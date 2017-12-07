class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister < ManagerRefresh::Inventory::Persister
  def initialize_inventory_collections
    add_inventory_collections(
      default_inventory_collections, inventory_collection_names, inventory_collection_options
    )

    add_inventory_collection(
      default_inventory_collections.datacenters(
        :arel => manager.ems_folders.where(:type => "Datacenter"),
      )
    )
  end

  def default_inventory_collections
    ManageIQ::Providers::Vmware::InfraManager::Inventory::InventoryCollections
  end

  def inventory_collection_names
    %i(
      custom_attributes
      customization_specs
      disks
      ems_clusters
      ems_folders
      guest_devices
      hardwares
      hosts
      host_hardwares
      host_networks
      host_storages
      host_switches
      host_operating_systems
      lans
      networks
      operating_systems
      resource_pools
      snapshots
      storages
      storage_profiles
      switches
      vms_and_templates
    )
  end

  def complete
    true
  end

  def saver_strategy
    :default
  end

  def strategy
    nil
  end

  def targeted
    false
  end

  def inventory_collection_options
    {
      :complete       => complete,
      :saver_strategy => saver_strategy,
      :strategy       => strategy,
      :targeted       => targeted,
    }
  end
end
