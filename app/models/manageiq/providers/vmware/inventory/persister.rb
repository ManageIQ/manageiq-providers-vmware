class ManageIQ::Providers::Vmware::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :CloudManager
  require_nested :NetworkManager
end
