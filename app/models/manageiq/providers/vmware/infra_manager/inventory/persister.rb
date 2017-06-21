class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister < ManagerRefresh::Inventory::Persister
  def initialize_inventory_collections
    add_inventory_collections(
      ManageIQ::Providers::Vmware::InfraManager::Inventory::InventoryCollections,
      %i(vms hosts resource_pools ems_clusters storages)
    )
  end
end
