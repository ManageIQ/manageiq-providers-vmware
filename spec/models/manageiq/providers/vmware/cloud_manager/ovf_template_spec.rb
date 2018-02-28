describe ManageIQ::Providers::Vmware::CloudManager::OvfTemplate do
  let(:ovf_string) { File.read(ManageIQ::Providers::Vmware::Engine.root.join(*%w(spec fixtures orchestration_templates vmware_parameters_ovf.xml))) }
  let(:instance)   { described_class.new(ovf_string) }

  describe '.parse' do
    let(:vm1)       { instance.vms[0] }
    let(:vm2)       { instance.vms[1] }
    let(:vapp_net1) { instance.vapp_networks[0] }
    let(:vapp_net2) { instance.vapp_networks[1] }

    it 'vms' do
      expect(instance.vms.count).to eq(2)
      expect(vm1).to have_attributes(
        :id               => 'e9b55b85-640b-462c-9e7a-d18c47a7a5f3',
        :name             => 'VM1',
        :hostname         => 'vm-1',
        :num_cores        => 2,
        :cores_per_socket => 2,
        :memory_mb        => 2048,
      )
      expect(vm2).to have_attributes(
        :id               => '04f85cca-3f8d-43b4-8473-7aa099f95c1b',
        :name             => 'VM2',
        :hostname         => 'vm-2',
        :num_cores        => 2,
        :cores_per_socket => 2,
        :memory_mb        => 4096,
      )
    end

    it 'vm disks' do
      expect(vm1.disks.count).to eq(2)
      expect(vm1.disks[0]).to have_attributes(
        :id          => '2000',
        :address     => '0',
        :capacity_mb => 16_384
      )
      expect(vm1.disks[1]).to have_attributes(
        :id          => '2001',
        :address     => '1',
        :capacity_mb => 40_960
      )
      expect(vm2.disks[0]).to have_attributes(
        :id          => '2000',
        :address     => '0',
        :capacity_mb => 40_960
      )
    end

    it 'vm NICs' do
      expect(vm1.nics.count).to eq(1)
      expect(vm1.nics[0]).to have_attributes(
        :idx        => '0',
        :network    => nil,
        :mode       => 'DHCP',
        :ip_address => nil
      )
      expect(vm2.nics.count).to eq(2)
      expect(vm2.nics[0]).to have_attributes(
        :idx        => '0',
        :network    => 'RedHat Private network 43',
        :mode       => 'MANUAL',
        :ip_address => '192.168.43.100'
      )
      expect(vm2.nics[1]).to have_attributes(
        :idx        => '1',
        :network    => nil,
        :mode       => 'DHCP',
        :ip_address => nil
      )
    end

    it 'vapp networks' do
      expect(instance.vapp_networks.count).to eq(2)
      expect(vapp_net1).to have_attributes(
        :name => 'VM Network',
        :mode => 'isolated'
      )
      expect(vapp_net2).to have_attributes(
        :name => 'RedHat Private network 43',
        :mode => 'bridged'
      )
    end
  end
end
