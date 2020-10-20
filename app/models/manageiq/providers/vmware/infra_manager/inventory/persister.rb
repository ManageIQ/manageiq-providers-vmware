class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :Batch
  require_nested :Full
  require_nested :Targeted

  def initialize_inventory_collections
    add_collection(infra, :customization_specs)
    add_collection(infra, :disks, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :distributed_virtual_switches)
    add_collection(infra, :distributed_virtual_lans)
    add_collection(infra, :clusters)
    add_collection(infra, :ems_custom_attributes, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :vm_and_template_labels, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :vm_and_template_taggings, :parent_inventory_collections => %i[vms_and_templates])
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
    add_collection(infra, :host_virtual_lans)
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
    add_collection(infra, :orchestration_templates)
    vms_and_templates_assign_created_on if ::Settings.ems_refresh.capture_vm_created_on_date
  end

  def vim_class_to_collection(managed_object)
    case managed_object
    when RbVmomi::VIM::ComputeResource
      clusters
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

  private

  def vms_and_templates_assign_created_on
    custom_save_block = lambda do |ems, inventory_collection|
      vms_and_templates = inventory_collection.dependency_attributes[:vms_and_templates]&.first
      return if vms_and_templates.nil?

      created_vm_ids = vms_and_templates.created_records.map { |rec| rec[:id] }
      ems.assign_ems_created_on_queue(created_vm_ids) unless created_vm_ids.empty?
    end

    settings = {:without_model_class => true, :auto_inventory_attributes => false}

    add_collection(infra, :vms_and_templates_assign_created_on, {}, settings) do |builder|
      builder.add_custom_save_block(custom_save_block)
      builder.add_dependency_attributes(:vms_and_templates => ->(persister) { [persister.vms_and_templates] })
    end
  end
end
