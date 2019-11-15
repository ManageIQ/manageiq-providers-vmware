class ManageIQ::Providers::Vmware::NetworkManager::RefreshWorker < ::MiqEmsRefreshWorker
  require_nested :Runner

  def self.settings_name
    :ems_refresh_worker_vmware_cloud
  end
end
