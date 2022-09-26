class ManageIQ::Providers::Vmware::InfraManager::EventCatcher < ManageIQ::Providers::BaseManager::EventCatcher
  require_nested :Runner

  self.rails_worker = !!worker_settings[:rails_worker]
end
