module ManageIQ::Providers::Vmware::InfraManager::CisConnectMixin
  extend ActiveSupport::Concern

  def cis_connect(_options = {})
    require 'vsphere-automation-cis'

    configuration = VSphereAutomation::Configuration.new.tap do |c|
      c.host = "#{hostname}:#{port || 443}"
      c.username = auth_user_pwd.first
      c.password = auth_user_pwd.last
      c.scheme = 'https'
      c.verify_ssl = false
      c.verify_ssl_host = false
    end

    api_client = VSphereAutomation::ApiClient.new(configuration)
    VSphereAutomation::CIS::SessionApi.new(api_client).create('')
    api_client
  end
end
