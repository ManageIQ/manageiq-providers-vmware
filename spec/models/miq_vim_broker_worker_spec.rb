describe MiqVimBrokerWorker do
  it ".emses_to_monitor" do
    _guid, _server, @zone = EvmSpecHelper.create_guid_miq_server_zone
    FactoryBot.create(:ems_vmware_with_authentication, :zone => @zone)
    FactoryBot.create(:ems_vmware_with_authentication, :zone => @zone)
    allow_any_instance_of(ManageIQ::Providers::Vmware::InfraManager).to receive_messages(:authentication_status_ok? => true)

    expect(described_class.emses_to_monitor).to match_array @zone.ext_management_systems
  end

  context "streaming_refresh" do
    before do
      stub_settings_merge(
        :ems_refresh => {
          :vmwarews => {
            :streaming_refresh => true
          }
        }
      )
    end

    it ".required_roles" do
      expect(described_class.required_roles).to be_empty
    end
  end

  context "standard refresh" do
    before do
      stub_settings_merge(
        :ems_refresh => {
          :vmwarews => {
            :streaming_refresh => false
          }
        }
      )
    end

    it ".required_roles" do
      expect(described_class.required_roles).to be_empty
    end
  end
end
