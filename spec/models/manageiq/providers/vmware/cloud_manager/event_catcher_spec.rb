describe ManageIQ::Providers::Vmware::CloudManager::EventCatcher do
  it '#ems_class' do
    expect(described_class.ems_class).to eq(ManageIQ::Providers::Vmware::CloudManager)
  end

  it '#settings_name' do
    expect(described_class.settings_name).to eq(:event_catcher_vmware_cloud)
  end

  describe '#all_valid_ems_in_zone' do
    let(:ems_without_amqp) { FactoryGirl.create(:ems_vmware_cloud) }
    let(:ems_with_amqp)    { FactoryGirl.create(:ems_vmware_cloud_with_amqp_authentication) }
    let(:ems_with_empty_amqp) do
      ems = FactoryGirl.create(:ems_vmware_cloud_with_amqp_authentication)
      ems.endpoints.detect { |h| h.role == 'amqp' }.update(:hostname => '')
      ems
    end

    it 'no ems at all' do
      allow(described_class.superclass).to receive(:all_valid_ems_in_zone).and_return([])
      expect(described_class.all_valid_ems_in_zone).to eq([])
    end

    it 'ems without AMQP credentials' do
      allow(described_class.superclass).to receive(:all_valid_ems_in_zone).and_return([ems_without_amqp])
      expect(described_class.all_valid_ems_in_zone).to eq([])
    end

    it 'ems with empty AMQP credentials' do
      allow(described_class.superclass).to receive(:all_valid_ems_in_zone).and_return([ems_with_empty_amqp])
      expect(described_class.all_valid_ems_in_zone).to eq([])
    end

    it 'ems with AMQP credentials' do
      allow(described_class.superclass).to receive(:all_valid_ems_in_zone).and_return([ems_with_amqp])
      expect(described_class.all_valid_ems_in_zone).to eq([ems_with_amqp])
    end

    it 'mixture of all' do
      allow(described_class.superclass).to receive(:all_valid_ems_in_zone).and_return([ems_with_amqp, ems_without_amqp, ems_with_empty_amqp])
      expect(described_class.all_valid_ems_in_zone).to eq([ems_with_amqp])
    end
  end
end
