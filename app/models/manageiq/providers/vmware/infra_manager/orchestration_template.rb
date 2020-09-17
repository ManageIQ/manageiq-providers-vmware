class ManageIQ::Providers::Vmware::InfraManager::OrchestrationTemplate < ::OrchestrationTemplate
  belongs_to :ext_management_system, :foreign_key => "ems_id", :class_name => "ManageIQ::Providers::Vmware::InfraManager", :inverse_of => false

  SPEC_KEY_MAPPING = {
    "resource_pool" => "resource_pool_id",
    "ems_folder"    => "folder_id",
    "host"          => "host_id"
  }.freeze

  def connect
    require 'vsphere-automation-cis'

    configuration = VSphereAutomation::Configuration.new.tap do |c|
      c.host = ext_management_system.hostname
      c.username = ext_management_system.auth_user_pwd.first
      c.password = ext_management_system.auth_user_pwd.last
      c.verify_ssl = false
      c.verify_ssl_host = false
    end

    api_client = VSphereAutomation::ApiClient.new(configuration)
    VSphereAutomation::CIS::SessionApi.new(api_client).create('')
    api_client
  end

  def with_provider_connection
    raise _("no block given") unless block_given?

    _log.info("Connecting through #{ext_management_system.class.name}: [#{ext_management_system.name}]")
    yield connect
  end

  def deploy(options = {})
    require 'vsphere-automation-vcenter'

    with_provider_connection do |api_client|
      request_body = VSphereAutomation::VCenter::VcenterOvfLibraryItemDeploy.new(deployment_spec(options))
      api_instance = VSphereAutomation::VCenter::OvfLibraryItemApi.new(api_client)
      api_instance.deploy(ems_ref, request_body)
    end
  end

  def deployment_spec(opts)
    opts = opts.with_indifferent_access
    raise _("Resource pool is required for content library item deployment.") if opts[:resource_pool_id].blank?
    raise _("accept_all_EULA is required for content library item deployment.") if opts[:accept_all_EULA].nil?

    spec = {"accept_all_EULA" => opts[:accept_all_EULA]}
    spec["name"] = opts[:vm_name] if opts[:vm_name].present?

    target = {}
    %w[resource_pool ems_folder host].each do |r|
      options_key = "#{r}_id"
      target[SPEC_KEY_MAPPING[r]] = r.camelize.constantize.find_by(:id => opts[options_key]).ems_ref if opts[options_key].present?
    end

    deploy_options = {"deployment_spec" => spec, "target" => target}
    _log.info("Content Library deployment request body: #{deploy_options}")

    deploy_options
  end

  def unique_md5?
    false
  end
end
