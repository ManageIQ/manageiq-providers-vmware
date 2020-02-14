require "rbvmomi"

describe ManageIQ::Providers::Vmware::InfraManager::Inventory::Cache do
  let(:cache) { described_class.new }
  let(:vm) { RbVmomi::VIM.VirtualMachine(nil, "vm-123") }
  let(:vm_folder) { RbVmomi::VIM.Folder(nil, "group-v3") }
  let(:vm_props) do
    {
      :config => {
        :hardware => {
          :device => [
            RbVmomi::VIM::VirtualLsiLogicController(
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
          ],
        },
        :version  => "vmx-08",
      },
      :name   => "vm1",
      :parent => vm_folder,
    }
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
      before { cache.insert(vm, vm_props) }

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
        expect(cache.update(vm) { |_| }).to be_nil
      end
    end

    context "of an object in the cache" do
      before do
        cache.insert(vm, vm_props)
      end

      it "updates a top-level value" do
        props = cache.update(vm) { |p| p[:name] = "vm2" }
        expect(props[:name]).to eq("vm2")
      end

      it "updates a nested value" do
        props = cache.update(vm) { |p| p[:config][:version] = "vmx-09" }
        expect(props[:config][:version]).to eq("vmx-09")
      end
    end
  end
end
