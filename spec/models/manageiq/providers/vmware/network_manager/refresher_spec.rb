describe ManageIQ::Providers::Vmware::NetworkManager::Refresher do
  before(:each) do
    @ems = FactoryGirl.create(:ems_vmware_with_vcr_authentication, :port => 443, :api_version => "v5_0", :security_protocol => "ssl-with-validation")
    @ems_network = @ems.network_manager
  end

  before(:each) do
    userid   = Rails.application.secrets.vmware_cloud.try(:[], 'userid') || 'VMWARE_CLOUD_USERID'
    password = Rails.application.secrets.vmware_cloud.try(:[], 'password') || 'VMWARE_CLOUD_PASSWORD'
    hostname = @ems.hostname

    # Ensure that VCR will obfuscate the basic auth
    VCR.configure do |c|
      # workaround for escaping host
      c.before_playback do |interaction|
        interaction.filter!(CGI.escape(hostname), hostname)
        interaction.filter!(CGI.escape('VMWARE_CLOUD_HOST'), 'vmwarecloudhost')
      end
      c.filter_sensitive_data('VMWARE_CLOUD_AUTHORIZATION') { Base64.encode64("#{userid}:#{password}").chomp }
    end
  end

  let(:network_type_vdc)  { 'ManageIQ::Providers::Vmware::NetworkManager::CloudNetwork::OrgVdcNet' }
  let(:network_type_vapp) { 'ManageIQ::Providers::Vmware::NetworkManager::CloudNetwork::VappNet' }
  let(:subnet_type)       { 'ManageIQ::Providers::Vmware::NetworkManager::CloudSubnet' }
  let(:router_type)       { 'ManageIQ::Providers::Vmware::NetworkManager::NetworkRouter' }
  let(:floating_ip_type)  { 'ManageIQ::Providers::Vmware::NetworkManager::FloatingIp' }

  it ".ems_type" do
    expect(described_class.ems_type).to eq(:vmware_cloud_network)
  end

  describe "VDC network is properly inventoried" do
    let(:vdc_net_ref)    { 'f656a8db-ac4d-47dc-9b63-672cb1497126' }
    let(:vdc_subnet_ref) { 'subnet-f656a8db-ac4d-47dc-9b63-672cb1497126' }
    let(:net_port_ref)   { 'vm-6850d9ee-ce30-42e0-aaad-3909e1861c48#NIC#0' }
    let(:vm_ref)         { 'vm-6850d9ee-ce30-42e0-aaad-3909e1861c48' }
    let(:vdc_net)        { CloudNetwork.find_by(:ems_ref => vdc_net_ref) }
    let(:vdc_subnet)     { CloudSubnet.find_by(:ems_ref => vdc_subnet_ref) }
    let(:net_port)       { NetworkPort.find_by(:ems_ref => net_port_ref) }
    let(:vm)             { Vm.find_by(:ems_ref => vm_ref) }

    it "full refresh" do
      refresh_network_manager(described_class.name.underscore) do
        assert_network_counts
        assert_specific_network
        assert_specific_subnet
        assert_specific_network_port
        assert_specific_vm_networking
      end
    end

    def assert_specific_network
      expect(vdc_net).to be
      expect(vdc_net).to have_attributes(
        :name   => 'RedHat external network',
        :cidr   => '10.12.0.1/16',
        :shared => false,
        :type   => network_type_vdc
      )
      expect(vdc_net.cloud_subnets.count).to eq(1)
    end

    def assert_specific_subnet
      expect(vdc_subnet).to have_attributes(
        :name                           => 'subnet-RedHat external network',
        :cidr                           => '10.12.0.1/16',
        :status                         => nil,
        :dhcp_enabled                   => nil,
        :gateway                        => "10.12.0.1",
        :network_protocol               => nil,
        :dns_nameservers                => ["10.12.0.13"],
        :ipv6_router_advertisement_mode => nil,
        :ipv6_address_mode              => nil,
        :extra_attributes               => nil,
        :type                           => subnet_type,
        :ext_management_system          => @ems_network,
        :availability_zone              => nil,
        :cloud_network                  => vdc_net,
        :cloud_tenant                   => nil,
        :network_router                 => nil,
        :network_group                  => nil,
        :parent_cloud_subnet            => nil
      )
      expect(vdc_subnet.network_ports.count).to eq(4)
      expect(vdc_subnet.vms.count).to eq(4)
    end

    def assert_specific_network_port
      expect(net_port).to have_attributes(
        :name                  => 'RHEL7-001 (WebServerVM)#NIC#0',
        :mac_address           => '00:50:56:01:00:09',
        :device_type           => 'VmOrTemplate',
        :source                => 'refresh',
        :ext_management_system => @ems_network,
        :device                => vm
      )
    end

    def assert_specific_vm_networking
      expect(vm).to have_attributes(
        :name           => 'RHEL7-001 (WebServerVM)',
        :ipaddresses    => ['10.12.6.17'],
        :mac_addresses  => [net_port.mac_address],
        :cloud_networks => [vdc_net],
        :cloud_subnets  => [vdc_subnet],
        :network_ports  => [net_port],
        :floating_ips   => []
      )
    end
  end

  describe "vApp network is properly inventoried" do
    let(:vapp_net_ref)    { '3d3da9a8-1db1-40cd-9fff-c770d6411486' }
    let(:vapp_subnet_ref) { 'subnet-3d3da9a8-1db1-40cd-9fff-c770d6411486' }
    let(:net_port_ref)    { 'vm-1a5ebd7d-c507-4ddd-b554-489ee5964dab#NIC#0' }
    let(:vm_ref)          { 'vm-1a5ebd7d-c507-4ddd-b554-489ee5964dab' }
    let(:router_ref)      { '3d3da9a8-1db1-40cd-9fff-c770d6411486---f656a8db-ac4d-47dc-9b63-672cb1497126' }
    let(:floating_ip_ref) { 'floating_ip-vm-1a5ebd7d-c507-4ddd-b554-489ee5964dab#NIC#0' }
    let(:vdc_net_ref)     { 'f656a8db-ac4d-47dc-9b63-672cb1497126' }
    let(:vapp_net)        { CloudNetwork.find_by(:ems_ref => vapp_net_ref) }
    let(:vapp_subnet)     { CloudSubnet.find_by(:ems_ref => vapp_subnet_ref) }
    let(:net_port)        { NetworkPort.find_by(:ems_ref => net_port_ref) }
    let(:vm)              { Vm.find_by(:ems_ref => vm_ref) }
    let(:router)          { NetworkRouter.find_by(:ems_ref => router_ref) }
    let(:floating_ip)     { FloatingIp.find_by(:ems_ref => floating_ip_ref) }
    let(:vdc_net)         { CloudNetwork.find_by(:ems_ref => vdc_net_ref) }

    it "full refresh" do
      refresh_network_manager(described_class.name.underscore) do
        assert_network_counts
        assert_specific_network
        assert_specific_subnet
        assert_specific_network_port
        assert_specific_network_router
        assert_specific_floating_ip
        assert_specific_vm_networking
      end
    end

    def assert_specific_network
      expect(vapp_net).to have_attributes(
        :name    => 'vApp network test (RHEL7-web-002)',
        :cidr    => '192.168.2.1/24',
        :enabled => true,
        :shared  => false,
        :type    => network_type_vapp
      )
      expect(vapp_net.cloud_subnets.count).to eq(1)
    end

    def assert_specific_subnet
      expect(vapp_subnet).to have_attributes(
        :name                  => 'subnet-vApp network test (RHEL7-web-002)',
        :cidr                  => '192.168.2.1/24',
        :dhcp_enabled          => true,
        :gateway               => '192.168.2.1',
        :dns_nameservers       => [],
        :type                  => subnet_type,
        :ext_management_system => @ems_network,
        :cloud_network         => vapp_net,
        :network_router        => router
      )
      expect(vapp_subnet.network_ports.count).to eq(1)
      expect(vapp_subnet.vms.count).to eq(1)
    end

    def assert_specific_network_port
      expect(net_port).to have_attributes(
        :name                  => 'vAppRHEL7-w-002 (WebServerVM)#NIC#0',
        :mac_address           => '00:50:56:01:00:0c',
        :device_type           => 'VmOrTemplate',
        :source                => 'refresh',
        :ext_management_system => @ems_network,
        :device                => vm
      )
    end

    def assert_specific_network_router
      expect(router).to have_attributes(
        :name                  => 'Router RedHat external network -> vApp network test',
        :type                  => router_type,
        :cloud_network         => vdc_net,
        :ext_management_system => @ems_network,
        :cloud_subnets         => [vapp_subnet]
      )
    end

    def assert_specific_floating_ip
      expect(floating_ip).to have_attributes(
        :type                  => floating_ip_type,
        :address               => '10.12.7.4',
        :fixed_ip_address      => '10.12.7.4',
        :ext_management_system => @ems_network,
        :vm                    => vm,
        :network_port          => net_port,
        :cloud_network         => vapp_net
      )
    end

    def assert_specific_vm_networking
      expect(vm).to have_attributes(
        :name           => 'vAppRHEL7-w-002 (WebServerVM)',
        :ipaddresses    => ['192.168.2.100', floating_ip.address],
        :mac_addresses  => [net_port.mac_address],
        :cloud_networks => [vapp_net],
        :cloud_subnets  => [vapp_subnet],
        :network_ports  => [net_port],
        :floating_ips   => [floating_ip]
      )
    end
  end

  describe "VM with two network ports" do
    let(:vm_ref)          { 'vm-37ff4eb7-a711-4baa-82cf-3075f099ebb0' }
    let(:floating_ip_ref) { 'floating_ip-vm-37ff4eb7-a711-4baa-82cf-3075f099ebb0#NIC#0' }
    let(:vm)              { Vm.find_by(:ems_ref => vm_ref) }
    let(:floating_ip)     { FloatingIp.find_by(:ems_ref => floating_ip_ref) }

    it "full refresh" do
      refresh_network_manager(described_class.name.underscore) do
        expect(vm).to have_attributes(
          :name         => 'RHEL01-rspec (WebServerVM)',
          :floating_ips => [floating_ip]
        )

        expect(vm.cloud_networks.count).to eq(2)
        expect(vm.cloud_subnets.count).to eq(2)
        expect(vm.network_ports.count).to eq(2)
        expect(vm.ipaddresses).to contain_exactly('192.168.2.100', '10.12.7.6', floating_ip.address)
        expect(vm.mac_addresses).to contain_exactly('00:50:56:01:00:1a', '00:50:56:01:00:19')
      end
    end
  end

  def refresh_network_manager(cassete)
    2.times do # Run twice to verify that a second run with existing data does not change anything
      @ems.reload
      @ems_network.reload
      VCR.use_cassette(cassete) do
        EmsRefresh.refresh(@ems)
        EmsRefresh.refresh(@ems_network)
      end
      @ems.reload
      @ems_network.reload

      yield
    end
  end

  def assert_network_counts
    expect(CloudNetwork.count).to eq(11)
    expect(CloudSubnet.count).to eq(11)
    expect(CloudNetwork.where(:type => network_type_vdc).count).to eq(6)
    expect(CloudNetwork.where(:type => network_type_vapp).count).to eq(5)
    expect(NetworkRouter.count).to eq(2)
    expect(NetworkPort.count).to eq(7)
    expect(FloatingIp.count).to eq(2)
  end
end
