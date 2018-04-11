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
      expect(ems.ems_folders.count).to eq(21)
      expect(ems.ems_folders.where(:type => "Datacenter").count).to eq(4)
      expect(ems.vms_and_templates.count).to eq(512)
      expect(ems.hosts.count).to eq(32)
      expect(ems.ems_clusters.count).to eq(8)
      expect(ems.resource_pools.count).to eq(72)
      expect(ems.hardwares.count).to eq(512)
      expect(ems.disks.count).to eq(512)
      expect(ems.guest_devices.count).to eq(512)
      expect(ems.operating_systems.count).to eq(512)
      expect(ems.host_operating_systems.count).to eq(32)
    end
  end
end
