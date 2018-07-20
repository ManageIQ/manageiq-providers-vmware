class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister < ManagerRefresh::Inventory::Persister
  require_nested :Batch
  require_nested :Targeted

  include ::ManageIQ::Providers::Vmware::Inventory::Persister::Definitions::InfraCollections

  def initialize_inventory_collections
    initialize_infra_inventory_collections
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

  def targeted?
    false
  end

  def parent
    manager.presence
  end

  def shared_options
    {
      :complete       => complete,
      :saver_strategy => saver_strategy,
      :strategy       => strategy,
      :targeted       => targeted?,
      :parent         => parent
    }
  end

  def vim_class_to_collection(managed_object)
    case managed_object
    when RbVmomi::VIM::ComputeResource
      ems_clusters
    when RbVmomi::VIM::Datacenter
      ems_folders
    when RbVmomi::VIM::HostSystem
      hosts
    when RbVmomi::VIM::Folder
      ems_folders
    when RbVmomi::VIM::ResourcePool
      resource_pools
    end
  end
end
