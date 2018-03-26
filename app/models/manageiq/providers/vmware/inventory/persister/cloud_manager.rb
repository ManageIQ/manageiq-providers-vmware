class ManageIQ::Providers::Vmware::Inventory::Persister::CloudManager < ManageIQ::Providers::Vmware::Inventory::Persister
  def initialize_inventory_collections
    add_inventory_collections(
      cloud,
      %i(
        availability_zones
        orchestration_stacks
        vms
        snapshots
        hardwares
        disks
        operating_systems
        orchestration_templates
        miq_templates
      )
    )
  end
end
