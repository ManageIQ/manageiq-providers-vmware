describe ManageIQ::Providers::Vmware::Inventory::Parser::NetworkManager do
  describe "Utility" do
    describe 'to_cidr' do
      [
        {
          :name     => 'regular case',
          :address  => '0.0.0.0',
          :netmask  => '128.0.0.0',
          :expected => '0.0.0.0/1'
        },
        {
          :name     => 'missing address',
          :address  => nil,
          :netmask  => '128.0.0.0',
          :expected => nil
        },
        {
          :name     => 'empty address',
          :address  => '',
          :netmask  => '128.0.0.0',
          :expected => nil
        },
        {
          :name     => 'missing netmask',
          :address  => '0.0.0.0',
          :netmask  => nil,
          :expected => nil
        },
        {
          :name     => 'empty netmask',
          :address  => '0.0.0.0',
          :netmask  => '',
          :expected => nil
        }
      ].each do |test_case|
        it "to_cidr - #{test_case[:name]}" do
          expect(subject.send(:to_cidr, test_case[:address], test_case[:netmask])).to eq(test_case[:expected])
        end
      end
    end
  end
end
