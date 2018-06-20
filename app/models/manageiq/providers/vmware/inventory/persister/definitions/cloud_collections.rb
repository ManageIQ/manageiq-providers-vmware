module ManageIQ::Providers::Vmware::Inventory::Persister::Definitions::CloudCollections
  extend ActiveSupport::Concern

  def cloud
    ::ManagerRefresh::InventoryCollection::Builder::CloudManager
  end

  def initialize_cloud_inventory_collections
    %i(vms
       availability_zones
       disks
       hardwares
       operating_systems
       snapshots).each do |name|

      add_collection(cloud, name)
    end

    add_orchestration_templates

    add_orchestration_stacks

    add_miq_templates
  end

  # ------ IC provider specific definitions -------------------------

  def add_miq_templates
    add_collection(cloud, :miq_templates) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::Vmware::CloudManager::Template)
    end
  end

  # TODO: mslemr - parent model_class used anywhere? If not, should be deleted from core
  def add_orchestration_stacks
    add_collection(cloud, :orchestration_stacks) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::Vmware::CloudManager::OrchestrationStack)
    end
  end

  def add_orchestration_templates
    add_collection(cloud, :orchestration_templates) do |builder|
      builder.add_builder_params(:ems_id => manager.id)
    end
  end
end
