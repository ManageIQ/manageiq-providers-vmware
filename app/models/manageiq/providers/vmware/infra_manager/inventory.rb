class ManageIQ::Providers::Vmware::InfraManager::Inventory < ManageIQ::Providers::Inventory
  require_nested :Cache
  require_nested :Collector
  require_nested :Parser
  require_nested :Persister
end
