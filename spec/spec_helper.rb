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

def credentials_infra_defaults_hostname
  @credentials_infra_defaults_hostname ||= "HOSTNAME".freeze
end

def credentials_infra_hostname
  Rails.application.credentials.dig("vmware_infra", "hostname") || credentials_infra_defaults_hostname
end

def credentials_cloud_defaults_host
  @credentials_cloud_defaults_host ||= "vmwarecloudhost".freeze
end

def credentials_cloud_host
  Rails.application.credentials.dig("vmware_cloud", "host") || credentials_cloud_defaults_host
end

def credentials_cloud_defaults_userid
  @credentials_cloud_defaults_userid ||= "VMWARE_CLOUD_USERID".freeze
end

def credentials_cloud_userid
  Rails.application.credentials.dig(:vmware_cloud, :userid) || credentials_cloud_defaults_userid
end

def credentials_cloud_defaults_password
  @credentials_cloud_defaults_password ||= "VMWARE_CLOUD_PASSWORD".freeze
end

def credentials_cloud_password
  Rails.application.credentials.dig(:vmware_cloud, :password) || credentials_cloud_defaults_password
end

def credentials_tanzu_defaults_hostname
  @credentials_tanzu_defaults_hostname ||= "vmware-tanzu-hostname".freeze
end

def credentials_tanzu_hostname
  Rails.application.credentials.dig("vmware_tanzu", "hostname") || credentials_tanzu_defaults_hostname
end

def credentials_tanzu_defaults_userid
  @credentials_tanzu_defaults_userid ||= "VMWARE_TANZU_USERID".freeze
end

def credentials_tanzu_userid
  Rails.application.credentials.dig("vmware_tanzu", "userid") || credentials_tanzu_defaults_userid
end

def credentials_tanzu_defaults_password
  @credentials_tanzu_defaults_password ||= "VMWARE_TANZU_PASSWORD".freeze
end

def credentials_tanzu_password
  Rails.application.credentials.dig("vmware_tanzu", "password") || credentials_tanzu_defaults_password
end

VCR.configure do |config|
  # config.default_cassette_options = { :record => :all }

  config.ignore_hosts 'codeclimate.com' if ENV['CI']
  config.cassette_library_dir = File.join(ManageIQ::Providers::Vmware::Engine.root, 'spec/vcr_cassettes')

  config.define_cassette_placeholder(credentials_infra_defaults_hostname) do
    credentials_infra_hostname
  end
  config.define_cassette_placeholder(credentials_cloud_defaults_host) do
    credentials_cloud_host
  end
  config.define_cassette_placeholder("VMWARE_CLOUD_AUTHORIZATION") do
    Base64.encode64("#{credentials_cloud_userid}:#{credentials_cloud_password}").chomp
  end
  config.define_cassette_placeholder("VMWARE_CLOUD_INVALIDAUTHORIZATION") do
    Base64.encode64("#{credentials_cloud_userid}:invalid").chomp
  end

  config.define_cassette_placeholder(credentials_tanzu_defaults_hostname) { credentials_tanzu_hostname }
  config.define_cassette_placeholder(credentials_tanzu_defaults_userid) { credentials_tanzu_userid }
  config.define_cassette_placeholder(credentials_tanzu_defaults_password) { credentials_tanzu_password }
end
