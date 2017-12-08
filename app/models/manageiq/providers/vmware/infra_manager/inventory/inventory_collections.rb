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
        :model_class    => ::VmOrTemplate,
        :association    => :vms_and_templates,
        :inventory_object_attributes => [
          :type,
          :cpu_limit,
          :cpu_reserve,
          :cpu_reserve_expand,
          :cpu_shares,
          :cpu_shares_level,
          :ems_ref,
          :ems_ref_obj,
          :uid_ems,
          :connection_state,
          :vendor,
          :name,
          :location,
          :template,
          :memory_limit,
          :memory_reserve,
          :memory_reserve_expand,
          :memory_shares,
          :memory_shares_level,
          :raw_power_state,
          :boot_time,
          :host,
          :ems_cluster,
          :storages,
          :storage,
          :snapshots
        ],
        :builder_params => {
          :ems_id   => ->(persister) { persister.manager.id },
          :vendor   => "vmware",
          :location => "unknown",
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
  end
end
