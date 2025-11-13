if ENV['CI']
  require 'simplecov'
  SimpleCov.start
end

Dir[Rails.root.join("spec/shared/**/*.rb")].each { |f| require f }
Dir[File.join(__dir__, "support/**/*.rb")].each { |f| require f }

require "manageiq/providers/vmware"

RSpec.configure do |config|
  config.before do
    YamlPermittedClasses.app_yaml_permitted_classes |= [VimHash, VimString, VimArray]
  end
end

VCR.configure do |config|
  # Allow connections to a local vcsim
  config.ignore_request do |req|
    uri = URI(req.uri)
    uri.host == "localhost" && uri.port = 8989
  end

  config.ignore_hosts 'codeclimate.com' if ENV['CI']
  config.cassette_library_dir = File.join(ManageIQ::Providers::Vmware::Engine.root, 'spec/vcr_cassettes')

  VcrSecrets.define_all_cassette_placeholders(config, :vmware_infra)
  VcrSecrets.define_all_cassette_placeholders(config, :vmware_cloud)
  VcrSecrets.define_all_cassette_placeholders(config, :vmware_tanzu)

  config.define_cassette_placeholder("VMWARE_CLOUD_AUTHORIZATION") do
    Base64.encode64("#{VcrSecrets.vmware_cloud.userid}:#{VcrSecrets.vmware_cloud.password}").chomp
  end
  config.define_cassette_placeholder("VMWARE_CLOUD_INVALIDAUTHORIZATION") do
    Base64.encode64("#{VcrSecrets.vmware_cloud.userid}:invalid").chomp
  end
end
