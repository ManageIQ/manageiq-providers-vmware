module ManageIQ::Providers::Vmware::InfraManager::Template::Scanning
  extend ActiveSupport::Concern

  def require_snapshot_for_scan?
    false
  end
end
