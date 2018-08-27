class ManageIQ::Providers::Vmware::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :CloudManager
end
