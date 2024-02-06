class ManageIQ::Providers::Vmware::ContainerManager::RefreshWorker < ManageIQ::Providers::BaseManager::RefreshWorker
  def self.settings_name
    :ems_refresh_worker_vmware_tanzu
  end
end
