describe ManageIQ::Providers::Vmware::CloudManager::Vm::RemoteConsole do
  let(:user) { FactoryBot.create(:user) }
  let(:ems)  { FactoryBot.create(:ems_vmware_cloud, :api_version => 6.0) }
  let(:vm)   { FactoryBot.create(:vm_vcloud, :ext_management_system => ems, :raw_power_state => 'on') }

  context '#remote_console_acquire_ticket' do
    it 'with :webmks' do
      expect(vm).to receive(:remote_console_webmks_acquire_ticket).with(user.userid, 1)
      vm.remote_console_acquire_ticket(user.userid, 1, :webmks)
    end
  end

  context '#remote_console_acquire_ticket_queue' do
    let(:server) { double('MiqServer') }

    before(:each) do
      allow(vm).to receive_messages(:my_zone => nil)
      allow(server).to receive_messages(:my_zone => nil)
      allow(server).to receive_messages(:id => 1)
      allow(MiqServer).to receive_messages(:my_server => server)
    end

    it 'with :webmks' do
      vm.remote_console_acquire_ticket_queue(:webmks, user.userid)

      q_all = MiqQueue.all
      expect(q_all.length).to eq(1)
      expect(q_all[0].method_name).to eq('remote_console_acquire_ticket')
      expect(q_all[0].args).to eq([user.userid, 1, :webmks])
    end
  end

  context '#remote_console_webmks_acquire_ticket' do
    before(:each) do
      allow(ems).to receive(:with_provider_connection).and_yield(connection)
      allow(SecureRandom).to receive(:hex).and_return('hex')
    end

    let(:connection)     { double('connection') }
    let(:empty_response) { double('response', :body => {}) }
    let(:response) do
      double(
        'response',
        :body => {
          :Ticket => 'ticket',
          :Port   => 1234,
          :Host   => 'host'
        }
      )
    end

    it 'performs validation' do
      expect(connection).to receive(:post_acquire_mks_ticket).and_return(empty_response)
      expect(vm).to receive(:validate_remote_console_webmks_support)
      expect { vm.remote_console_webmks_acquire_ticket(user.userid) }.to raise_error MiqException::RemoteConsoleNotSupportedError
    end

    it 'launches proxy socket' do
      expect(connection).to receive(:post_acquire_mks_ticket).and_return(response)
      expect(SystemConsole).to receive(:launch_proxy_if_not_local).with(
        {
          :user       => user,
          :vm_id      => vm.id,
          :ssl        => true,
          :protocol   => 'webmks-uint8utf8',
          :secret     => 'ticket',
          :url_secret => 'hex',
          :url        => '/1234;ticket'
        },
        1, 'host', 443
      ).and_return({})
      vm.remote_console_webmks_acquire_ticket(user.userid, 1)
    end
  end

  context '#validate_remote_console_webmks_support' do
    it 'normal case' do
      ems.api_version = '5.5'
      expect(vm.validate_remote_console_webmks_support).to be_truthy
    end

    it 'with vm with no ems' do
      vm.ext_management_system = nil
      vm.save!
      expect { vm.validate_remote_console_webmks_support }.to raise_error MiqException::RemoteConsoleNotSupportedError
    end

    it 'with vm off' do
      vm.raw_power_state = 'off'
      expect { vm.validate_remote_console_webmks_support }.to raise_error MiqException::RemoteConsoleNotSupportedError
    end

    it 'on vCloud 5.1' do
      ems.api_version = '5.1'
      expect { vm.validate_remote_console_webmks_support }.to raise_error MiqException::RemoteConsoleNotSupportedError
    end
  end
end
