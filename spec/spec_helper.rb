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

Object.include Spec::Shared::CassetteSecretsHelper
VCR.configure do |config|
  # config.default_cassette_options = { :record => :all }

  config.ignore_hosts 'codeclimate.com' if ENV['CI']
  config.cassette_library_dir = File.join(ManageIQ::Providers::Vmware::Engine.root, 'spec/vcr_cassettes')

  config.define_cassette_placeholder(default_vcr_secret_by_key_path(:vmware_infra, :hostname)) do
    vcr_secret_by_key_path(:vmware_infra, :hostname)
  end
  config.define_cassette_placeholder(default_vcr_secret_by_key_path(:vmware_cloud, :host)) do
    vcr_secret_by_key_path(:vmware_cloud, :host)
  end
  config.define_cassette_placeholder("VMWARE_CLOUD_AUTHORIZATION") do
    Base64.encode64("#{vcr_secret_by_key_path(:vmware_cloud, :userid)}:#{vcr_secret_by_key_path(:vmware_cloud, :password)}").chomp
  end
  config.define_cassette_placeholder("VMWARE_CLOUD_INVALIDAUTHORIZATION") do
    Base64.encode64("#{vcr_secret_by_key_path(:vmware_cloud, :userid)}:invalid").chomp
  end

  config.define_cassette_placeholder(default_vcr_secret_by_key_path(:vmware_tanzu, :hostname)) { vcr_secret_by_key_path(:vmware_tanzu, :hostname) }
  config.define_cassette_placeholder(default_vcr_secret_by_key_path(:vmware_tanzu, :userid))   { vcr_secret_by_key_path(:vmware_tanzu, :userid) }
  config.define_cassette_placeholder(default_vcr_secret_by_key_path(:vmware_tanzu, :password)) { vcr_secret_by_key_path(:vmware_tanzu, :password) }
end
