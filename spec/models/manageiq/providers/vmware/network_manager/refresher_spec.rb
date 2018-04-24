describe ManageIQ::Providers::Vmware::NetworkManager::Refresher do
  ALL_REFRESH_SETTINGS = [
    {
      :inventory_object_refresh => false
    },
    {
      :inventory_object_refresh => true,
      :inventory_collections    => {
        :saver_strategy => :default,
      },
    }, {
      :inventory_object_refresh => true,
      :inventory_collections    => {
        :saver_strategy => :batch,
        :use_ar_object  => true,
      },
    }, {
      :inventory_object_refresh => true,
      :inventory_collections    => {
        :saver_strategy => :batch,
        :use_ar_object  => false,
      },
    }, {
      :inventory_object_saving_strategy => :recursive,
      :inventory_object_refresh         => true
    }
  ].freeze

  before(:each) do
    @ems = FactoryGirl.create(:ems_vmware_with_vcr_authentication, :port => 443, :api_version => '5.5', :security_protocol => 'ssl-with-validation')
    @ems_network = @ems.network_manager
    vapp = FactoryGirl.create(:orchestration_stack_vmware_cloud, :ems_ref => 'vapp-67a4a9c2-488d-4479-bd16-f459c9dbc3ff', :ext_management_system => @ems, :name => 'spec3-vapp-external-network')
    FactoryGirl.create(:vm_vcloud, :name => 'vm1', :ems_ref => 'vm-8e5744b9-d47e-48fe-a989-0f84a714e335', :ext_management_system => @ems, :orchestration_stack => vapp)
    FactoryGirl.create(:vm_vcloud, :name => 'vm2', :ems_ref => 'vm-563a216a-9c16-4fb4-bbb0-070d4a1f0419', :ext_management_system => @ems, :orchestration_stack => vapp)
    FactoryGirl.create(:vm_vcloud, :name => 'vm3', :ems_ref => 'vm-9ca720ad-8f85-472c-9c7f-62f8e529301e', :ext_management_system => @ems, :orchestration_stack => vapp)
    FactoryGirl.create(:vm_vcloud, :name => 'vm4', :ems_ref => 'vm-f211aafc-6cd9-444c-86af-faeb18793549', :ext_management_system => @ems, :orchestration_stack => vapp)
    FactoryGirl.create(:vm_vcloud, :name => 'vm5', :ems_ref => 'vm-19d2e739-6a53-4d1a-bd2e-af4ab5fcd03e', :ext_management_system => @ems, :orchestration_stack => vapp)
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

  describe '.refresh' do
    ALL_REFRESH_SETTINGS.each do |settings|
      before(:each) do
        stub_settings_merge(
          :ems_refresh => {
            :vmware_cloud_network => settings
          }
        )
      end

      context "with settings #{settings}" do
        describe 'when VM has no network' do
          let(:vm_ref)       { 'vm-9ca720ad-8f85-472c-9c7f-62f8e529301e' }
          let(:net_port_ref) { 'vm-9ca720ad-8f85-472c-9c7f-62f8e529301e#NIC#0' }
          let(:vm)           { Vm.find_by(:ems_ref => vm_ref) }
          let(:net_port)     { NetworkPort.find_by(:ems_ref => net_port_ref) }

          it do
            refresh_network_manager(described_class.name.underscore) do
              assert_network_counts
              assert_specific_vm_networking
            end
          end

          def assert_specific_vm_networking
            expect(vm).to have_attributes(
              :name           => 'vm3',
              :mac_addresses  => [net_port.mac_address],
              :cloud_networks => [],
              :cloud_subnets  => [],
              :network_ports  => [net_port],
              :floating_ips   => [],
              :ipaddresses    => []
            )
          end
        end

        describe 'when VM has direct network' do
          let(:vm_ref)         { 'vm-19d2e739-6a53-4d1a-bd2e-af4ab5fcd03e' }
          let(:vdc_net_ref)    { '5038b60d-fbb8-42e8-8bf3-e711f703507c' }
          let(:vdc_subnet_ref) { 'subnet-5038b60d-fbb8-42e8-8bf3-e711f703507c' }
          let(:net_port_ref)   { 'vm-19d2e739-6a53-4d1a-bd2e-af4ab5fcd03e#NIC#0' }
          let(:vdc_net)        { CloudNetwork.find_by(:ems_ref => vdc_net_ref) }
          let(:vdc_subnet)     { CloudSubnet.find_by(:ems_ref => vdc_subnet_ref) }
          let(:net_port)       { NetworkPort.find_by(:ems_ref => net_port_ref) }
          let(:vm)             { Vm.find_by(:ems_ref => vm_ref) }

          it do
            refresh_network_manager(described_class.name.underscore) do
              assert_network_counts
              assert_specific_network
              assert_specific_subnet
              assert_specific_network_port
              assert_specific_vm_networking
            end
          end

          def assert_specific_network
            expect(vdc_net).to have_attributes(
              :name   => 'ManageIQ Dev external network',
              :cidr   => '10.12.0.24/16',
              :shared => false,
              :type   => network_type_vdc
            )
            expect(vdc_net.cloud_subnets.count).to eq(1)
          end

          def assert_specific_subnet
            expect(vdc_subnet).to have_attributes(
              :name                           => 'subnet-ManageIQ Dev external network',
              :cidr                           => '10.12.0.24/16',
              :status                         => nil,
              :dhcp_enabled                   => nil,
              :gateway                        => "10.12.0.24",
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
            expect(vdc_subnet.network_ports.count).to eq(2)
            expect(vdc_subnet.vms.count).to eq(2)
          end

          def assert_specific_network_port
            expect(net_port).to have_attributes(
              :name                  => 'vm5#NIC#0',
              :mac_address           => '00:50:56:01:01:28',
              :device_type           => 'VmOrTemplate',
              :ext_management_system => @ems_network,
              :device                => vm,
              :cloud_subnets         => [vdc_subnet]
            )
          end

          def assert_specific_vm_networking
            expect(vm).to have_attributes(
              :name           => 'vm5',
              :mac_addresses  => [net_port.mac_address],
              :cloud_networks => [vdc_net],
              :cloud_subnets  => [vdc_subnet],
              :network_ports  => [net_port],
              :floating_ips   => [],
              :ipaddresses    => ['10.12.6.11']
            )
          end
        end

        describe 'when VM has internal network' do
          let(:vm_ref)          { 'vm-563a216a-9c16-4fb4-bbb0-070d4a1f0419' }
          let(:net_port_ref)    { 'vm-563a216a-9c16-4fb4-bbb0-070d4a1f0419#NIC#0' }
          let(:vapp_net_ref)    { 'e741274b-fdb2-4aad-9db0-0f039eb1b124' }
          let(:vapp_subnet_ref) { 'subnet-e741274b-fdb2-4aad-9db0-0f039eb1b124' }
          let(:vapp_net)        { CloudNetwork.find_by(:ems_ref => vapp_net_ref) }
          let(:vapp_subnet)     { CloudSubnet.find_by(:ems_ref => vapp_subnet_ref) }
          let(:vm)              { Vm.find_by(:ems_ref => vm_ref) }
          let(:net_port)        { NetworkPort.find_by(:ems_ref => net_port_ref) }

          it do
            refresh_network_manager(described_class.name.underscore) do
              assert_network_counts
              assert_specific_network
              assert_specific_subnet
              assert_specific_network_port
              assert_specific_vm_networking
            end
          end

          def assert_specific_network
            expect(vapp_net).to have_attributes(
              :name    => 'spec3-internal-network (spec3-vapp-external-network)',
              :cidr    => '192.168.2.1/24',
              :enabled => true,
              :shared  => false,
              :type    => network_type_vapp
            )
            expect(vapp_net.cloud_subnets.count).to eq(1)
          end

          def assert_specific_subnet
            expect(vapp_subnet).to have_attributes(
              :name                  => 'subnet-spec3-internal-network (spec3-vapp-external-network)',
              :cidr                  => '192.168.2.1/24',
              :dhcp_enabled          => false,
              :gateway               => '192.168.2.1',
              :dns_nameservers       => [],
              :type                  => subnet_type,
              :ext_management_system => @ems_network,
              :cloud_network         => vapp_net,
            )
            expect(vapp_subnet.network_ports.count).to eq(2)
            expect(vapp_subnet.vms.count).to eq(2)
          end

          def assert_specific_network_port
            expect(net_port).to have_attributes(
              :name                  => 'vm2#NIC#0',
              :mac_address           => '00:50:56:01:01:1c',
              :device_type           => 'VmOrTemplate',
              :ext_management_system => @ems_network,
              :device                => vm,
              :cloud_subnets         => [vapp_subnet]
            )
          end

          def assert_specific_vm_networking
            expect(vm).to have_attributes(
              :name           => 'vm2',
              :mac_addresses  => [net_port.mac_address],
              :cloud_networks => [vapp_net],
              :cloud_subnets  => [vapp_subnet],
              :network_ports  => [net_port],
              :floating_ips   => [],
              :ipaddresses    => ['192.168.2.102']
            )
          end
        end

        describe 'when VM has external network' do
          let(:vm_ref)          { 'vm-8e5744b9-d47e-48fe-a989-0f84a714e335' }
          let(:net_port_ref)    { 'vm-8e5744b9-d47e-48fe-a989-0f84a714e335#NIC#0' }
          let(:vapp_net_ref)    { 'c10f8530-0e36-46fb-8cda-0c3aa9c2ad2c' }
          let(:vapp_subnet_ref) { 'subnet-c10f8530-0e36-46fb-8cda-0c3aa9c2ad2c' }
          let(:router_ref)      { 'c10f8530-0e36-46fb-8cda-0c3aa9c2ad2c---5038b60d-fbb8-42e8-8bf3-e711f703507c' }
          let(:floating_ip_ref) { 'floating_ip-vm-8e5744b9-d47e-48fe-a989-0f84a714e335#NIC#0' }
          let(:vdc_net_ref)     { '5038b60d-fbb8-42e8-8bf3-e711f703507c' }
          let(:vapp_net)        { CloudNetwork.find_by(:ems_ref => vapp_net_ref) }
          let(:vapp_subnet)     { CloudSubnet.find_by(:ems_ref => vapp_subnet_ref) }
          let(:vm)              { Vm.find_by(:ems_ref => vm_ref) }
          let(:net_port)        { NetworkPort.find_by(:ems_ref => net_port_ref) }
          let(:router)          { NetworkRouter.find_by(:ems_ref => router_ref) }
          let(:floating_ip)     { FloatingIp.find_by(:ems_ref => floating_ip_ref) }
          let(:vdc_net)         { CloudNetwork.find_by(:ems_ref => vdc_net_ref) }

          it do
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
              :name    => 'spec3-external-network (spec3-vapp-external-network)',
              :cidr    => '192.168.2.1/24',
              :enabled => true,
              :shared  => false,
              :type    => network_type_vapp
            )
            expect(vapp_net.cloud_subnets.count).to eq(1)
          end

          def assert_specific_subnet
            expect(vapp_subnet).to have_attributes(
              :name                  => 'subnet-spec3-external-network (spec3-vapp-external-network)',
              :cidr                  => '192.168.2.1/24',
              :dhcp_enabled          => false,
              :gateway               => '192.168.2.1',
              :dns_nameservers       => [],
              :type                  => subnet_type,
              :ext_management_system => @ems_network,
              :cloud_network         => vapp_net,
              :network_router        => router
            )
            expect(vapp_subnet.network_ports.count).to eq(2)
            expect(vapp_subnet.vms.count).to eq(2)
          end

          def assert_specific_network_port
            expect(net_port).to have_attributes(
              :name                  => 'vm1#NIC#0',
              :mac_address           => '00:50:56:01:01:1a',
              :device_type           => 'VmOrTemplate',
              :ext_management_system => @ems_network,
              :device                => vm,
              :cloud_subnets         => [vapp_subnet]
            )
          end

          def assert_specific_network_router
            expect(router).to have_attributes(
              :name                  => 'Router ManageIQ Dev external network -> spec3-external-network',
              :type                  => router_type,
              :cloud_network         => vdc_net,
              :ext_management_system => @ems_network,
              :cloud_subnets         => [vapp_subnet]
            )
          end

          def assert_specific_floating_ip
            expect(floating_ip).to have_attributes(
              :type                  => floating_ip_type,
              :address               => '10.12.6.13',
              :fixed_ip_address      => '10.12.6.13',
              :ext_management_system => @ems_network,
              :vm                    => vm,
              :network_port          => net_port,
              :cloud_network         => vapp_net
            )
          end

          def assert_specific_vm_networking
            expect(vm).to have_attributes(
              :name           => 'vm1',
              :ipaddresses    => ['192.168.2.101', floating_ip.address],
              :mac_addresses  => [net_port.mac_address],
              :cloud_networks => [vapp_net],
              :cloud_subnets  => [vapp_subnet],
              :network_ports  => [net_port],
              :floating_ips   => [floating_ip]
            )
          end
        end

        describe 'when VM has 4 ports' do
          let(:vm_ref)           { 'vm-f211aafc-6cd9-444c-86af-faeb18793549' }
          let(:net_port_ref1)    { 'vm-f211aafc-6cd9-444c-86af-faeb18793549#NIC#0' }
          let(:net_port_ref2)    { 'vm-f211aafc-6cd9-444c-86af-faeb18793549#NIC#1' }
          let(:net_port_ref3)    { 'vm-f211aafc-6cd9-444c-86af-faeb18793549#NIC#2' }
          let(:net_port_ref4)    { 'vm-f211aafc-6cd9-444c-86af-faeb18793549#NIC#3' }
          let(:vapp_net_ref1)    { 'c10f8530-0e36-46fb-8cda-0c3aa9c2ad2c' }
          let(:vapp_net_ref2)    { 'e741274b-fdb2-4aad-9db0-0f039eb1b124' }
          let(:vdc_net_ref)      { '5038b60d-fbb8-42e8-8bf3-e711f703507c' }
          let(:vapp_subnet_ref1) { 'subnet-c10f8530-0e36-46fb-8cda-0c3aa9c2ad2c' }
          let(:vapp_subnet_ref2) { 'subnet-e741274b-fdb2-4aad-9db0-0f039eb1b124' }
          let(:vdc_subnet_ref)   { 'subnet-5038b60d-fbb8-42e8-8bf3-e711f703507c' }
          let(:floating_ip_ref)  { 'floating_ip-vm-f211aafc-6cd9-444c-86af-faeb18793549#NIC#1' }
          let(:vm)               { Vm.find_by(:ems_ref => vm_ref) }
          let(:net_port1)        { NetworkPort.find_by(:ems_ref => net_port_ref1) }
          let(:net_port2)        { NetworkPort.find_by(:ems_ref => net_port_ref2) }
          let(:net_port3)        { NetworkPort.find_by(:ems_ref => net_port_ref3) }
          let(:net_port4)        { NetworkPort.find_by(:ems_ref => net_port_ref4) }
          let(:vapp_net1)        { CloudNetwork.find_by(:ems_ref => vapp_net_ref1) }
          let(:vapp_net2)        { CloudNetwork.find_by(:ems_ref => vapp_net_ref2) }
          let(:vdc_net)          { CloudNetwork.find_by(:ems_ref => vdc_net_ref) }
          let(:vapp_subnet1)     { CloudSubnet.find_by(:ems_ref => vapp_subnet_ref1) }
          let(:vapp_subnet2)     { CloudSubnet.find_by(:ems_ref => vapp_subnet_ref2) }
          let(:vdc_subnet)       { CloudSubnet.find_by(:ems_ref => vdc_subnet_ref) }
          let(:floating_ip)      { FloatingIp.find_by(:ems_ref => floating_ip_ref) }

          it do
            refresh_network_manager(described_class.name.underscore) do
              assert_network_counts
              assert_specific_floating_ip
              assert_specific_vm_networking
            end
          end

          def assert_specific_network_port
            expect(net_port3).to have_attributes(
              :name                  => 'vm1#NIC#3',
              :mac_address           => '00:50:56:01:01:1a',
              :device_type           => 'VmOrTemplate',
              :ext_management_system => @ems_network,
              :device                => vm,
              :cloud_subnets         => [vdc_subnet]
            )
          end

          def assert_specific_floating_ip
            expect(floating_ip).to have_attributes(
              :type                  => floating_ip_type,
              :address               => '10.12.6.14',
              :fixed_ip_address      => '10.12.6.14',
              :ext_management_system => @ems_network,
              :vm                    => vm,
              :network_port          => net_port2,
              :cloud_network         => vapp_net1
            )
          end

          def assert_specific_vm_networking
            expect(vm.name).to eq('vm4')
            expect(vm.ipaddresses).to match_array(['192.168.2.100', '10.12.6.15', floating_ip.address])
            expect(vm.cloud_networks).to match_array([vapp_net1, vapp_net2, vdc_net])
            expect(vm.cloud_subnets).to match_array([vapp_subnet1, vapp_subnet2, vdc_subnet])
            expect(vm.network_ports).to match_array([net_port1, net_port2, net_port3, net_port4])
            expect(vm.floating_ips).to match_array([floating_ip])
            expect(vm.mac_addresses).to match_array([net_port1.mac_address, net_port2.mac_address, net_port3.mac_address, net_port4.mac_address])
          end
        end
      end
    end
  end

  def refresh_network_manager(cassete)
    2.times do # Run twice to verify that a second run with existing data does not change anything
      @ems.reload
      @ems_network.reload
      VCR.use_cassette(cassete) do
        EmsRefresh.refresh(@ems_network)
      end
      @ems.reload
      @ems_network.reload

      yield
    end
  end

  def assert_network_counts
    expect(CloudNetwork.count).to eq(4)
    expect(CloudSubnet.count).to eq(4)
    expect(CloudNetwork.where(:type => network_type_vdc).count).to eq(2)
    expect(CloudNetwork.where(:type => network_type_vapp).count).to eq(2)
    expect(NetworkRouter.count).to eq(1)
    expect(NetworkPort.count).to eq(8)
    expect(FloatingIp.count).to eq(2)
  end
end
