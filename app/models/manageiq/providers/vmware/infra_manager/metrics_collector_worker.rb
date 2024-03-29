class ManageIQ::Providers::Vmware::InfraManager::MetricsCollectorWorker < ManageIQ::Providers::BaseManager::MetricsCollectorWorker
  self.default_queue_name = "vmware"

  def friendly_name
    @friendly_name ||= "C&U Metrics Collector for vCenter"
  end
end
