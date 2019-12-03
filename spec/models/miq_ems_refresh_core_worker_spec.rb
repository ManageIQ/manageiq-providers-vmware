describe MiqEmsRefreshCoreWorker do
  # enable role "ems_inventory" ( .has_required_role? == true)
  before do
    FactoryBot.create(:server_role, :name => 'ems_inventory')
    my_server = EvmSpecHelper.local_miq_server
    my_server.update(:role => "ems_inventory")
    my_server.activate_roles("ems_inventory")
  end

  context ".ems_class" do
    it "is the infra manager" do
      expect(described_class.ems_class).to eq(ManageIQ::Providers::Vmware::InfraManager)
    end
  end

  context ".has_required_role?" do
    context "with streaming_refresh" do
      before do
        stub_settings_merge(
          :ems_refresh => {
            :vmwarews => {
              :streaming_refresh => true
            }
          }
        )
      end

      it "should not start the worker" do
        expect(described_class.has_required_role?).to be_falsy
      end
    end
    context "without streaming_refresh" do
      before do
        stub_settings_merge(
          :ems_refresh => {
            :vmwarews => {
              :streaming_refresh => false
            }
          }
        )
      end

      it "should start the worker" do
        expect(described_class.has_required_role?).to be_truthy
      end
      context "without role" do
        before do
          MiqServer.my_server(true).deactivate_roles("ems_inventory")
        end
        it "should not start the worker" do
          expect(described_class.has_required_role?).to be_falsy
        end
      end
    end
  end
end
