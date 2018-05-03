require 'rbvmomi/vim'

describe ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector do
  let(:ems) do
    _, _, zone = EvmSpecHelper.create_guid_miq_server_zone
    hostname = Rails.application.secrets.vmware.try(:[], "hostname") || "HOSTNAME"
    FactoryGirl.create(:ems_vmware_with_authentication, :hostname => hostname, :zone => zone).tap do |ems|
      # NOTE: VCR filter_sensitive_data was replacing rootFolder with VMWARE_USERNAME and
      # vmware_soap_string_abcdef with VMWARE_PASSWORD_string_abcdef, given these are the
      # default credentials for a virtual center this doesn't need to be hidden
      username = "root"
      password = "vmware"

      ems.update_authentication(:default => {:userid => username, :password => password})
    end
  end
  let(:collector) { described_class.new(ems, :run_once => true, :threaded => false) }

  context "#monitor_updates" do
    context "full refresh" do
      it "Performs a full refresh" do
        2.times do
          run_full_refresh
          ems.reload

          assert_ems
          assert_specific_datacenter
          assert_specific_folder
          assert_specific_host
          assert_specific_cluster
          assert_specific_resource_pool
          assert_specific_switch
          assert_specific_lan
          assert_specific_dvswitch
          assert_specific_dvportgroup
          assert_specific_vm
        end
      end
    end

    context "targeted refresh" do
      let(:vim)             { RbVmomi::VIM.new(:ns => "urn2", :rev => "6.5") }
      let(:property_filter) { RbVmomi::VIM.PropertyFilter(vim, "session[6f2dcefd-41de-6dfb-0160-1ee1cc024553]") }
      let(:cache)           { collector.send(:inventory_cache) }
      let(:persister)       { ems.class::Inventory::Persister::Targeted.new(ems) }
      let(:parser)          { ems.class::Inventory::Parser.new(cache, persister) }

      before do
        # Use the VCR to prime the cache and do the initial save_inventory
        run_full_refresh
      end

      it "doesn't impact unassociated inventory" do
        run_targeted_refresh(targeted_update_set([vm_power_on_object_update]))
        assert_ems
      end

      it "power on a virtual machine" do
        vm = ems.vms.find_by(:ems_ref => 'vm-107')

        expect(vm.power_state).to eq("off")
        run_targeted_refresh(targeted_update_set([vm_power_on_object_update]))
        expect(vm.reload.power_state).to eq("on")
      end

      it "migrate a virtual machine" do
        vm = ems.vms.find_by(:ems_ref => 'vm-107')

        expect(vm.host.ems_ref).to eq("host-93")
        run_targeted_refresh(targeted_update_set([vm_migrate_object_update]))
        expect(vm.reload.host.ems_ref).to eq("host-94")
      end

      it "deleting a virtual machine" do
        vm = ems.vms.find_by(:ems_ref => 'vm-107')

        expect(vm.archived?).to be_falsy
        run_targeted_refresh(targeted_update_set(vm_delete_object_updates))
        expect(vm.reload.archived?).to be_truthy
      end

      def run_targeted_refresh(update_set)
        update_set = collector.send(:process_update_set, property_filter, update_set)
        update_set.each { |managed_object, kind, props| parser.parse(managed_object, kind, props) }
        collector.send(:save_inventory, persister)
      end

      def targeted_update_set(object_updates)
        property_filter_update = RbVmomi::VIM.PropertyFilterUpdate(
          :filter    => property_filter,
          :objectSet => object_updates,
        )

        RbVmomi::VIM.UpdateSet(
          :version   => "1",
          :filterSet => [property_filter_update],
          :truncated => false,
        )
      end

      def vm_power_on_object_update
        RbVmomi::VIM.ObjectUpdate(
          :dynamicProperty => [],
          :kind            => "modify",
          :obj             => RbVmomi::VIM.VirtualMachine(vim, "vm-107"),
          :changeSet       => [
            RbVmomi::VIM.PropertyChange(:name => "config.hotPlugMemoryIncrementSize", :op => "assign"),
            RbVmomi::VIM.PropertyChange(:name => "config.hotPlugMemoryLimit",         :op => "assign"),
            RbVmomi::VIM.PropertyChange(:name => "summary.runtime.powerState",        :op => "assign", :val => "poweredOn"),
            RbVmomi::VIM.PropertyChange(:name => "summary.storage.committed",         :op => "assign", :val => 210_930),
            RbVmomi::VIM.PropertyChange(:name => "summary.storage.unshared",          :op => "assign", :val => 0),
          ],
          :missingSet      => [],
        )
      end

      def vm_migrate_object_update
        RbVmomi::VIM.ObjectUpdate(
          :dynamicProperty => [],
          :kind            => "modify",
          :obj             => RbVmomi::VIM.VirtualMachine(vim, "vm-107"),
          :changeSet       => [
            RbVmomi::VIM.PropertyChange(:name => "summary.runtime.host", :op => "assign", :val => RbVmomi::VIM.HostSystem(vim, "host-94")),
          ],
          :missingSet      => [],
        )
      end

      def vm_delete_object_updates
        [
          RbVmomi::VIM.ObjectUpdate(
            :dynamicProperty => [],
            :kind            => "leave",
            :obj             => RbVmomi::VIM.VirtualMachine(vim, "vm-107"),
            :changeSet       => [],
            :missingSet      => [],
          ),
          RbVmomi::VIM.ObjectUpdate(
            :dynamicProperty => [],
            :kind            => "modify",
            :obj             => RbVmomi::VIM.ClusterComputeResource(vim, "domain-c91"),
            :changeSet       => [
              RbVmomi::VIM.PropertyChange(
                :dynamicProperty => [],
                :name            => "summary.effectiveCpu",
                :op              => "assign",
                :val             => 47_983,
              ),
              RbVmomi::VIM.PropertyChange(
                :dynamicProperty => [],
                :name            => "summary.effectiveMemory",
                :op              => "assign",
                :val             => 59_871,
              ),
            ],
            :missingSet      => [],
          ),
        ]
      end
    end

    def run_full_refresh
      # All VIM API calls go to uri https://hostname/sdk so we have to match on the body
      VCR.use_cassette(described_class.name.underscore, :match_requests_on => [:body]) do
        collector.run
      end
    end

    def assert_ems
      expect(ems.api_version).to eq("5.5")
      expect(ems.uid_ems).to eq("D6EB1D64-05B2-4937-BFF6-6F77C6E647B7")
      expect(ems.ems_clusters.count).to eq(8)
      expect(ems.ems_folders.count).to eq(21)
      expect(ems.ems_folders.where(:type => "Datacenter").count).to eq(4)
      expect(ems.disks.count).to eq(512)
      expect(ems.guest_devices.count).to eq(512)
      expect(ems.hardwares.count).to eq(512)
      expect(ems.hosts.count).to eq(32)
      expect(ems.host_operating_systems.count).to eq(32)
      expect(ems.operating_systems.count).to eq(512)
      expect(ems.resource_pools.count).to eq(72)
      expect(ems.storages.count).to eq(1)
      expect(ems.vms_and_templates.count).to eq(512)
      expect(ems.switches.count).to eq(36)
      expect(ems.host_virtual_switches.count).to eq(32)
      expect(ems.distributed_virtual_switches.count).to eq(4)
      expect(ems.lans.count).to eq(76)
    end

    def assert_specific_datacenter
      datacenter = ems.ems_folders.find_by(:ems_ref => "datacenter-2")

      expect(datacenter).not_to be_nil
      expect(datacenter).to have_attributes(
        :ems_ref => "datacenter-2",
        :name    => "DC0",
        :type    => "Datacenter",
        :uid_ems => "datacenter-2",
      )

      expect(datacenter.parent.ems_ref).to eq("group-d1")

      expect(datacenter.children.count).to eq(4)
      expect(datacenter.children.map(&:name)).to match_array(%w(host network datastore vm))
    end

    def assert_specific_folder
      folder = ems.ems_folders.find_by(:ems_ref => "group-d1")

      expect(folder).not_to be_nil
      expect(folder).to have_attributes(
        :ems_ref => "group-d1",
        :name    => "Datacenters",
        :uid_ems => "group-d1",
      )

      expect(folder.parent).to be_nil
      expect(folder.children.count).to eq(4)
      expect(folder.children.map(&:name)).to match_array(%w(DC0 DC1 DC2 DC3))
    end

    def assert_specific_host
      host = ems.hosts.find_by(:ems_ref => "host-14")

      expect(host).not_to be_nil

      expect(host.parent).not_to be_nil
      expect(host.parent.ems_ref).to eq("domain-c12")

      switch = host.host_virtual_switches.find_by(:uid_ems => "vSwitch0")

      expect(switch).not_to be_nil
      expect(switch).to have_attributes(
        :name              => "vSwitch0",
        :uid_ems           => "vSwitch0",
        :ports             => 64,
        :allow_promiscuous => false,
        :forged_transmits  => true,
        :mac_changes       => true,
        :mtu               => 1500,
        :type              => "ManageIQ::Providers::Vmware::InfraManager::HostVirtualSwitch",
      )

      vnic = host.hardware.guest_devices.find_by(:uid_ems => "vmnic0")
      expect(vnic).not_to be_nil
      expect(vnic).to have_attributes(
        :device_name     => "vmnic0",
        :device_type     => "ethernet",
        :location        => "03:00.0",
        :controller_type => "ethernet",
        :uid_ems         => "vmnic0",
        # TODO: :switch          => switch,
      )
    end

    def assert_specific_cluster
      cluster = ems.ems_clusters.find_by(:ems_ref => "domain-c12")

      expect(cluster).not_to be_nil
      expect(cluster).to have_attributes(
        :drs_automation_level    => "manual",
        :drs_enabled             => true,
        :drs_migration_threshold => 3,
        :effective_cpu           => 47_984,
        :effective_memory        => 62_780_342_272,
        :ems_ref                 => "domain-c12",
        :ha_admit_control        => true,
        :ha_enabled              => false,
        :ha_max_failures         => 1,
        :name                    => "DC0_C0",
        :uid_ems                 => "domain-c12",
      )

      expect(cluster.parent).not_to be_nil
      expect(cluster.parent.ems_ref).to eq("group-h4")

      expect(cluster.children.count).to eq(5)
      expect(cluster.default_resource_pool.ems_ref).to eq("resgroup-13")
    end

    def assert_specific_resource_pool
      resource_pool = ems.resource_pools.find_by(:ems_ref => "resgroup-92")

      expect(resource_pool).not_to be_nil
      expect(resource_pool).to have_attributes(
        :cpu_limit             => 47_984,
        :cpu_reserve           => 47_984,
        :cpu_reserve_expand    => true,
        :cpu_shares            => 4_000,
        :cpu_shares_level      => nil,
        :memory_limit          => 59_872,
        :memory_reserve        => 59_872,
        :memory_reserve_expand => true,
        :memory_shares         => 163_840,
        :memory_shares_level   => "normal",
        :name                  => "Resources",
        :vapp                  => false,
      )

      expect(resource_pool.parent.ems_ref).to eq("domain-c91")

      expect(resource_pool.children.count).to eq(8)
      expect(resource_pool.children.map(&:ems_ref)).to match_array(
        %w(resgroup-106 resgroup-115 resgroup-124 resgroup-133 resgroup-142 resgroup-151 resgroup-160 resgroup-97)
      )
    end

    def assert_specific_switch
      host = ems.hosts.find_by(:ems_ref => "host-14")
      switch = host.switches.find_by(:name => "vSwitch0")

      expect(switch).not_to be_nil
      expect(switch).to have_attributes(
        :name              => "vSwitch0",
        :ports             => 64,
        :uid_ems           => "vSwitch0",
        :allow_promiscuous => false,
        :forged_transmits  => true,
        :mac_changes       => true,
        :mtu               => 1500,
      )

      expect(switch.lans.count).to eq(2)
      expect(switch.hosts.count).to eq(1)
    end

    def assert_specific_lan
      host = ems.hosts.find_by(:ems_ref => "host-14")
      switch = host.switches.find_by(:name => "vSwitch0")
      lan = switch.lans.find_by(:uid_ems => "VM Network")

      expect(lan).not_to be_nil
      expect(lan).to have_attributes(
        :name                       => "VM Network",
        :uid_ems                    => "VM Network",
        :tag                        => "0",
        :allow_promiscuous          => false,
        :forged_transmits           => true,
        :mac_changes                => true,
        :computed_allow_promiscuous => false,
        :computed_forged_transmits  => true,
        :computed_mac_changes       => true,
      )

      expect(lan.switch.uid_ems).to eq("vSwitch0")
    end

    def assert_specific_dvswitch
      dvs = ems.distributed_virtual_switches.find_by(:uid_ems => "dvs-8")

      expect(dvs).not_to be_nil
      expect(dvs).to have_attributes(
        :uid_ems           => "dvs-8",
        :name              => "DC0_DVS",
        :ports             => 288,
        :switch_uuid       => "4e 1f 2b 50 19 20 4c f7-f3 11 41 90 35 76 52 7b",
        :type              => "ManageIQ::Providers::Vmware::InfraManager::DistributedVirtualSwitch",
        :allow_promiscuous => false,
        :forged_transmits  => false,
        :mac_changes       => false,
      )

      expect(dvs.lans.count).to eq(3)
      expect(dvs.hosts.count).to eq(8)
    end

    def assert_specific_dvportgroup
      lan = ems.lans.find_by(:uid_ems => "dvportgroup-10")

      expect(lan).not_to be_nil
      expect(lan).to have_attributes(
        :name              => "DC0_DVPG0",
        :uid_ems           => "dvportgroup-10",
        :allow_promiscuous => false,
        :forged_transmits  => false,
        :mac_changes       => false,
        :tag               => nil,
      )

      expect(lan.switch.uid_ems).to eq("dvs-8")
    end

    def assert_specific_vm
      vm = ems.vms.find_by(:ems_ref => "vm-21")

      expect(vm).to have_attributes(
        :connection_state      => "connected",
        :cpu_reserve           => 0,
        :cpu_reserve_expand    => false,
        :cpu_limit             => -1,
        :cpu_shares            => 1000,
        :cpu_shares_level      => "normal",
        :cpu_affinity          => nil,
        :ems_ref               => "vm-21",
        :location              => "DC0_C0_RP0_VM1/DC0_C0_RP0_VM1.vmx",
        :memory_reserve        => 0,
        :memory_reserve_expand => false,
        :memory_limit          => -1,
        :memory_shares         => 640,
        :memory_shares_level   => "normal",
        :name                  => "DC0_C0_RP0_VM1",
        :raw_power_state       => "poweredOn",
        :type                  => "ManageIQ::Providers::Vmware::InfraManager::Vm",
        :uid_ems               => "422bf630-7e83-c7dd-f226-56b41f3c50ef",
        :vendor                => "vmware",
      )

      expect(vm.hardware).to have_attributes(
        :bios                 => "422bf630-7e83-c7dd-f226-56b41f3c50ef",
        :cpu_cores_per_socket => 1,
        :cpu_sockets          => 1,
        :cpu_total_cores      => 1,
        :virtual_hw_version   => "07",
      )

      expect(vm.disks.count).to eq(1)

      disk = vm.disks.first
      expect(disk).to have_attributes(
        :controller_type => "scsi",
        :device_name     => "Hard disk 1",
        :device_type     => "disk",
        :disk_type       => "thick",
        :filename        => "[GlobalDS_0] DC0_C0_RP0_VM1/DC0_C0_RP0_VM1.vmdk",
        :location        => "0:0",
        :mode            => "persistent",
        :size            => 536_870_912,
        :start_connected => true,
      )

      expect(vm.ems_cluster).not_to be_nil
      expect(vm.ems_cluster.ems_ref).to eq("domain-c12")

      expect(vm.host).not_to be_nil
      expect(vm.host.ems_ref).to eq("host-17")

      expect(vm.parent_blue_folder).not_to be_nil
      expect(vm.parent_blue_folder.ems_ref).to eq("group-v3")

      expect(vm.parent_yellow_folder).not_to be_nil
      expect(vm.parent_yellow_folder.ems_ref).to eq("group-d1")

      expect(vm.parent_resource_pool).not_to be_nil
      expect(vm.parent_resource_pool.ems_ref).to eq("resgroup-19")
    end
  end
end
