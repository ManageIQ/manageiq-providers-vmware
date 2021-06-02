class ManageIQ::Providers::Vmware::CloudManager::Refresher < ManageIQ::Providers::BaseManager::Refresher
  def post_process_refresh_classes
    [::Vm]
  end
end
