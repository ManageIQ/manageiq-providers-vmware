require "rbvmomi/vim"

describe ManageIQ::Providers::Vmware::InfraManager::Inventory::Cache do
  let(:cache) { described_class.new }
  let(:vm) { RbVmomi::VIM.VirtualMachine(nil, "vm-123") }

  context "#insert" do
    context "without initial change_set" do
      it "creates an entry in the cache" do
        cache.insert(vm)

        expect(cache.keys).to include("VirtualMachine")
        expect(cache["VirtualMachine"].keys).to include("vm-123")
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
        cache.delete(vm)
      end
    end
  end

  context "#update" do
  end
end
