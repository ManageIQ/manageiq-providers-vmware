class ManageIQ::Providers::Vmware::Inventory::Persister::CloudManager < ManageIQ::Providers::Vmware::Inventory::Persister
  def initialize_inventory_collections
    add_cloud_collection(:availability_zones)
    add_cloud_collection(:disks)
    add_cloud_collection(:hardwares)
    add_cloud_collection(:miq_templates)
    add_cloud_collection(:operating_systems)
    add_cloud_collection(:orchestration_stacks)
    add_cloud_collection(:snapshots)
    add_cloud_collection(:orchestration_templates) do |builder|
      builder.add_default_values(:ext_management_system => cloud_manager)
    end
    add_cloud_collection(:vms)
  end
end
