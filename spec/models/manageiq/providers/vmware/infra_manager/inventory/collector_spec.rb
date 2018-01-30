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
        end
      end
    end

    def assert_table_counts(ems)
      expect(ems.storages.count).to eq(4)
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

  context "#process_object_update (private)" do
    let(:root_folder)     { RbVmomi::VIM::Folder(nil, "group-d1") }
    let(:datacenter)      { RbVmomi::VIM::Datacenter(nil, "datacenter-1") }
    let(:virtual_machine) { RbVmomi::VIM::VirtualMachine(nil, "vm-1") }

    context "enter" do
      it "Folder" do
        object_update = RbVmomi::VIM::ObjectUpdate(
          :obj       => root_folder,
          :kind      => "enter",
          :changeSet => [
            RbVmomi::VIM::PropertyChange(:name => "childEntity", :op => "assign", :val => [datacenter]),
            RbVmomi::VIM::PropertyChange(:name => "name",        :op => "assign", :val => "Datacenters"),
            RbVmomi::VIM::PropertyChange(:name => "parent",      :op => "assign"),
          ]
        )

        _obj, props = collector.send(:process_object_update, object_update)

        expect(props).to have_attributes(
          "name"        => "Datacenters",
          "parent"      => nil,
          "childEntity" => [datacenter]
        )
      end

      it "VirtualMachine" do
        object_update = virtual_machine_enter_object_update

        _obj, props = collector.send(:process_object_update, object_update)
        expect(props).to have_attributes(
          "summary.config.uuid"       => "eaf4991e-ab31-4f86-9ec0-aeb5d5a27c33",
          "summary.config.name"       => "vm1",
          "summary.config.vmPathName" => "[datastore1] vm1/vm1.vmx",
          "summary.config.template"   => false,
        )
      end
    end

    context "modify" do
      context "Change the name of an existing vm" do
        before do
          object_update = virtual_machine_enter_object_update
          collector.send(:process_object_update, object_update)
        end

        it "Returns the changed name" do
          object_update = RbVmomi::VIM::ObjectUpdate(
            :obj       => virtual_machine,
            :kind      => "modify",
            :changeSet => [
              RbVmomi::VIM::PropertyChange(:name => "summary.config.name", :op => "assign", :val => "vm2"),
            ]
          )

          _obj, props = collector.send(:process_object_update, object_update)
          expect(props).to have_attributes(
            "summary.config.name" => "vm2"
          )
        end

        it "Merges the cached properties with the name change" do
          object_update = RbVmomi::VIM::ObjectUpdate(
            :obj       => virtual_machine,
            :kind      => "modify",
            :changeSet => [
              RbVmomi::VIM::PropertyChange(:name => "summary.config.name", :op => "assign", :val => "vm2"),
            ]
          )

          _obj, props = collector.send(:process_object_update, object_update)
          expect(props).to have_attributes(
            "summary.config.uuid"       => "eaf4991e-ab31-4f86-9ec0-aeb5d5a27c33",
            "summary.config.name"       => "vm2",
            "summary.config.vmPathName" => "[datastore1] vm1/vm1.vmx",
            "summary.config.template"   => false,
          )
        end
      end
    end

    def virtual_machine_enter_object_update
      RbVmomi::VIM::ObjectUpdate(
        :obj       => virtual_machine,
        :kind      => "enter",
        :changeSet => [
          RbVmomi::VIM::PropertyChange(:name => "summary.config.uuid",
                                       :op   => "assign",
                                       :val  => "eaf4991e-ab31-4f86-9ec0-aeb5d5a27c33"),
          RbVmomi::VIM::PropertyChange(:name => "summary.config.name",
                                       :op   => "assign",
                                       :val  => "vm1"),
          RbVmomi::VIM::PropertyChange(:name => "summary.config.vmPathName",
                                       :op   => "assign",
                                       :val  => "[datastore1] vm1/vm1.vmx"),
          RbVmomi::VIM::PropertyChange(:name => "summary.runtime.powerState",
                                       :op   => "assign",
                                       :val  => "poweredOff"),
          RbVmomi::VIM::PropertyChange(:name => "summary.config.template",
                                       :op   => "assign",
                                       :val  => false),
        ]
      )
    end
  end
end
