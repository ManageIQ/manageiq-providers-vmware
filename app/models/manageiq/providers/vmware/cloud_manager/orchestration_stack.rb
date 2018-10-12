class ManageIQ::Providers::Vmware::CloudManager::OrchestrationStack < ManageIQ::Providers::CloudManager::OrchestrationStack
  require_nested :Status

  def self.raw_create_stack(orchestration_manager, stack_name, template, options = {})
    log_prefix = "stack=[#{stack_name}]"
    orchestration_manager.with_provider_connection do |service|
      create_options = {:stack_name => stack_name, :template => template.ems_ref}.merge(options)
      $vcloud_log.info("#{log_prefix} create_options: #{create_options}")
      service.instantiate_template(create_options)
    end
  rescue => err
    $vcloud_log.error("#{log_prefix} error: #{err}")
    raise MiqException::MiqOrchestrationProvisionError, err.to_s, err.backtrace
  end

  def raw_delete_stack
    ext_management_system.with_provider_connection do |service|
      raw_stack = vapp_or_nil(service, ems_ref)
      raise MiqException::MiqOrchestrationStackNotExistError, "#{name} does not exist on #{ems.name}" unless raw_stack

      # First, undeploy the vApp (power off).
      raw_stack.undeploy
      # Then delete it.
      raw_stack.destroy
    end
  rescue => err
    $vcloud_log.error("stack=[#{name}], error: #{err}")
    raise MiqException::MiqOrchestrationDeleteError, err.to_s, err.backtrace
  end

  def raw_status
    ems = ext_management_system
    ems.with_provider_connection do |service|
      raw_stack = vapp_or_nil(service, ems_ref)
      raise MiqException::MiqOrchestrationStackNotExistError, "#{name} does not exist on #{ems.name}" unless raw_stack

      Status.new(raw_stack.human_status, nil)
    end
  rescue MiqException::MiqOrchestrationStackNotExistError
    raise
  rescue => err
    $vcloud_log.error("stack=[#{name}], error: #{err}")
    raise MiqException::MiqOrchestrationStatusError, err.to_s, err.backtrace
  end

  def vapp_or_nil(service, ems_ref)
    service.vapps.get_single_vapp(ems_ref)
  rescue Fog::Compute::VcloudDirector::Forbidden
    # vCloud returns 403 Forbidden instead 404 Not Found when ems_ref is in
    # right format but nothing is found.
    nil
  rescue Fog::Compute::VcloudDirector::ServiceError
    # vCloud returns 500 Service Error instead 404 Not Found when ems_ref is in
    # unexpected format i.e. ems_ref does not comply to regex.
    nil
  end
end
