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
  let(:collector) { described_class.new(ems) }

  context "#wait_for_updates" do
    it "Performs a full refresh" do
      2.times do
        # All VIM API calls go to uri https://hostname/sdk so we have to match on the body
        VCR.use_cassette(described_class.name.underscore, :match_requests_on => [:body]) do
          vim = collector.send(:connect, ems.hostname, ems.authentication_userid, ems.authentication_password)
          collector.send(:wait_for_updates, vim, :run_once => true)
          vim.close

          ems.reload

          assert_table_counts(ems)
          assert_specific_vm(ems)
        end
      end
    end

    def assert_table_counts(ems)
      expect(ems.ems_folders.count).to eq(21)
      expect(ems.ems_folders.where(:type => "Datacenter").count).to eq(4)
      expect(ems.vms_and_templates.count).to eq(512)
      expect(ems.hosts.count).to eq(32)
      expect(ems.ems_clusters.count).to eq(8)
      expect(ems.resource_pools.count).to eq(72)
      expect(ems.hardwares.count).to eq(512)
      # TODO: expect(ems.disks.count).to eq(512)
      # TODO: expect(ems.guest_devices.count).to eq(512)
      expect(ems.operating_systems.count).to eq(512)
      # TODO: expect(ems.host_operating_systems.count).to eq(32)
    end

    def assert_specific_vm(ems)
      vm = ems.vms.find_by(:ems_ref => "vm-17")

      expect(vm).to have_attributes(
        :vendor   => "vmware",
        :name     => "DC0_C0_RP0_VM1",
        :location => "DC0_C0_RP0_VM1/DC0_C0_RP0_VM1.vmx",
        :uid_ems  => "423d8331-b640-489f-e3be-61d33a04a258",
      )

      expect(vm.hardware).to have_attributes(
        :virtual_hw_version => "07",
        :memory_mb          => 64,
      )
    end
  end
end
