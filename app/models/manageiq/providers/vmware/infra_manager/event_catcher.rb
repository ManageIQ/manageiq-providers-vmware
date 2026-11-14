class ManageIQ::Providers::Vmware::InfraManager::EventCatcher < ManageIQ::Providers::BaseManager::EventCatcher
  # Core derives the :ems path from ems_type ("vmwarews"), but the settings key is "ems_vmware".
  def self.worker_settings_paths
    [
      %i[http_proxy vmwarews],
      %i[log level_vim],
      %i[ems ems_vmware]
    ]
  end
end
