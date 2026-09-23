require 'kubeclient'
require 'recursive-open-struct'
require 'rest-client'

require_relative '../../../workers/container_event_catcher/event_catcher'

RSpec.describe EventCatcher do
  let(:ems)            { {'id' => 1, 'uid_ems' => 'my-tanzu-cluster', 'type' => 'ManageIQ::Providers::Vmware::ContainerManager', 'ems_type' => 'vmware_tanzu'} }
  let(:endpoint)       { {'hostname' => 'tanzu.example.com', 'port' => 443, 'security_protocol' => 'ssl-with-validation', 'certificate_authority' => nil} }
  let(:authentication) { {'authtype' => 'default', 'userid' => 'administrator@vsphere.local', 'password' => 's3cr3t'} }
  let(:settings)       { {'ems' => {'ems_vmware_tanzu' => {'blacklisted_event_names' => []}}} }
  let(:logger)         { instance_double('Logger', :info => nil, :warn => nil) }
  let(:catcher)        { described_class.new(ems, endpoint, authentication, settings, {}, logger) }

  describe '#log_prefix' do
    it 'returns the Vmware ContainerManager class name' do
      expect(catcher.send(:log_prefix)).to eq('MIQ(ManageIQ::Providers::Vmware::ContainerManager::EventCatcher)')
    end
  end

  describe '#auth_options' do
    let(:fake_session_id) { 'wcp-session-abc123' }

    before do
      allow(RestClient::Request).to receive(:execute).and_return(
        double('Response', :body => {'session_id' => fake_session_id}.to_json)
      )
    end

    it 'posts to /wcp/login on the endpoint hostname' do
      expect(RestClient::Request).to receive(:execute) do |opts|
        expect(opts[:url]).to include('tanzu.example.com')
        expect(opts[:url]).to include('/wcp/login')
        double('Response', :body => {'session_id' => fake_session_id}.to_json)
      end

      catcher.send(:auth_options)
    end

    it 'passes userid and password to the WCP login request' do
      expect(RestClient::Request).to receive(:execute) do |opts|
        expect(opts[:user]).to eq('administrator@vsphere.local')
        expect(opts[:password]).to eq('s3cr3t')
        double('Response', :body => {'session_id' => fake_session_id}.to_json)
      end

      catcher.send(:auth_options)
    end

    it 'returns the session_id as bearer_token and records token_expiry' do
      before_call = Time.now.utc
      expect(catcher.send(:auth_options)).to eq(:bearer_token => fake_session_id)
      expect(catcher.instance_variable_get(:@token_expiry)).to be_within(2).of(before_call + EventCatcher::WCP_SESSION_TTL)
    end

    it 'uses VERIFY_PEER for ssl-with-validation' do
      expect(RestClient::Request).to receive(:execute) do |opts|
        expect(opts[:verify_ssl]).to eq(OpenSSL::SSL::VERIFY_PEER)
        double('Response', :body => {'session_id' => fake_session_id}.to_json)
      end

      catcher.send(:auth_options)
    end

    it 'uses VERIFY_NONE for ssl-without-validation' do
      endpoint['security_protocol'] = 'ssl-without-validation'
      expect(RestClient::Request).to receive(:execute) do |opts|
        expect(opts[:verify_ssl]).to eq(OpenSSL::SSL::VERIFY_NONE)
        double('Response', :body => {'session_id' => fake_session_id}.to_json)
      end

      catcher.send(:auth_options)
    end
  end

  describe '#token_expiry' do
    it 'returns nil before auth_options has been called' do
      expect(catcher.send(:token_expiry)).to be_nil
    end

    it 'returns a Time ~WCP_SESSION_TTL seconds in the future after auth_options is called' do
      allow(RestClient::Request).to receive(:execute).and_return(
        double('Response', :body => {'session_id' => 'wcp-session-abc123'}.to_json)
      )
      before_call = Time.now.utc
      catcher.send(:auth_options)
      expect(catcher.send(:token_expiry)).to be_within(2).of(before_call + EventCatcher::WCP_SESSION_TTL)
    end
  end

  describe '#build_client' do
    let(:fake_session_id) { 'wcp-session-fresh' }
    let(:client)          { instance_double('Kubeclient::Client', :discover => nil) }

    before do
      allow(RestClient::Request).to receive(:execute).and_return(
        double('Response', :body => {'session_id' => fake_session_id}.to_json)
      )
    end

    it 'passes the WCP session_id as bearer_token to Kubeclient' do
      expect(Kubeclient::Client).to receive(:new) do |_uri, _version, opts|
        expect(opts[:auth_options]).to eq(:bearer_token => fake_session_id)
        client
      end

      catcher.send(:build_client)
    end

    it 'calls wcp_login on every build_client call (token refresh)' do
      allow(Kubeclient::Client).to receive(:new).and_return(client)
      expect(RestClient::Request).to receive(:execute).twice.and_return(
        double('Response', :body => {'session_id' => fake_session_id}.to_json)
      )

      catcher.send(:build_client)
      catcher.send(:build_client)
    end
  end
end
