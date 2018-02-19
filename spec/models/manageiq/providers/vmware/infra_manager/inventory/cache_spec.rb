require "rbvmomi/vim"

describe ManageIQ::Providers::Vmware::InfraManager::Inventory::Cache do
  let(:cache) { described_class.new }
  let(:vm) { RbVmomi::VIM.VirtualMachine(nil, "vm-123") }
  let(:device) do
    [
      RbVmomi::VIM::VirtualLsiLogicController(
        :dynamicProperty    => [],
        :key                => 1000,
        :deviceInfo         => RbVmomi::VIM::Description(:label => "SCSI controller 0", :summary => "LSI Logic"),
        :controllerKey      => 100,
        :unitNumber         => 3,
        :busNumber          => 0,
        :device             => [2000],
        :hotAddRemove       => true,
        :sharedBus          => "noSharing",
        :scsiCtlrUnitNumber => 7,
      ),
      RbVmomi::VIM::VirtualDisk(
        :dynamicProperty => [],
        :key             => 2000,
        :deviceInfo      => RbVmomi::VIM::Description(:label => "Hard disk 1", :summary => "41,943,040 KB"),
        :backing         => RbVmomi::VIM::VirtualDiskFlatVer2BackingInfo(
          :fileName        => "[datastore] vm1/vm1.vmdk",
          :datastore       => RbVmomi::VIM::Datastore(nil, "datastore-1"),
          :diskMode        => "persistent",
          :thinProvisioned => true,
          :uuid            => "6000C294-264b-3f91-8e5c-8c2ebac1bfe8",
        ),
        :controllerKey   => 1000,
        :unitNumber      => 0,
        :capacityInKB    => 41_943_040,
      ),
    ]
  end
  let(:change_set) do
    [
      RbVmomi::VIM::PropertyChange(:dynamicProperty => [], :name => "config.hardware.device", :op => "assign", :val => device),
      RbVmomi::VIM::PropertyChange(:dynamicProperty => [], :name => "config.version",         :op => "assign", :val => "vmx-08"),
      RbVmomi::VIM::PropertyChange(:dynamicProperty => [], :name => "name",                   :op => "assign", :val => "vm1"),
      RbVmomi::VIM::PropertyChange(:dynamicProperty => [], :name => "parent",                 :op => "assign", :val => RbVmomi::VIM::Folder(nil, "group-v3")),
    ]
  end

  context "#insert" do
    context "without initial change_set" do
      before { cache.insert(vm) }

      it "creates an entry in the cache" do
        expect(cache.keys).to include("VirtualMachine")
        expect(cache["VirtualMachine"].keys).to include("vm-123")
      end
    end

    context "with an initial change_set" do
      before { cache.insert(vm, change_set) }

      it "caches the properties" do
        props = cache["VirtualMachine"]["vm-123"]

        expect(props.keys).to include(:name, :parent, :config)
        expect(props[:config][:version]).to eq("vmx-08")
      end
    end
  end

  context "#delete" do
    context "of an object in the cache" do
      before { cache.insert(vm) }

      it "removes the object" do
        cache.delete(vm)

        expect(cache["VirtualMachine"].keys).to_not include("vm-123")
      end
    end

    context "of an object not in the cache" do
      it "does nothing" do
        expect(cache.delete(vm)).to be_nil
      end
    end
  end

  context "#update" do
    context "of an object not in the cache" do
      it "does nothing" do
        expect(cache.update(vm, [])).to be_nil
      end
    end

    context "of an object in the cache" do
      before { cache.insert(vm, change_set) }

      it "updates a top-level value" do
        update_change_set = [RbVmomi::VIM::PropertyChange(:name => "name", :op => "assign", :val => "vm2")]
        props = cache.update(vm, update_change_set)
        expect(props[:name]).to eq("vm2")
      end

      it "updates a nested value" do
        update_change_set = [RbVmomi::VIM::PropertyChange(:name => "config.version", :op => "assign", :val => "vmx-09")]
        props = cache.update(vm, update_change_set)
        expect(props[:config][:version]).to eq("vmx-09")
      end

      it "updates a value in an array" do
        update_change_set = [
          RbVmomi::VIM::PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[1000].device",
            :op              => "assign",
            :val             => [2000, 2001]
          ),
          RbVmomi::VIM::PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[2002]",
            :op              => "add",
            :val             => RbVmomi::VIM::VirtualDisk(
              :dynamicProperty => [],
              :key             => 2001,
              :deviceInfo      => RbVmomi::VIM::Description(:dynamicProperty => [], :label => "Hard disk 2", :summary => "16,777,216 KB"),
              :backing         => RbVmomi::VIM::VirtualDiskFlatVer2BackingInfo(),
              :controllerKey   => 1000,
              :unitNumber      => 2,
              :capacityInKB    => 16_777_216,
            )
          ),
        ]

        props = cache.update(vm, update_change_set)

        controller = props[:config][:hardware][:device].detect { |dev| dev.key == 1000 }
        expect(controller[:device]).to match_array([2000, 2001])
      end
    end
  end
end
