class ManageIQ::Providers::Vmware::InfraManager::Inventory::InventoryCollections < ManagerRefresh::InventoryCollectionDefault::InfraManager
  class << self
    def customization_specs(extra_attributes = {})
      attributes = {
        :model_class    => ::CustomizationSpec,
        :association    => :customization_specs,
        :manager_ref    => [:name],
        :builder_params => {
          :ems_id => ->(persister) { persister.manager.id },
        },
      }

      attributes.merge!(extra_attributes)
    end

    def vms_and_templates(extra_attributes = {})
      attributes = {
        :model_class          => ::VmOrTemplate,
        :association          => :vms_and_templates,
        :attributes_blacklist => %i(parent resource_pool),
        :builder_params       => {
          :ems_id => ->(persister) { persister.manager.id },
        },
      }

      attributes.merge!(extra_attributes)
    end

    def storage_profiles(extra_attributes = {})
      attributes = {
        :model_class    => ::StorageProfile,
        :association    => :storage_profiles,
        :builder_params => {
          :ems_id => ->(persister) { persister.manager.id },
        },
      }

      attributes.merge!(extra_attributes)
    end

    def hosts(extra_attributes = {})
      attributes = {:model_class => ManageIQ::Providers::Vmware::InfraManager::HostEsx}
      super(attributes.merge(extra_attributes))
    end

    def hardwares(extra_attributes = {})
      attributes = {:parent_inventory_collections => [:vms_and_templates]}
      super(attributes.merge(extra_attributes))
    end

    def disks(extra_attributes = {})
      attributes = {:parent_inventory_collections => [:vms_and_templates]}
      super(attributes.merge(extra_attributes))
    end

    def operating_systems(extra_attributes = {})
      attributes = {:parent_inventory_collections => [:vms_and_templates]}
      super(attributes.merge(extra_attributes))
    end

    def guest_devices(extra_attributes = {})
      attributes = {:parent_inventory_collections => [:vms_and_templates]}
      super(attributes.merge(extra_attributes))
    end

    def parent_blue_folders(extra_attributes = {})
      relationships(:parent, :ems_metadata, :parent_blue_folders, extra_attributes)
    end

    def vm_resource_pools(extra_attributes = {})
      relationships(:resource_pool, :ems_metadata, :vm_resource_pools, extra_attributes)
    end
  end
end
