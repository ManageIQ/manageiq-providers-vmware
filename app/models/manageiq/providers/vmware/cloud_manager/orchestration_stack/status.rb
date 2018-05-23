class ManageIQ::Providers::Vmware::CloudManager::OrchestrationStack::Status < ::OrchestrationStack::Status
  def succeeded?
    %w(on off suspended).include?(status.to_s.downcase)
  end

  def failed?
    %w(failed_creation).include?(status.to_s.downcase)
  end
end
