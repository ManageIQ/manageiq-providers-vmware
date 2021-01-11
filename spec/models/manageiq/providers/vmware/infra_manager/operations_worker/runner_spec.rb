describe ManageIQ::Providers::Vmware::InfraManager::OperationsWorker::Runner do
  let(:ems)    { FactoryBot.create(:ems_vmware_with_authentication, :hostname => "hostname") }
  let(:runner) { ManageIQ::Providers::Vmware::InfraManager::OperationsWorker::Runner.new(:ems_id => ems.id) }

  # TODO: need a better way to create a runner for testing without the following mocks
  # And the runner can be reloaded between tests
  before do
    allow_any_instance_of(ManageIQ::Providers::Vmware::InfraManager).to receive(:authentication_check).and_return([true, ""])
    allow_any_instance_of(MiqWorker::Runner).to receive(:worker_initialization)
  end

  describe "#do_before_work_loop" do
    # The operations worker changes the class-level setting of monitor_updates,
    # we have to put back the previous values so as to not break other tests
    around do |example|
      require "VMwareWebService/MiqVim"
      saved_monitor_updates = MiqVim.monitor_updates
      saved_pre_load = MiqVim.pre_load

      example.run
    ensure
      MiqVim.monitor_updates = saved_monitor_updates
      MiqVim.pre_load = saved_pre_load
    end

    before do
      require "VMwareWebService/MiqVim"
      expect(MiqVim)
        .to receive(:new)
        .with(ems.hostname, ems.auth_user_pwd.first, ems.auth_user_pwd.last, nil, nil, nil)
        .and_return(nil)
    end

    it "preloads the cache" do
      runner.do_before_work_loop

      expect(MiqVim.pre_load).to be_truthy
      expect(MiqVim.monitor_updates).to be_truthy
    end
  end
end
