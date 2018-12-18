describe ManageIQ::Providers::Vmware::CloudManager::OrchestrationServiceOptionConverter do
  let(:converter)      { described_class.new(nil) }
  let(:valid_template) { FactoryBot.create(:orchestration_template_vmware_cloud_in_xml) }
  let(:dialog_options) do
    {
      # 1st vapp network
      'dialog_param_parent-0'              => nil,
      'dialog_param_fence_mode-0'          => 'isolated',
      'dialog_param_gateway-0-0'           => '192.168.0.0',
      'dialog_param_netmask-0-0'           => '255.255.255.0',
      'dialog_param_dns1-0-0'              => '8.8.8.8',
      'dialog_param_dns2-0-0'              => nil,
      # 2nd vapp network
      'dialog_param_parent-1'              => 'b915be99-1471-4e51-bcde-da2da791b98f',
      'dialog_param_fence_mode-1'          => 'bridged',
      'dialog_param_gateway-1-0'           => '192.168.0.1',
      'dialog_param_netmask-1-0'           => '255.255.255.1',
      'dialog_param_dns1-1-0'              => '1.2.3.4',
      'dialog_param_dns2-1-0'              => '4.3.2.1',
      # 1st VM
      'dialog_param_instance_name-0'       => 'my VM1',
      'dialog_param_hostname-0'            => 'my-vm-1',
      'dialog_param_num_cores-0'           => 8,
      'dialog_param_cores_per_socket-0'    => 4,
      'dialog_param_memory_mb-0'           => 8192,
      'dialog_param_admin_password-0'      => 'admin-password',
      'dialog_param_admin_reset-0'         => 't',
      'dialog_param_guest_customization-0' => 'f',
      'dialog_param_disk_mb-0-0'           => 40_960,
      'dialog_param_disk_mb-0-1'           => 20_480,
      'dialog_param_nic_network-0-0'       => 'VM Network',
      'dialog_param_nic_mode-0-0'          => 'MANUAL',
      'dialog_param_nic_ip_address-0-0'    => '192.168.0.100',
      # 2nd VM
      'dialog_param_instance_name-1'       => 'my VM2',
      'dialog_param_hostname-1'            => 'my-vm-2',
      'dialog_param_num_cores-1'           => 4,
      'dialog_param_cores_per_socket-1'    => 1,
      'dialog_param_memory_mb-1'           => 2048,
      'dialog_param_admin_password-1'      => '',
      'dialog_param_admin_reset-1'         => 'f',
      'dialog_param_guest_customization-1' => 't',
      'dialog_param_disk_mb-1-0'           => 4096,
      'dialog_param_nic_network-1-0'       => 'RedHat Private network 43',
      'dialog_param_nic_mode-1-0'          => 'DHCP',
      'dialog_param_nic_ip_address-1-0'    => nil,
      'dialog_param_nic_network-1-1'       => 'VM Network',
      'dialog_param_nic_mode-1-1'          => 'POOL',
      'dialog_param_nic_ip_address-1-1'    => nil
    }
  end

  describe '.stack_create_options' do
    before do
      allow(described_class).to receive(:get_template).and_return(valid_template)
      converter.instance_variable_set(:@dialog_options, dialog_options)
    end

    it 'vapp networks' do
      options = converter.stack_create_options
      expect(options).not_to be_nil
      expect(options[:vapp_networks]).not_to be_nil
      expect(options[:vapp_networks].count).to eq(2)
      expect(options[:vapp_networks][0]).to include(
        :name       => 'VM Network',
        :parent     => nil,
        :fence_mode => 'isolated',
        :subnet     => [
          {
            :gateway => '192.168.0.0',
            :netmask => '255.255.255.0',
            :dns1    => '8.8.8.8',
            :dns2    => nil
          }
        ]
      )
      expect(options[:vapp_networks][1]).to include(
        :name       => 'RedHat Private network 43',
        :parent     => 'b915be99-1471-4e51-bcde-da2da791b98f',
        :fence_mode => 'bridged',
        :subnet     => [
          {
            :gateway => '192.168.0.1',
            :netmask => '255.255.255.1',
            :dns1    => '1.2.3.4',
            :dns2    => '4.3.2.1'
          }
        ]
      )
    end

    it 'vms' do
      options = converter.stack_create_options
      expect(options).not_to be_nil
      expect(options[:source_vms]).not_to be_nil
      expect(options[:source_vms].count).to eq(2)
      expect(options[:source_vms][0]).to eq(
        :name                => 'my VM1',
        :vm_id               => 'vm-e9b55b85-640b-462c-9e7a-d18c47a7a5f3',
        :guest_customization => {
          :Enabled               => false,
          :ComputerName          => 'my-vm-1',
          :AdminPasswordEnabled  => true,
          :AdminPassword         => 'admin-password',
          :AdminPasswordAuto     => false,
          :ResetPasswordRequired => true
        },
        :hardware            => {
          :cpu    => { :num_cores => 8, :cores_per_socket => 4 },
          :memory => { :quantity_mb => 8192 },
          :disk   => [
            { :id => '2000', :capacity_mb => 40_960 },
            { :id => '2001', :capacity_mb => 20_480 }
          ]
        },
        :networks            => [
          {
            :networkName             => 'VM Network',
            :IpAddressAllocationMode => 'MANUAL',
            :IpAddress               => '192.168.0.100',
            :IsConnected             => true
          }
        ]
      )
      expect(options[:source_vms][1]).to eq(
        :name                => 'my VM2',
        :vm_id               => 'vm-04f85cca-3f8d-43b4-8473-7aa099f95c1b',
        :guest_customization => {
          :Enabled               => true,
          :ComputerName          => 'my-vm-2',
          :AdminPasswordEnabled  => true,
          :AdminPasswordAuto     => true,
          :ResetPasswordRequired => false
        },
        :hardware            => {
          :cpu    => { :num_cores => 4, :cores_per_socket => 1 },
          :memory => { :quantity_mb => 2048 },
          :disk   => [{ :id => '2000', :capacity_mb => 4096 }]
        },
        :networks            => [
          {
            :networkName             => 'RedHat Private network 43',
            :IpAddressAllocationMode => 'DHCP',
            :IpAddress               => nil,
            :IsConnected             => true
          },
          {
            :networkName             => 'VM Network',
            :IpAddressAllocationMode => 'POOL',
            :IpAddress               => nil,
            :IsConnected             => true
          }
        ]
      )
    end
  end
end
