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

  secrets = Rails.application.secrets
  config.define_cassette_placeholder(Rails.application.secrets.vmware_infra_defaults[:hostname]) do
    Rails.application.secrets.vmware_infra[:hostname]
  end
  config.define_cassette_placeholder(Rails.application.secrets.vmware_cloud_defaults[:host]) do
    Rails.application.secrets.vmware_cloud[:host]
  end
  config.define_cassette_placeholder("VMWARE_CLOUD_AUTHORIZATION") do
    Base64.encode64("#{Rails.application.secrets.vmware_cloud[:userid]}:#{Rails.application.secrets.vmware_cloud[:password]}").chomp
  end
  config.define_cassette_placeholder("VMWARE_CLOUD_INVALIDAUTHORIZATION") do
    Base64.encode64("#{Rails.application.secrets.vmware_cloud[:userid]}:invalid").chomp
  end
  secrets.vmware_tanzu.each do |key, val|
    config.define_cassette_placeholder(secrets.vmware_tanzu_defaults[key]) { val }
  end
end
