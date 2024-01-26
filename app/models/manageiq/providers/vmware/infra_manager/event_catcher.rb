class ManageIQ::Providers::Vmware::InfraManager::EventCatcher < ManageIQ::Providers::BaseManager::EventCatcher
  self.rails_worker = -> { !!worker_settings[:rails_worker] }
  self.worker_settings_paths = [
    %i[http_proxy vmwarews],
    %i[log level_vim],
    %i[ems ems_vmware]
  ]
end
