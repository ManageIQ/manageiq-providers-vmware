class ManageIQ::Providers::Vmware::ContainerManager::EventCatcher < ManageIQ::Providers::BaseManager::EventCatcher
  def self.settings_name
    :event_catcher_vmware_tanzu
  end
end
