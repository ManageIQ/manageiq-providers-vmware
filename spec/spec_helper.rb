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
  config.ignore_hosts 'codeclimate.com' if ENV['CI']
  config.cassette_library_dir = File.join(ManageIQ::Providers::Vmware::Engine.root, 'spec/vcr_cassettes')
end
