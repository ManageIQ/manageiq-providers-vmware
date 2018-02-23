describe ManageIQ::Providers::Vmware::CloudManager::Vm do
  context "#is_available?" do
    let(:ems)                   { FactoryGirl.create(:ems_vmware_cloud) }
    let(:vm)                    { FactoryGirl.create(:vm_vmware_cloud, :ext_management_system => ems) }
    let(:power_state_on)        { "on" }
    let(:power_state_suspended) { "suspended" }

    context("with :start") do
      let(:state) { :start }
      include_examples "Vm operation is available when not powered on"
    end

    context("with :stop") do
      let(:state) { :stop }
      include_examples "Vm operation is available when powered on"
    end

    context("with :suspend") do
      let(:state) { :suspend }
      include_examples "Vm operation is available when powered on"
    end

    context("with :pause") do
      let(:state) { :pause }
      include_examples "Vm operation is not available"
    end

    context("with :shutdown_guest") do
      let(:state) { :shutdown_guest }
      include_examples "Vm operation is not available"
    end

    context("with :standby_guest") do
      let(:state) { :standby_guest }
      include_examples "Vm operation is not available"
    end
  end

  context "when destroyed" do
    let(:ems) { FactoryGirl.create(:ems_vmware_cloud) }
    let(:vm) { FactoryGirl.create(:vm_vmware_cloud, :ext_management_system => ems) }
    let(:connection) { double("connection") }
    let(:response) { double("response", :body => nil) }

    it "deletes the virtual machine" do
      allow(ems).to receive(:with_provider_connection).and_yield(connection)
      expect(connection).to receive(:delete_vapp).and_return(response)
      expect(connection).to receive(:process_task).and_return(true)

      vm.raw_destroy
    end
  end
end
