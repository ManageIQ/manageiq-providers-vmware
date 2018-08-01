class ManageIQ::Providers::Vmware::Inventory::Persister < ManagerRefresh::Inventory::Persister
  require_nested :CloudManager
end
