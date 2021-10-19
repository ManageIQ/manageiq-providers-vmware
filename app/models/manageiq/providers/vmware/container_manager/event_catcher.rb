class ManageIQ::Providers::Vmware::ContainerManager::EventCatcher < ManageIQ::Providers::BaseManager::EventCatcher
  require_nested :Runner

  def self.settings_name
    :event_catcher_vmware_tanzu
  end
end
