module ManageIQ::Providers::Vmware::Inventory::Persister::Definitions::CloudCollections
  extend ActiveSupport::Concern

  def initialize_cloud_inventory_collections
    %i(vms
       miq_templates
       availability_zones
       disks
       hardwares
       operating_systems
       snapshots).each do |name|

      add_collection(cloud, name)
    end

    add_orchestration_templates

    add_orchestration_stacks
  end

  # ------ IC provider specific definitions -------------------------

  # TODO: mslemr - parent model_class used anywhere? If not, should be deleted from core
  def add_orchestration_stacks
    add_collection(cloud, :orchestration_stacks) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::Vmware::CloudManager::OrchestrationStack)
    end
  end

  def add_orchestration_templates
    add_collection(cloud, :orchestration_templates) do |builder|
      builder.add_default_values(:ems_id => manager.id)
    end
  end
end
