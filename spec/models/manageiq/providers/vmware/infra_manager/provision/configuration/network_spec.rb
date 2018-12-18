describe ManageIQ::Providers::Vmware::InfraManager::Provision::Configuration::Network do
  describe '#normalize_network_adapter_settings' do
    let(:miq_provision) { FactoryBot.build(:miq_provision_vmware, :options => options) }

    shared_examples_for 'normalize_network_adapter_settings' do
      it 'updates network options' do
        miq_provision.normalize_network_adapter_settings

        expect(miq_provision.options).to include(network_options)
      end
    end

    context 'adds default adapter into networks hash' do
      let(:options) { {:vlan => %w(network network), :mac_address => 'aa:bb:cc:dd:ee:ff'} }
      let(:network_options)  { {:networks=>[{:network => 'network', :mac_address => 'aa:bb:cc:dd:ee:ff'}]} }

      it_behaves_like 'normalize_network_adapter_settings'
    end

    context 'adds default adapter into networks hash' do
      let(:options) { {:vlan => %w(dvs_network network)} }
      let(:network_options)  { {:networks => [{:network => 'network', :is_dvs => true}]} }

      it_behaves_like 'normalize_network_adapter_settings'
    end

    context 'adds default adapter into networks hash' do
      let(:options) { {:vlan => %w(network network), :networks => []} }
      let(:network_options)  { {:networks=>[{:network=>'network'}]} }

      it_behaves_like 'normalize_network_adapter_settings'
    end

    context 'adds default adapter into networks hash' do
      let(:options) { {:vlan => %w(network network), :networks => [nil]} }
      let(:network_options)  { {:networks=>[{:network=>'network'}]} }

      it_behaves_like 'normalize_network_adapter_settings'
    end

    context 'adds default adapter into networks hash' do
      let(:options) { {:networks => [{:network => 'network'}]} }
      let(:network_options) { {:vlan => %w(network network)} }

      it_behaves_like 'normalize_network_adapter_settings'
    end

    context 'adds default adapter into networks hash' do
      let(:options) { {:networks => [{:network => 'network', :is_dvs => true}]} }
      let(:network_options) { {:vlan => %w(dvs_network network)} }

      it_behaves_like 'normalize_network_adapter_settings'
    end
  end
end
