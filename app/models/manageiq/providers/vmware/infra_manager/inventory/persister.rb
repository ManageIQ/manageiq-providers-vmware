class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :Batch
  require_nested :Targeted

  include ::ManageIQ::Providers::Vmware::Inventory::Persister::Definitions::InfraCollections

  def initialize_inventory_collections
    initialize_infra_inventory_collections
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
