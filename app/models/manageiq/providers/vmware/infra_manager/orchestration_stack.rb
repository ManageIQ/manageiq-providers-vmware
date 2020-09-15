class ManageIQ::Providers::Vmware::InfraManager::OrchestrationStack < ManageIQ::Providers::InfraManager::OrchestrationStack
  require_nested :Status

  def self.create_stack(template, options = {})
    new(:name                   => template.name,
        :description            => "Deploy Vmware content library template",
        :status                 => "Creating",
        :ext_management_system  => template.ext_management_system,
        :orchestration_template => template).tap do |stack|
      stack.send(:update_with_provider_object, raw_create_stack(template, options))
      stack.save!
    end
  end

  def self.raw_create_stack(template, options = {})
    template.deploy(options)
  rescue VSphereAutomation::ApiError => e
    _log.error("Failed to deploy content library template(#{template.name}), error: #{e}")
    raise MiqException::MiqOrchestrationProvisionError, "Content library OVF template deployment failed: #{e}"
  end

  def raw_status
    response = JSON.parse(outputs.first.value)
    message = response.dig("value", "succeeded") ? nil : response.dig("value", "error").to_json || deploy_result
    Status.new(true, message)
  end

  def update_with_provider_object(response)
    result = response.to_hash
    _log.info("Content Library request response: #{result}")
    outputs.build(:key => 'repsonse', :value => result.to_json)
    self.status = 'Failed'

    if result.dig(:value, :succeeded)
      options = {
        :resource_category => result.dig(:value, :resource_id, :type),
        :ems_ref           => result.dig(:value, :resource_id, :id),
        :resource_status   => 'Succeeded'
      }
      resources.build(options)
      self.status = 'Succeeded'
    end
  end

  def self.display_name(number = 1)
    n_('Orchestration Stack (VMware Content Library)', 'Orchestration Stacks (VMware Content Library)', number)
  end
end
