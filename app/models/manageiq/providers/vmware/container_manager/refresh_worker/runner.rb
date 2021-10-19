class ManageIQ::Providers::Vmware::ContainerManager::RefreshWorker::Runner < ManageIQ::Providers::Kubernetes::ContainerManager::RefreshWorker::Runner
  def kubernetes_entity_types
    super - %w[persistent_volumes]
  end
end
