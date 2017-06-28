class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister < ManagerRefresh::Inventory::Persister
  def initialize_inventory_collections
    add_inventory_collections(
      default_inventory_collections, inventory_collection_names, inventory_collection_options
    )
  end

  def default_inventory_collections
    ManageIQ::Providers::Vmware::InfraManager::Inventory::InventoryCollections
  end

  def inventory_collection_names
    %i(vms_and_templates disks nics guest_devices hardwares snapshots operating_systems
       custom_attributes ems_folders resource_pools ems_clusters storages hosts
       host_storage switches lans storage_profiles)
  end

  def inventory_collection_options
    {}
  end
end
