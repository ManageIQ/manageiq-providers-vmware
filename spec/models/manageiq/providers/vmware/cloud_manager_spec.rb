describe ManageIQ::Providers::Vmware::CloudManager do
  before(:context) do
    @host = VcrSecrets.vmware_cloud.host
    host_uri = URI.parse("https://#{@host}")

    @hostname = host_uri.host
    @port = host_uri.port == 443 ? nil : host_uri.port

    @userid = VcrSecrets.vmware_cloud.userid
    @password = VcrSecrets.vmware_cloud.password
  end

  before(:example) do
    zone = EvmSpecHelper.local_miq_server.zone
    @ems = FactoryBot.create(
      :ems_vmware_cloud,
      :zone     => zone,
      :hostname => @hostname,
      :port     => @port
    )
  end

  context ".raw_connect" do
    let(:params) do
      {
        :vcloud_director_username      => "username",
        :vcloud_director_password      => "encrypted",
        :vcloud_director_host          => "server",
        :vcloud_director_show_progress => false,
        :vcloud_director_api_version   => "api_version",
        :port                          => "port",
        :connection_options            => {
          :ssl_verify_peer => false # for development
        }
      }
    end

    before do
      require 'fog/vcloud_director'
    end

    it "decrypts the vcloud password" do
      encrypted = ManageIQ::Password.encrypt("encrypted")
      expect(::Fog::VcloudDirector::Compute).to receive(:new).with(params)

      described_class.raw_connect("server", "port", "username", encrypted, "api_version")
    end

    it "validates the password if validate is true if specified" do
      expect(described_class).to receive(:validate_connection).and_raise(Fog::VcloudDirector::Compute::Unauthorized)
      expect(::Fog::VcloudDirector::Compute).to receive(:new).with(params)

      expect do
        described_class.raw_connect("server", "port", "username", "encrypted", "api_version", true)
      end.to raise_error(MiqException::MiqInvalidCredentialsError, "Login failed due to a bad username or password.")
    end

    it "does not validate the password unless specified" do
      expect(described_class).to_not receive(:validate_connection)
      expect(::Fog::VcloudDirector::Compute).to receive(:new).with(params)

      described_class.raw_connect("server", "port", "username", "encrypted", "api_version")
    end
  end

  it ".ems_type" do
    expect(described_class.ems_type).to eq('vmware_cloud')
  end

  it ".description" do
    expect(described_class.description).to eq('VMware vCloud')
  end

  it "will verify credentials" do
    VCR.use_cassette("#{described_class.name.underscore}_valid_credentials") do
      @ems.update_authentication(:default => {:userid => @userid, :password => @password})

      expect(@ems.verify_credentials).to eq(true)
    end
  end

  it "will fail to verify invalid credentials" do
    VCR.use_cassette("#{described_class.name.underscore}_invalid_credentials") do
      @ems.update_authentication(:default => {:userid => @userid, :password => 'invalid'})

      expect { @ems.verify_credentials }.to raise_error(
        MiqException::MiqInvalidCredentialsError, 'Login failed due to a bad username or password.')
    end
  end

  it "#catalog_types" do
    expect(@ems.catalog_types).to include("vmware")
  end

  describe 'snapshot operations' do
    before(:each) do
      allow(@ems).to receive(:with_provider_connection).and_yield(connection)
    end

    let(:vm) { FactoryBot.create(:vm_vcloud, :ext_management_system => @ems) }
    let(:response) { double("response", :body => nil) }
    let(:connection) { double('connection') }

    context ".vm_create_snapshot" do
      let(:snapshot_options) { { :name => 'name', :memory => false } }

      it 'creates a snapshot' do
        expect(connection).to receive(:post_create_snapshot).and_return(response)
        expect(connection).to receive(:process_task).and_return(true)

        @ems.vm_create_snapshot(vm, snapshot_options)
      end

      it 'supports snapshot create' do
        expect(vm.supports?(:snapshot_create)).to be_truthy
      end

      it 'supports snapshot create (for second snapshot)' do
        FactoryBot.create(:snapshot, :vm_or_template_id => vm.id)
        expect(vm.supports?(:snapshot_create)).to be_truthy
      end
    end

    context ".vm_revert_to_snapshot" do
      it 'reverts a vm to snapshot' do
        expect(connection).to receive(:post_revert_snapshot).and_return(response)
        expect(connection).to receive(:process_task).and_return(true)

        @ems.vm_revert_to_snapshot(vm)
      end

      it 'supports revert to snapshot' do
        expect(vm.supports?(:revert_to_snapshot)).to be_truthy
      end
    end

    context ".vm_remove_snapshot" do
      it 'removes all snapshots' do
        expect(connection).to receive(:post_remove_all_snapshots).and_return(response)
        expect(connection).to receive(:process_task).and_return(true)

        @ems.vm_remove_all_snapshots(vm)
      end

      it 'supports remove all snapshots' do
        expect(vm.supports?(:remove_all_snapshots)).to be_truthy
      end

      it 'supports remove snapshot' do
        expect(vm.supports?(:remove_snapshot)).to be_falsey
      end
    end
  end

  describe 'reconfigure operations' do
    before do
      allow(@ems).to receive(:with_provider_connection).and_yield(connection)
    end

    let(:vm)         { FactoryBot.create(:vm_vcloud, :ext_management_system => @ems) }
    let(:connection) { double('connection') }
    let(:vm_xml)     { double('vm_xml') }
    let(:options)    { { :spec => 'fog-options' } }

    it 'supports reconfigure_disks' do
      expect(vm.supports?(:reconfigure_disks)).to be_truthy
    end

    describe 'supports reconfigure_disksize' do
      it 'without snapshots' do
        expect(vm.supports?(:reconfigure_disksize)).to be_truthy
      end

      context 'with snapshots' do
        before { FactoryBot.create(:snapshot, :vm_or_template => vm) }

        it do
          expect(vm.supports?(:reconfigure_disksize)).to be_falsey
        end
      end
    end

    it 'supports reconfigure_network_adapters' do
      expect(vm.supports?(:reconfigure_network_adapters)).to be_truthy
    end

    it '.vm_reconfigure' do
      expect(connection).to receive(:get_vapp).with(vm.ems_ref, :parser => 'xml').and_return(double(:body => vm_xml))
      expect(connection).to receive(:post_reconfigure_vm).with(vm.ems_ref, vm_xml, 'fog-options').and_return(double(:body => nil))
      expect(connection).to receive(:process_task)
      @ems.vm_reconfigure(vm, options)
    end
  end
end
