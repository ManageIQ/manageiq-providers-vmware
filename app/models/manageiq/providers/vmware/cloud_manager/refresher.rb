class ManageIQ::Providers::Vmware::CloudManager::Refresher < ManageIQ::Providers::BaseManager::Refresher
  def save_inventory(ems, target, hashes)
    super
    EmsRefresh.queue_refresh(ems.network_manager)
  end

  def post_process_refresh_classes
    [::Vm]
  end
end
