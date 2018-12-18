describe ManageIQ::Providers::Vmware::NetworkManager::RefreshParser do
  describe "Utility" do
    before do
      allow($vcloud_log).to receive(:debug)
      allow($vcloud_log).to receive(:error)
      allow($vcloud_log).to receive(:info)
    end
    let(:ems) do
      FactoryBot.create(:ems_vmware_cloud).tap do |ems|
        ems.authentications << FactoryBot.create(:authentication, :status => "Valid")
      end
    end
    let(:refresher) { described_class.new(ems) }
    let(:network)   { double(:id => 'id1', :name => 'name1') }

    describe 'build_vapp_network' do
      [
        {
          :name     => 'only network name',
          :net_conf => { :networkName => 'network-name' },
          :expected => { :name => 'network-name (vapp-name)' }
        },
        {
          :name     => 'empty IpScopes section',
          :net_conf => {
            :networkName   => 'network-name',
            :Configuration => { :IpScopes => {}}
          },
          :expected => { :name => 'network-name (vapp-name)' }
        },
        {
          :name     => 'valid IpScopes section - hash',
          :net_conf => {
            :networkName   => 'network-name',
            :Configuration => {
              :IpScopes => { :IpScope => { :Gateway => '1.1.1.1', :Netmask => '2.2.2.2', :IsEnabled => true }}
            }
          },
          :expected => {
            :name    => 'network-name (vapp-name)',
            :gateway => '1.1.1.1',
            :netmask => '2.2.2.2',
            :enabled => true
          }
        },
        {
          :name     => 'valid IpScopes section - list',
          :net_conf => {
            :networkName   => 'network-name',
            :Configuration => {
              :IpScopes => [
                { :IpScope => { :Gateway => '1.1.1.1', :Netmask => '2.2.2.2', :IsEnabled => true }}
              ]
            }
          },
          :expected => {
            :name    => 'network-name (vapp-name)',
            :gateway => '1.1.1.1',
            :netmask => '2.2.2.2',
            :enabled => true
          }
        },
        {
          :name     => 'with Features section',
          :net_conf => {
            :networkName   => 'network-name',
            :Configuration => {
              :Features => { :DhcpService => { :IsEnabled => true }}
            }
          },
          :expected => {
            :name         => 'network-name (vapp-name)',
            :dhcp_enabled => true
          }
        }
      ].each do |test_case|
        it "build_vapp_network - #{test_case[:name]}" do
          test_case[:expected][:type]         ||= 'application/vnd.vmware.vcloud.vAppNetwork+xml'
          test_case[:expected][:is_shared]    ||= false
          test_case[:expected][:gateway]      ||= nil
          test_case[:expected][:netmask]      ||= nil
          test_case[:expected][:enabled]      ||= nil
          test_case[:expected][:dhcp_enabled] ||= nil
          vapp = double(:name => 'vapp-name')
          n = refresher.send(:build_vapp_network, vapp, 'network-id', test_case[:net_conf])
          expect(n).to have_attributes(test_case[:expected])
        end
      end
    end

    describe 'network_id_from_links' do
      [
        {
          :name     => 'regular case',
          :data     => {
            :Link => [
              {
                :rel  => 'repair',
                :href => 'https://vmwarecloudhost/api/admin/network/3d3da9a8-1db1-40cd-9fff-c770d6411486/action/reset'
              },
              {
                :rel  => 'syncSyslogSettings',
                :href => 'https://vmwarecloudhost/api/admin/network/3d3da9a8-1db1-40cd-9fff-c770d6411486/action/syncSyslogServerSettings',
                :type => 'application/vnd.vmware.vcloud.task+xml'
              }
            ]
          },
          :expected => '3d3da9a8-1db1-40cd-9fff-c770d6411486'
        },
        {
          :name     => 'missing Link section',
          :data     => {},
          :expected => nil
        },
        {
          :name     => 'Link section is not array',
          :data     => {
            :Link => {
              :rel  => 'repair',
              :href => 'https://vmwarecloudhost/api/admin/network/3d3da9a8-1db1-40cd-9fff-c770d6411486/action/reset'
            }
          },
          :expected => '3d3da9a8-1db1-40cd-9fff-c770d6411486'
        },
        {
          :name     => 'first link does not match',
          :data     => {
            :Link => [
              {
                :rel  => 'repair',
                :href => 'https://vmwarecloudhost/api/admin/not-network/123/stop'
              },
              {
                :rel  => 'syncSyslogSettings',
                :href => 'https://vmwarecloudhost/api/admin/network/3d3da9a8-1db1-40cd-9fff-c770d6411486/action/syncSyslogServerSettings',
                :type => 'application/vnd.vmware.vcloud.task+xml'
              }
            ]
          },
          :expected => '3d3da9a8-1db1-40cd-9fff-c770d6411486'
        },
        {
          :name     => 'no link matches',
          :data     => {
            :Link => [
              {
                :rel  => 'repair',
                :href => 'https://vmwarecloudhost/api/admin/not-network/123/action1'
              },
              {
                :rel  => 'syncSyslogSettings',
                :href => 'https://vmwarecloudhost/api/admin/not-network/123/action2',
              }
            ]
          },
          :expected => nil
        },
      ].each do |test_case|
        it "network_id_from_links - #{test_case[:name]}" do
          expect(refresher.send(:network_id_from_links, test_case[:data])).to eq(test_case[:expected])
        end
      end
    end

    describe 'parent_vdc_network' do
      [
        {
          :name         => 'regular case',
          :net_conf     => { :Configuration => { :ParentNetwork => { :id => 'parent1' }}},
          :vdc_networks => { 'parent1' => 'OK' },
          :expected     => 'OK'
        },
        {
          :name         => 'no parent specified',
          :net_conf     => { :Configuration => {}},
          :vdc_networks => {},
          :expected     => nil
        },
      ].each do |test_case|
        it "parent_vdc_network - #{test_case[:name]}" do
          expect(refresher.send(:parent_vdc_network, test_case[:net_conf], test_case[:vdc_networks]))
            .to eq(test_case[:expected])
        end
      end
    end

    describe 'corresponding_vdc_network' do
      [
        {
          :name         => 'regular case - is corresponding',
          :net_conf     => {
            :networkName   => 'same name',
            :Configuration => { :ParentNetwork => { :id => 'parent1', :name => 'same name' }}
          },
          :vdc_networks => { 'parent1' => 'OK' },
          :expected     => 'OK'
        },
        {
          :name         => 'regular case - not corresponding',
          :net_conf     => {
            :networkName   => 'different name 1',
            :Configuration => { :ParentNetwork => { :id => 'parent1', :name => 'different name 2' }}
          },
          :vdc_networks => { 'parent1' => 'OK' },
          :expected     => nil
        },
        {
          :name         => 'is corresponding, but network not found',
          :net_conf     => {
            :networkName   => 'same name',
            :Configuration => { :ParentNetwork => { :id => 'parent1', :name => 'same name' }}
          },
          :vdc_networks => {},
          :expected     => nil
        }
      ].each do |test_case|
        it "parent_vdc_network - #{test_case[:name]}" do
          expect(refresher.send(:corresponding_vdc_network, test_case[:net_conf], test_case[:vdc_networks]))
            .to eq(test_case[:expected])
        end
      end
    end

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
          expect(refresher.send(:to_cidr, test_case[:address], test_case[:netmask])).to eq(test_case[:expected])
        end
      end
    end

    describe 'fetch_network_configurations_for_vapp' do
      [
        {
          :name     => 'regular case',
          :data     => { :NetworkConfigSection => { :NetworkConfig => 'DATA'}},
          :expected => ['DATA']
        },
        {
          :name     => 'regular case - list',
          :data     => { :NetworkConfigSection => { :NetworkConfig => ['DATA']}},
          :expected => ['DATA']
        },
        {
          :name     => 'error response',
          :data     => -> { raise Fog::VcloudDirector::Compute::Forbidden, 'simulated error' },
          :expected => []
        }
      ].each do |test_case|
        it "to_list - #{test_case[:name]}" do
          mock_api_response(:get_vapp, test_case[:data])
          expect(refresher.send(:fetch_network_configurations_for_vapp, 'vapp-id')).to eq(test_case[:expected])
        end
      end
    end

    describe 'fetch_nic_configurations_for_vm' do
      [
        {
          :name     => 'regular case',
          :data     => { :NetworkConnection => 'DATA' },
          :expected => ['DATA']
        },
        {
          :name     => 'regular case - list',
          :data     => { :NetworkConnection => ['DATA'] },
          :expected => ['DATA']
        },
        {
          :name     => 'error response',
          :data     => -> { raise Fog::VcloudDirector::Compute::Forbidden, 'simulated error' },
          :expected => []
        }
      ].each do |test_case|
        it "to_list - #{test_case[:name]}" do
          mock_api_response(:get_network_connection_system_section_vapp, test_case[:data])
          expect(refresher.send(:fetch_nic_configurations_for_vm, 'vm-id')).to eq(test_case[:expected])
        end
      end
    end

    def mock_api_response(fun_name, response)
      d = double('api-mock')
      if response.respond_to?(:call)
        allow(d).to receive(fun_name) { response.call }
      else
        allow(d).to receive(fun_name).with(any_args).and_return(double(:body => response))
      end
      refresher.instance_variable_set(:@connection, d)
    end
  end
end
