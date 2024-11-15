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

TEST_CREDENTIALS_DEFAULTS = {
  :vmware_cloud_defaults => {:host => "vmwarecloudhost", :userid => "VMWARE_CLOUD_USERID", :password => "VMWARE_CLOUD_PASSWORD"},
  :vmware_infra_defaults => {:hostname => "HOSTNAME"},
  :vmware_tanzu_defaults => {:hostname => "vmware-tanzu-hostname", :userid => "VMWARE_TANZU_USERID", :password => "VMWARE_TANZU_PASSWORD"}
}.freeze

def test_credentials(*args)
  Rails.application.credentials.dig(*args) || test_credentials_defaults(*args)
end

def test_credentials_defaults(*args)
  args[0] = "#{args[0]}_defaults".to_sym
  TEST_CREDENTIALS_DEFAULTS.dig(*args)
end

VCR.configure do |config|
  # config.default_cassette_options = { :record => :all }

  config.ignore_hosts 'codeclimate.com' if ENV['CI']
  config.cassette_library_dir = File.join(ManageIQ::Providers::Vmware::Engine.root, 'spec/vcr_cassettes')

  config.define_cassette_placeholder(test_credentials_defaults(:vmware_infra_defaults, :hostname)) do
    test_credentials(:vmware_infra, :hostname)
  end
  config.define_cassette_placeholder(test_credentials_defaults(:vmware_cloud, :host)) do
    test_credentials(:vmware_cloud, :host)
  end
  config.define_cassette_placeholder("VMWARE_CLOUD_AUTHORIZATION") do
    Base64.encode64("#{test_credentials(:vmware_cloud, :userid)}:#{test_credentials(:vmware_cloud, :password)}").chomp
  end
  config.define_cassette_placeholder("VMWARE_CLOUD_INVALIDAUTHORIZATION") do
    Base64.encode64("#{test_credentials(:vmware_cloud, :userid)}:invalid").chomp
  end

  config.define_cassette_placeholder(test_credentials_defaults(:vmware_tanzu, :hostname)) { test_credentials(:vmware_tanzu, :hostname) }
  config.define_cassette_placeholder(test_credentials_defaults(:vmware_tanzu, :userid))   { test_credentials(:vmware_tanzu, :userid) }
  config.define_cassette_placeholder(test_credentials_defaults(:vmware_tanzu, :password)) { test_credentials(:vmware_tanzu, :password) }
end
