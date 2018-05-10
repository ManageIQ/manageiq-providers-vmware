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
        :model_class            => ::VmOrTemplate,
        :association            => :vms_and_templates,
        :delete_method          => :disconnect_inv,
        :attributes_blacklist   => %i(parent resource_pool),
        :custom_reconnect_block => ManagerRefresh::InventoryCollectionDefault::INVENTORY_RECONNECT_BLOCK,
        :builder_params         => {
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

    def ems_folders(extra_attributes = {})
      attributes = {:attributes_blacklist => %i(parent)}
      super(attributes.merge(extra_attributes))
    end

    def resource_pools(extra_attributes = {})
      attributes = {:attributes_blacklist => %i(parent)}
      super(attributes.merge(extra_attributes))
    end

    def ems_clusters(extra_attributes = {})
      attributes = {:attributes_blacklist => %i(parent)}
      super(attributes.merge(extra_attributes))
    end

    def storages(extra_attributes = {})
      attributes = {:attributes_blacklist => %i(parent)}
      super(attributes.merge(extra_attributes))
    end

    def hosts(extra_attributes = {})
      attributes = {
        :attributes_blacklist => %i(parent),
        :model_class          => ManageIQ::Providers::Vmware::InfraManager::HostEsx,
      }
      super(attributes.merge(extra_attributes))
    end

    def switchs(extra_attributes = {})
      attributes = {:attributes_blacklist => %i(parent)}
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
      relationships(:parent, :ems_metadata, nil, :parent_blue_folders, extra_attributes)
    end

    def vm_parent_blue_folders(extra_attributes = {})
      relationships(:parent, :ems_metadata, "EmsFolder", :vm_parent_blue_folders, extra_attributes)
    end

    def vm_resource_pools(extra_attributes = {})
      relationships(:resource_pool, :ems_metadata, "ResourcePool", :vm_resource_pools, extra_attributes)
    end

    def relationships(relationship_key, relationship_type, parent_type, association, extra_attributes = {})
      relationship_save_block = lambda do |_ems, inventory_collection|
        parents  = Hash.new { |h, k| h[k] = {} }
        children = Hash.new { |h, k| h[k] = {} }

        inventory_collection.dependency_attributes.each_value do |dependency_collections|
          next if dependency_collections.blank?

          dependency_collections.each do |collection|
            next if collection.blank?

            collection.data.each do |obj|
              parent = obj.data[relationship_key].try(&:load)
              next if parent.nil?

              parent_klass = parent.inventory_collection.model_class

              # Save the model_class and id of the parent for each child
              children[collection.model_class][obj.id] = [parent_klass, parent.id]

              # This will be populated later when looking up all the parent ids
              parents[parent_klass][parent.id] = nil
            end
          end
        end

        ActiveRecord::Base.transaction do
          # Lookup all of the parent records
          parents.each do |model_class, ids|
            model_class.find(ids.keys).each { |record| ids[record.id] = record }
          end

          # Loop through all children and assign parents
          children.each do |model_class, ids|
            child_records = model_class.find(ids.keys).index_by(&:id)

            ids.each do |id, parent_info|
              child = child_records[id]

              parent_klass, parent_id = parent_info
              parent = parents[parent_klass][parent_id]

              child.with_relationship_type(relationship_type) do
                prev_parent = child.parent(:of_type => parent_type)
                unless prev_parent == parent
                  prev_parent&.remove_child(child)
                  parent.add_child(child)
                end
              end
            end
          end
        end
      end

      attributes = {
        :association       => association,
        :custom_save_block => relationship_save_block,
      }
      attributes.merge!(extra_attributes)
    end
  end
end
