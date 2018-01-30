require 'rbvmomi/vim'

describe ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser do
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
  let(:persister) { ems.class::Inventory::Persister.new(ems) }
  let(:parser)    { described_class.new(ems, persister) }

  context "#parse" do
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

        parser.parse(object_update)
      end

      it "VirtualMachine" do
        object_update = virtual_machine_enter_object_update

        parser.parse(object_update)
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
