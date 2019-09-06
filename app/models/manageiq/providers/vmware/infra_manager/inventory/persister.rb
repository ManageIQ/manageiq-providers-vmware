class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :Batch
  require_nested :Targeted

  def initialize_inventory_collections
    add_collection(infra, :customization_specs)
    add_collection(infra, :disks, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :distributed_virtual_switches)
    add_collection(infra, :ems_clusters)
    add_collection(infra, :ems_custom_attributes, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :ems_extensions)
    add_collection(infra, :ems_folders)
    add_collection(infra, :ems_licenses)
    add_collection(infra, :ext_management_system)
    add_collection(infra, :guest_devices, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :hardwares, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :hosts)
    add_collection(infra, :host_hardwares)
    add_collection(infra, :host_guest_devices)
    add_collection(infra, :host_networks)
    add_collection(infra, :host_storages, :parent_inventory_collections => %i[storages]) do |builder|
      builder.add_properties(:arel => manager.host_storages.joins(:storage))
    end
    add_collection(infra, :host_switches)
    add_collection(infra, :host_system_services)
    add_collection(infra, :host_operating_systems)
    add_collection(infra, :host_virtual_switches)
    add_collection(infra, :lans)
    add_collection(infra, :miq_scsi_luns)
    add_collection(infra, :miq_scsi_targets)
    add_collection(infra, :networks, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :operating_systems, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :resource_pools)
    add_collection(infra, :snapshots, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :storages)
    add_collection(infra, :storage_profiles)
    add_collection(infra, :storage_profile_storages)
    add_collection(infra, :parent_blue_folders)
    add_collection(infra, :vms_and_templates, &:vm_template_shared)
    add_collection(infra, :vm_parent_blue_folders)
    add_collection(infra, :vm_resource_pools)
    add_collection(infra, :root_folder_relationship)
    add_collection(infra, :orchestration_templates, &:add_common_default_values)
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
