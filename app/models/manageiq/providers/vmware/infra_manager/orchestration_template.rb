class ManageIQ::Providers::Vmware::InfraManager::OrchestrationTemplate < OrchestrationTemplate
  def unique_md5?
    false
  end
end
