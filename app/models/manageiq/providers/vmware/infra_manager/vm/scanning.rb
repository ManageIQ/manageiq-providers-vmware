module ManageIQ::Providers::Vmware::InfraManager::Vm::Scanning
  extend ActiveSupport::Concern

  def require_snapshot_for_scan?
    true
  end
end
