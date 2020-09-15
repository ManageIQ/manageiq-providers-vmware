class ManageIQ::Providers::Vmware::InfraManager::OrchestrationStack::Status < ::OrchestrationStack::Status
  def succeeded?
    status
  end

  def failed?
    !status
  end
end
