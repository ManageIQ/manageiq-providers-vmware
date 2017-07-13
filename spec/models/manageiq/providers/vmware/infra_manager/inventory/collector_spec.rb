describe ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector do
  let(:ems) { FactoryGirl.create(:ems_vmware_with_authentication) }
  let(:collector) { described_class.new(ems) }

  context "#process_object_update" do
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

        props = collector.process_object_update(object_update)

        expect(props).to have_attributes(
          "name"        => "Datacenters",
          "parent"      => nil,
          "childEntity" => [datacenter]
        )
      end

      it "VirtualMachine" do
        object_update = virtual_machine_enter_object_update

        props = collector.process_object_update(object_update)
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
          collector.process_object_update(object_update)
        end

        it "Returns the changed name" do
          object_update = RbVmomi::VIM::ObjectUpdate(
            :obj       => virtual_machine,
            :kind      => "modify",
            :changeSet => [
              RbVmomi::VIM::PropertyChange(:name => "summary.config.name", :op => "assign", :val => "vm2"),
            ]
          )

          props = collector.process_object_update(object_update)
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

          props = collector.process_object_update(object_update)
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
