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

    context("with :terminate") do
      let(:state) { :terminate }
      include_examples "Vm operation is available when not powered on"
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

  describe 'power operations' do
    before(:each) do
      allow(ems).to receive(:with_provider_connection).and_yield(connection)
    end

    let(:ems)        { FactoryGirl.create(:ems_vmware_cloud) }
    let(:vm)         { FactoryGirl.create(:vm_vcloud, :ext_management_system => ems, :ems_ref => 'id') }
    let(:connection) { double('connection') }
    let(:response)   { double('response', :body => nil) }

    context '.raw_stop' do
      it 'stops the virtual machine' do
        expect(connection).to receive(:post_undeploy_vapp).with('id', :UndeployPowerAction => 'powerOff').and_return(response)
        expect(connection).to receive(:process_task)

        vm.raw_stop
      end
    end

    context '.raw_suspend' do
      it 'suspends the virtual machine' do
        expect(connection).to receive(:post_undeploy_vapp).with('id', :UndeployPowerAction => 'suspend').and_return(response)
        expect(connection).to receive(:process_task)

        vm.raw_suspend
      end
    end

    it '.disconnected' do
      expect(subject.disconnected).to be_falsey
    end

    it '.disconnected?' do
      expect(subject.disconnected).to be_falsey
    end
  end
end
