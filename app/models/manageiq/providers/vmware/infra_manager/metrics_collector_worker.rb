class ManageIQ::Providers::Vmware::InfraManager::MetricsCollectorWorker < ManageIQ::Providers::BaseManager::MetricsCollectorWorker
  require_nested :Runner

  def friendly_name
    @friendly_name ||= "C&U Metrics Collector for vCenter"
  end
end
