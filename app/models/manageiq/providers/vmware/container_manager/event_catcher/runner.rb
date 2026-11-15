class ManageIQ::Providers::Vmware::ContainerManager::EventCatcher::Runner < ManageIQ::Providers::BaseManager::EventCatcher::Runner
  include ManageIQ::Providers::Kubernetes::ContainerManager::EventCatcherMixin

  private

  def worker_cmdline
    ManageIQ::Providers::Vmware::Engine.root.join("workers/container_event_catcher/worker").to_s
  end
end
