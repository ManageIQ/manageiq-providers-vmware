describe ManageIQ::Providers::Vmware::InfraManager::EmsRefObjMixin do
  let(:vm) { FactoryBot.create(:vm_vmware, :ems_ref_type => "VirtualMachine") }

  describe ".ems_ref_obj" do
    context "when ems_ref is nil" do
      before { vm.ems_ref = nil }
      it "returns nil" do
        expect(vm.ems_ref_obj).to be_nil
      end

      it "returns a VimString when ems_ref is set" do
        expect(vm.ems_ref_obj).to be_nil
        vm.ems_ref = "vm-123"
        expect(vm.ems_ref_obj).to eq(VimString.new("vm-123", :VirtualMachine, :ManagedObjectReference))
      end
    end

    context "when ems_ref is present" do
      before { vm.ems_ref = "vm-123" }

      it "returns a VimString" do
        expect(vm.ems_ref_obj).to eq(VimString.new("vm-123", :VirtualMachine, :ManagedObjectReference))
      end

      it "returns nil when ems_ref is cleared" do
        expect(vm.ems_ref_obj).to eq(VimString.new("vm-123", :VirtualMachine, :ManagedObjectReference))
        vm.ems_ref = nil
        expect(vm.ems_ref_obj).to be_nil
      end

      it "returns a new VimString when ems_ref is updated" do
        expect(vm.ems_ref_obj).to eq(VimString.new("vm-123", :VirtualMachine, :ManagedObjectReference))
        vm.ems_ref = "vm-456"
        expect(vm.ems_ref_obj).to eq(VimString.new("vm-456", :VirtualMachine, :ManagedObjectReference))
      end
    end
  end
end
