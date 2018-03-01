describe ManageIQ::Providers::Vmware::CloudManager do
  before(:context) do
    @host = Rails.application.secrets.vmware_cloud.try(:[], 'host') || 'vmwarecloudhost'
    host_uri = URI.parse("https://#{@host}")

    @hostname = host_uri.host
    @port = host_uri.port == 443 ? nil : host_uri.port

    @userid = Rails.application.secrets.vmware_cloud.try(:[], 'userid') || 'VMWARE_CLOUD_USERID'
    @password = Rails.application.secrets.vmware_cloud.try(:[], 'password') || 'VMWARE_CLOUD_PASSWORD'

    VCR.configure do |c|
      # workaround for escaping host in spec/spec_helper.rb
      c.before_playback do |interaction|
        interaction.filter!(CGI.escape(@host), @host)
        interaction.filter!(CGI.escape('VMWARE_CLOUD_HOST'), 'vmwarecloudhost')
      end

      c.filter_sensitive_data('VMWARE_CLOUD_AUTHORIZATION') { Base64.encode64("#{@userid}:#{@password}").chomp }
      c.filter_sensitive_data('VMWARE_CLOUD_INVALIDAUTHORIZATION') { Base64.encode64("#{@userid}:invalid").chomp }
    end
  end

  before(:example) do
    _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
    @ems = FactoryGirl.create(
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
      encrypted = MiqPassword.encrypt("encrypted")
      expect(::Fog::Compute::VcloudDirector).to receive(:new).with(params)

      described_class.raw_connect("server", "port", "username", encrypted)
    end

    it "validates the password if validate is true if specified" do
      expect(described_class).to receive(:validate_connection).and_raise(Fog::Compute::VcloudDirector::Unauthorized)
      expect(::Fog::Compute::VcloudDirector).to receive(:new).with(params)

      expect do
        described_class.raw_connect("server", "port", "username", "encrypted", true)
      end.to raise_error(MiqException::MiqInvalidCredentialsError, "Login failed due to a bad username or password.")
    end

    it "does not validate the password unless specified" do
      expect(described_class).to_not receive(:validate_connection)
      expect(::Fog::Compute::VcloudDirector).to receive(:new).with(params)

      described_class.raw_connect("server", "port", "username", "encrypted")
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

  it "#supported_catalog_types" do
    expect(@ems.supported_catalog_types).to eq(%w(vmware))
  end

  describe 'snapshot operations' do
    before(:each) do
      allow(@ems).to receive(:with_provider_connection).and_yield(connection)
    end

    let(:vm) { FactoryGirl.create(:vm_vcloud, :ext_management_system => @ems) }
    let(:response) { double("response", :body => nil) }
    let(:connection) { double('connection') }

    context ".vm_create_snapshot" do
      let(:snapshot_options) { { :name => 'name', :memory => false } }

      it 'creates a snapshot' do
        expect(connection).to receive(:post_create_snapshot).and_return(response)
        expect(connection).to receive(:process_task).and_return(true)

        @ems.vm_create_snapshot(vm, snapshot_options)
      end
    end

    context ".vm_revert_to_snapshot" do
      it 'reverts a vm to snapshot' do
        expect(connection).to receive(:post_revert_snapshot).and_return(response)
        expect(connection).to receive(:process_task).and_return(true)

        @ems.vm_revert_to_snapshot(vm)
      end
    end

    context ".vm_remove_snapshot" do
      it 'removes all snapshots' do
        expect(connection).to receive(:post_remove_all_snapshots).and_return(response)
        expect(connection).to receive(:process_task).and_return(true)

        @ems.vm_remove_all_snapshots(vm)
      end

      it 'supports remove all snapshots' do
        expect(vm.supports_remove_all_snapshots?).to be_truthy
      end

      it 'supports remove snapshot' do
        expect(vm.supports_remove_snapshot?).to be_falsey
      end
    end
  end
end
