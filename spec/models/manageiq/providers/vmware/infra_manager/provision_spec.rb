require 'VMwareWebService/VimTypes'

describe ManageIQ::Providers::Vmware::InfraManager::Provision do
  context "A new provision request," do
    before(:each) do
      @os = OperatingSystem.new(:product_name => 'Microsoft Windows')
      @admin = FactoryBot.create(:user_admin)
      @target_vm_name = 'clone test'
      @options = {
        :pass                   => 1,
        :vm_name                => @target_vm_name,
        :number_of_vms          => 1,
        :cpu_limit              => -1,
        :cpu_reserve            => 0,
        :allocated_disk_storage => 16
      }
    end

    context "VMware provisioning" do
      before(:each) do
        @ems         = FactoryBot.create(:ems_vmware_with_authentication, :api_version => '6.0')
        @vm_template = FactoryBot.create(:template_vmware, :name => "template1", :ext_management_system => @ems, :operating_system => @os, :cpu_limit => -1, :cpu_reserve => 0)
        @vm          = FactoryBot.create(:vm_vmware, :name => "vm1", :location => "abc/def.vmx")
        @pr          = FactoryBot.create(:miq_provision_request, :requester => @admin, :src_vm_id => @vm_template.id)
        @options[:src_vm_id] = [@vm_template.id, @vm_template.name]
        @vm_prov = FactoryBot.create(:miq_provision_vmware, :userid => @admin.userid, :miq_request => @pr, :source => @vm_template, :request_type => 'template', :state => 'pending', :status => 'Ok', :options => @options)
      end

      it "#workflow" do
        workflow_class = ManageIQ::Providers::Vmware::InfraManager::ProvisionWorkflow
        allow_any_instance_of(workflow_class).to receive(:get_dialogs).and_return(:dialogs => {})

        expect(@vm_prov.workflow.class).to eq workflow_class
        expect(@vm_prov.workflow_class).to eq workflow_class
      end

      it "should return a config spec" do
        @vm_prov.options.merge!(:vm_memory => '1024', :number_of_cpus => 2)
        @vm_prov.phase_context[:new_vm_validation_guid] = "12345"
        @vm_prov.destination = @vm_template
        expect(@vm_prov).to receive(:build_config_network_adapters)
        spec = @vm_prov.build_config_spec
        expect(spec).to be_kind_of(VimHash)
        expect(spec.xsiType).to eq('VirtualMachineConfigSpec')
        expect(spec["memoryMB"]).to eq(1024)
        expect(spec["numCPUs"]).to eq(2)
        expect(spec["annotation"]).to include(@vm_prov.phase_context[:new_vm_validation_guid])
      end

      describe "disk_relocate_spec" do
        let(:device_list) { [VimHash.new("VirtualDisk") { |d| d.key = "2000" }, VimHash.new("NotAVirtualDisk") { |d| d.key = "2001" }] }

        it "thin" do
          expect(@vm_prov).to receive(:disks).and_return(device_list)
          @vm_prov.options[:disk_format] = 'thin'
          spec = @vm_prov.build_disk_relocate_spec('datastore-1729')
          expect(spec).to be_kind_of(VimArray)
          expect(spec.first.diskBackingInfo.thinProvisioned).to eq("true")
        end

        it "thick lazy zero" do
          expect(@vm_prov).to receive(:disks).and_return(device_list)
          @vm_prov.options[:disk_format] = 'thick'
          spec = @vm_prov.build_disk_relocate_spec('datastore-1729')
          expect(spec).to be_kind_of(VimArray)
          expect(spec.first.diskBackingInfo.eagerlyScrub).to eq("false")
          expect(spec.first.diskBackingInfo.thinProvisioned).to eq("false")
        end

        it "thick eager zero" do
          expect(@vm_prov).to receive(:disks).and_return(device_list)
          @vm_prov.options[:disk_format] = 'thick_eager'
          spec = @vm_prov.build_disk_relocate_spec('datastore-1729')
          expect(spec).to be_kind_of(VimArray)
          expect(spec.first.diskBackingInfo.thinProvisioned).to eq("false")
          expect(spec.first.diskBackingInfo.eagerlyScrub).to eq("true")
        end
      end

      it "should detect when reconfigure container or disk calls are required" do
        target_vm1 = FactoryBot.create(:vm_vmware, :name => "target_vm1", :location => "abc/def.vmx", :cpu_limit => @vm_prov.options[:cpu_limit],
                                      :hardware => FactoryBot.create(:hardware, :disks => FactoryBot.create(:disks, [:device_type => "disk", :size => 16 * 1.gigabyte])))
        target_vm2 = FactoryBot.create(:vm_vmware, :name => "target_vm1", :location => "abc/def.vmx", :cpu_limit => @vm_prov.options[:cpu_limit],
                                       :hardware => FactoryBot.create(:hardware, :disks => FactoryBot.create(:disks, [{:device_type => "disk", :size => 16 * 1.gigabyte},
                                                                                                                      {:device_type => "disk", :size => 16 * 1.gigabyte}])))
        @vm_prov.destination = target_vm1
        expect(@vm_prov.reconfigure_container_on_destination?).to eq(false)
        @vm_prov.options[:cpu_limit] = 100
        expect(@vm_prov.reconfigure_container_on_destination?).to eq(true)
        @vm_prov.options[:allocated_disk_storage] = 20
        expect(@vm_prov.reconfigure_disk_on_destination?).to eq(true)
        @vm_prov.destination = target_vm2
        expect(@vm_prov.reconfigure_disk_on_destination?).to eq(false)
      end

      it "should delete unneeded network cards" do
        requested_networks = [{:network => "Build", :devicetype => "VirtualE1000"}, {:network => "Enterprise", :devicetype => "VirtualE1000"}]
        template_networks  = [{"connectable" => {"startConnected" => "true"}, "unitNumber" => "7", "controllerKey" => "100", "addressType" => "assigned", "macAddress" => "00:50:56:af:00:50", "deviceInfo" => {"label" => "Network adapter 1", "summary" => "VM Network"}, "backing" => {"deviceName" => "VM Network", "network" => "network-658"}, "key" => "4000"}]

        allow(@vm_prov).to receive(:normalize_network_adapter_settings).and_return(requested_networks)
        allow(@vm_prov).to receive(:get_network_adapters).and_return(template_networks)
        expect(@vm_prov).to receive(:build_config_spec_vlan).twice

        vmcs = VimHash.new("VirtualMachineConfigSpec")
        expect { @vm_prov.build_config_network_adapters(vmcs) }.not_to raise_error
      end

      it "should replace network card backing" do
        requested_network = {:network => "Prod", :devicetype => "VirtualE1000"}
        template_network  = VimHash.new("VirtualVmxnet3") do |vnic|
          vnic.backing       = VimHash.new("VirtualEthernetCardDistributedVirtualPortBackingInfo") do |backing|
            backing.port = VimHash.new("DistributedVirtualSwitchPortConnection") do |dvs_port|
              dvs_port.portKey      = "1"
              dvs_port.portgroupKey = "dvportgroup-17"
              dvs_port.switchUuid   = "50 3c b7 67 59 58 cf ce-75 16 2f e0 2b 6a d8 3c"
            end
          end
        end

        allow(@vm_prov).to receive(:normalize_network_adapter_settings).and_return([requested_network])
        allow(@vm_prov).to receive(:get_network_adapters).and_return([template_network])

        vmcs = VimHash.new("VirtualMachineConfigSpec")
        @vm_prov.build_config_network_adapters(vmcs)
        expect(vmcs["deviceChange"][0]["device"]["backing"].xsiType).to eq("VirtualEthernetCardNetworkBackingInfo")
      end

      it "should change the device type of existing network cards" do
        requested_networks = [{:network => "Enterprise", :devicetype => "VirtualVmxnet3"}]
        template_networks  = [
          VimHash.new("VirtualE1000")  do |vnic|
            vnic.backing = VimHash.new("VirtualEthernetCardNetworkBackingInfo")
          end
        ]

        allow(@vm_prov).to receive(:normalize_network_adapter_settings).and_return(requested_networks)
        allow(@vm_prov).to receive(:get_network_adapters).and_return(template_networks)

        vmcs = VimHash.new("VirtualMachineConfigSpec")
        @vm_prov.build_config_network_adapters(vmcs)

        expect(vmcs.deviceChange[0].device.xsiType).to eq("VirtualVmxnet3")
      end

      it "eligible_hosts" do
        host = FactoryBot.create(:host, :ext_management_system => @ems)
        host_struct = [MiqHashStruct.new(:id => host.id, :evm_object_class => host.class.base_class.name.to_sym)]
        allow_any_instance_of(MiqProvisionWorkflow).to receive(:allowed_hosts).and_return(host_struct)
        expect(@vm_prov.eligible_resources(:hosts)).to eq([host])
      end

      it "eligible_resources with bad resource" do
        expect { @vm_prov.eligible_resources(:bad_resource_name) }.to raise_error(NameError)
      end

      it "disable customization_spec" do
        expect(@vm_prov).to receive(:disable_customization_spec).once
        expect(@vm_prov.set_customization_spec(nil)).to be_truthy
      end

      context "with destination VM" do
        before(:each) do
          @vm_prov.destination = Vm.first
          @vm_prov.destination.ext_management_system = @ems
          allow(@vm_prov).to receive(:my_zone).and_return("default")
        end

        it "autostart_destination, vm_auto_start disabled" do
          expect(@vm_prov.destination).not_to receive(:raw_start)
          expect(@vm_prov).to receive(:post_create_destination)
          @vm_prov.signal :autostart_destination
        end

        it "autostart_destination" do
          @vm_prov.options[:vm_auto_start] = true
          expect(@vm_prov.destination).to receive(:raw_start)
          expect(@vm_prov).to receive(:post_create_destination)
          @vm_prov.signal :autostart_destination
        end

        it "autostart_destination with a vm cache error requeues the phase" do
          @vm_prov.options[:vm_auto_start] = true
          allow(@vm_prov.destination).to receive(:raw_start).and_raise(MiqException::MiqVimResourceNotFound)
          expect(@vm_prov).not_to receive(:post_create_destination)
          expect(@vm_prov).to receive(:requeue_phase)
          @vm_prov.signal :autostart_destination
        end

        it "autostart_destination with error" do
          @vm_prov.options[:vm_auto_start] = true
          allow(@vm_prov.destination).to receive(:raw_start).and_raise
          expect(@vm_prov.destination).to receive(:raw_start).once
          @vm_prov.signal :autostart_destination
        end
      end

      context "#dest_folder" do
        let(:user_folder) { FactoryBot.create(:ems_folder) }

        let(:dc) do
          FactoryBot.create(:datacenter).tap do |f|
            f.parent = FactoryBot.create(:ems_folder, :name => 'Datacenters').tap { |d| d.parent = @ems; }
          end
        end

        let(:dc_nested) do
          EvmSpecHelper::EmsMetadataHelper.vmware_nested_folders(@ems)
        end

        let(:vm_folder_nested) do
          FactoryBot.create(:ems_folder, :name => 'vm', :ems_id => @ems.id).tap { |v| v.parent = dc_nested }
        end

        let(:vm_folder) do
          FactoryBot.create(:ems_folder, :name => 'vm', :ems_id => @ems.id).tap { |v| v.parent = dc }
        end

        let(:dest_host_nested) do
          FactoryBot.create(:host_vmware, :ext_management_system => @ems).tap { |h| h.parent = dc_nested }
        end

        let(:dest_host) do
          FactoryBot.create(:host_vmware, :ext_management_system => @ems).tap { |h| h.parent = dc }
        end

        it "uses folder set from option" do
          @vm_prov.options[:placement_folder_name] = [user_folder.id, user_folder.name]
          expect(@vm_prov.dest_folder).to eq(user_folder)
        end

        it "correctly locates a nested folder in destination host" do
          @vm_prov.options[:dest_host] = [dest_host_nested.id, dest_host_nested.name]
          parent_datacenter = dest_host_nested.parent_datacenter
          expect(parent_datacenter.folder_path).to eq("Datacenters/nested/testing/#{parent_datacenter.name}")
        end

        it "uses vm folder in destination host" do
          vm_folder
          @vm_prov.options[:dest_host] = [dest_host.id, dest_host.name]
          expect(@vm_prov.dest_folder).to eq(vm_folder)
        end
      end

      context "#dest_resource_pool" do
        let(:resource_pool) { FactoryBot.create(:resource_pool) }

        let(:dest_host) do
          host = FactoryBot.create(:host_vmware, :ext_management_system => @ems)
          FactoryBot.create(:resource_pool).parent = host
          host
        end

        let(:cluster) do
          cluster = FactoryBot.create(:ems_cluster)
          FactoryBot.create(:resource_pool).parent = cluster
        end

        let(:dest_host_with_cluster) { FactoryBot.create(:host_vmware, :ems_cluster => cluster) }

        it "uses the resource pool from options" do
          @vm_prov.options[:placement_rp_name] = resource_pool.id
          expect(@vm_prov.dest_resource_pool).to eq(resource_pool)
        end

        it "returns a resource_pool if one is passed in" do
          expect(ResourcePool).to receive(:find_by).and_return(:resource_pool)
          expect(cluster).to receive(:default_resource_pool).never
          @vm_prov.dest_resource_pool
        end

        it "uses the resource pool from the cluster" do
          @vm_prov.options[:dest_host]    = [dest_host_with_cluster.id, dest_host_with_cluster.name]
          @vm_prov.options[:dest_cluster] = [cluster.id, cluster.name]
          expect(@vm_prov.dest_resource_pool).to eq(cluster.default_resource_pool)
        end

        it "uses the resource pool from destination host" do
          @vm_prov.options[:dest_host] = [dest_host.id, dest_host.name]
          expect(@vm_prov.dest_resource_pool).to eq(dest_host.default_resource_pool)
        end
      end

      context "#dest_storage_profile" do
        let(:storage_profile) { FactoryBot.create(:storage_profile, :name => "Gold") }

        it "returns nil if no placement_storage_profile is given" do
          @vm_prov.options[:placement_storage_profile] = nil
          expect(@vm_prov.dest_storage_profile).to be_nil
        end

        it "returns a storage profile" do
          @vm_prov.options[:placement_storage_profile] = [storage_profile.id, storage_profile.name]
          expect(@vm_prov.dest_storage_profile).to eq(storage_profile)
        end
      end

      context "#start_clone" do
        before(:each) do
          Array.new(2) do |i|
            ds_mor = "datastore-#{i}"
            storage = FactoryBot.create(:storage_vmware, :ems_ref => ds_mor, :ems_ref_type => "Datastore")

            cluster_mor = "cluster-#{i}"
            cluster     = FactoryBot.create(:ems_cluster, :ems_ref => cluster_mor)

            host_mor = "host-#{i}"
            host_props = {
              :ext_management_system => @ems,
              :ems_cluster           => cluster,
              :ems_ref               => host_mor,
              :ems_ref_type          => "HostSystem"
            }

            FactoryBot.create(:host_vmware, host_props).tap do |host|
              host.storages = [storage]
              hs = host.host_storages.first
              hs.save
            end
          end
        end

        it "uses the ems_ref for the correct host" do
          dest_host_mor      = "host-1"
          dest_datastore_mor = "datastore-1"
          task_mor           = "task-1"

          host = Host.find_by(:ems_ref => dest_host_mor)
          clone_opts = {
            :name      => @target_vm_name,
            :host      => host,
            :datastore => host.storages.first
          }

          expected_vim_clone_opts = {
            :name          => @target_vm_name,
            :wait          => false,
            :template      => false,
            :config        => nil,
            :customization => nil,
            :linked_clone  => nil,
            :host          => dest_host_mor,
            :datastore     => dest_datastore_mor,
            :disk          => []
          }

          expect(@vm_prov).to receive(:disks).and_return([])
          allow(@vm_prov).to receive(:clone_vm).with(expected_vim_clone_opts).and_return(task_mor)

          result = @vm_prov.start_clone clone_opts
          expect(result).to eq(task_mor)
        end

        it "uses the right ems_ref when given a cluster" do
          dest_cluster_mor   = "cluster-1"
          dest_datastore_mor = "datastore-1"
          task_mor           = "task-1"

          cluster = EmsCluster.find_by(:ems_ref => dest_cluster_mor)
          clone_opts = {
            :name      => @target_vm_name,
            :cluster   => cluster,
            :datastore => cluster.storages.first
          }

          expected_vim_clone_opts = {
            :name          => @target_vm_name,
            :wait          => false,
            :template      => false,
            :config        => nil,
            :customization => nil,
            :linked_clone  => nil,
            :datastore     => dest_datastore_mor,
            :disk          => []
          }

          expect(@vm_prov).to receive(:disks).and_return([])
          allow(@vm_prov).to receive(:clone_vm).with(expected_vim_clone_opts).and_return(task_mor)

          result = @vm_prov.start_clone clone_opts
          expect(result).to eq(task_mor)
        end
      end

      describe '#get_next_vm_name' do
        before do
          @vm_prov.update(:options => @options.merge(:miq_force_unique_name => true))
          allow(MiqRegion).to receive_message_chain('my_region.next_naming_sequence').and_return(123)
        end

        it 'does not add "_" in name' do
          allow(MiqAeEngine).to receive(:resolve_automation_object).and_return(double(:root => 'myvm'))
          expect(@vm_prov.get_next_vm_name).to eq('myvm0123')
        end

        it 'keeps "_" in name' do
          allow(MiqAeEngine).to receive(:resolve_automation_object).and_return(double(:root => 'myvm_'))
          expect(@vm_prov.get_next_vm_name).to eq('myvm_0123')
        end
      end
    end
  end
end
