class ManageIQ::Providers::Vmware::InfraManager::OrchestrationTemplate < ::OrchestrationTemplate
  belongs_to :ext_management_system, :foreign_key => "ems_id", :class_name => "ManageIQ::Providers::Vmware::InfraManager", :inverse_of => false

  delegate :allowed_resource_pools, :allowed_folders, :allowed_hosts, :to => :workflow_helper

  include ProviderObjectMixin

  SPEC_KEY_MAPPING = {
    "resource_pool" => "resource_pool_id",
    "ems_folder"    => "folder_id",
    "host"          => "host_id"
  }.freeze

  def deploy(options = {})
    require 'vsphere-automation-vcenter'

    with_provider_connection(:service => :cis) do |api_client|
      request_body = VSphereAutomation::VCenter::VcenterOvfLibraryItemDeploy.new(deployment_spec(options))
      api_instance = VSphereAutomation::VCenter::OvfLibraryItemApi.new(api_client)
      api_instance.deploy(ems_ref, request_body)
    end
  end

  def deployment_spec(opts)
    opts = opts.with_indifferent_access
    raise _("Resource pool is required for content library item deployment.") if opts[:resource_pool_id].blank?
    raise _("accept_all_eula is required for content library item deployment.") if opts[:accept_all_eula].nil?

    spec = {"accept_all_EULA" => opts[:accept_all_eula]}
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

  def workflow_helper
    @workflow_helper ||= MiqProvisionOrchWorkflow.new({:src_vm_id => [id]}, User.current_user, :skip_dialog_load => true, :initial_pass => true)
  end

  def target_name_valid?(name, ems_folder_id = nil)
    # TODO: need a way to tell the ovf template is for VM template (where target is a VM) or vApp template (where target is a resource pool with VMs)
    folder = EmsFolder.find_by(:id => ems_folder_id)
    if folder
      folder.vms.none? { |vm| vm.name == name }
    else
      !ext_management_system.vms.where(:name => name).exists?
    end
  end

  def unique_md5?
    false
  end
end
