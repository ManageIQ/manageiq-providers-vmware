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

          assert_table_counts
          assert_specific_datacenter
          assert_specific_folder
          assert_specific_cluster
          assert_specific_resource_pool
          assert_specific_switch
          assert_specific_lan
          assert_specific_vm
        end
      end
    end

    context "targeted refresh" do
      let(:vim)             { RbVmomi::VIM.new(:ns => "urn2", :rev => "6.5") }
      let(:property_filter) { RbVmomi::VIM.PropertyFilter(vim, "session[6f2dcefd-41de-6dfb-0160-1ee1cc024553]") }
      let(:persister)       { ems.class::Inventory::Persister::Targeted.new(ems) }
      let(:parser)          { ems.class::Inventory::Parser.new(persister) }

      before do
        # Use the VCR to prime the cache and do the initial save_inventory
        run_full_refresh
      end

      it "doesn't impact unassociated inventory" do
        run_targeted_refresh(targeted_update_set(vm_power_on_object_update))
        assert_table_counts
      end

      it "power on a virtual machine" do
        vm = ems.vms.find_by(:ems_ref => 'vm-107')

        expect(vm.power_state).to eq("off")
        run_targeted_refresh(targeted_update_set(vm_power_on_object_update))
        expect(vm.reload.power_state).to eq("on")
      end

      def run_targeted_refresh(update_set)
        collector.send(:process_update_set, property_filter, update_set, parser)
        collector.send(:save_inventory, persister)
      end

      def targeted_update_set(object_update)
        property_filter_update = RbVmomi::VIM.PropertyFilterUpdate(
          :filter    => property_filter,
          :objectSet => [object_update],
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
    end

    def run_full_refresh
      # All VIM API calls go to uri https://hostname/sdk so we have to match on the body
      VCR.use_cassette(described_class.name.underscore, :match_requests_on => [:body]) do
        collector.monitor_updates
      end
    end

    def assert_table_counts
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

      # TODO: check relationships
    end

    def assert_specific_folder
      folder = ems.ems_folders.find_by(:ems_ref => "group-d1")

      expect(folder).not_to be_nil
      expect(folder).to have_attributes(
        :ems_ref => "group-d1",
        :name    => "Datacenters",
        :uid_ems => "group-d1",
      )

      # TODO: check relationships
    end

    def assert_specific_cluster
      cluster = ems.ems_clusters.find_by(:ems_ref => "domain-c87")

      expect(cluster).not_to be_nil
      expect(cluster).to have_attributes(
        :drs_automation_level    => "manual",
        :drs_enabled             => true,
        :drs_migration_threshold => 3,
        :effective_cpu           => 47_992,
        :effective_memory        => 68_698_505_216,
        :ems_ref                 => "domain-c87",
        :ha_admit_control        => true,
        :ha_enabled              => false,
        :ha_max_failures         => 1,
        :name                    => "DC0_C1",
        :uid_ems                 => "domain-c87",
      )
    end

    def assert_specific_resource_pool
      resource_pool = ems.resource_pools.find_by(:ems_ref => "resgroup-88")

      expect(resource_pool).not_to be_nil
      expect(resource_pool).to have_attributes(
        :cpu_limit             => 47_992,
        :cpu_reserve           => 47_992,
        :cpu_reserve_expand    => true,
        :cpu_shares            => 4_000,
        :cpu_shares_level      => nil,
        :memory_limit          => 65_516,
        :memory_reserve        => 65_516,
        :memory_reserve_expand => true,
        :memory_shares         => 163_840,
        :memory_shares_level   => "normal",
        :name                  => "Resources",
        :vapp                  => false,
      )
    end

    def assert_specific_switch
      # TODO: check a switch
    end

    def assert_specific_lan
      # TODO: check a lan
    end

    def assert_specific_vm
      vm = ems.vms.find_by(:ems_ref => "vm-17")

      expect(vm).to have_attributes(
        :connection_state      => "connected",
        :cpu_reserve           => 0,
        :cpu_reserve_expand    => false,
        :cpu_limit             => -1,
        :cpu_shares            => 1000,
        :cpu_shares_level      => "normal",
        :cpu_affinity          => nil,
        :ems_ref               => "vm-17",
        :location              => "DC0_C0_RP0_VM1/DC0_C0_RP0_VM1.vmx",
        :memory_reserve        => 0,
        :memory_reserve_expand => false,
        :memory_limit          => -1,
        :memory_shares         => 640,
        :memory_shares_level   => "normal",
        :name                  => "DC0_C0_RP0_VM1",
        :raw_power_state       => "poweredOn",
        :type                  => "ManageIQ::Providers::Vmware::InfraManager::Vm",
        :uid_ems               => "423d8331-b640-489f-e3be-61d33a04a258",
        :vendor                => "vmware",
      )

      expect(vm.hardware).to have_attributes(
        :bios                 => "423d8331-b640-489f-e3be-61d33a04a258",
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

      expect(vm.host).not_to be_nil
      expect(vm.host.ems_ref).to eq("host-12")
    end
  end
end
