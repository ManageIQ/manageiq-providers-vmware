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

    def lans(extra_attributes = {})
      attributes = {
        :manager_ref => %i(switch uid_ems),
        :parent_inventory_collections => [:switches]
      }
      super(attributes.merge(extra_attributes))
    end

    def hosts(extra_attributes = {})
      attributes = {
        :attributes_blacklist => %i(parent),
        :model_class          => ManageIQ::Providers::Vmware::InfraManager::HostEsx,
      }
      super(attributes.merge(extra_attributes))
    end

    def switches(extra_attributes = {})
      attributes = {
        :attributes_blacklist => %i(parent),
        :secondary_refs       => {:by_switch_uuid => [:switch_uuid]},
      }
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

    def snapshots(extra_attributes = {})
      attributes = {
        :manager_ref                  => [:vm_or_template, :uid],
        :parent_inventory_collections => [:vms_and_templates],
      }
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

    def root_folder_relationship(extra_attributes = {})
      root_folder_save_block = lambda do |ems, inventory_collection|
        folder_inv_collection = inventory_collection.dependency_attributes[:ems_folders]&.first
        return if folder_inv_collection.nil?

        # All folders must have a parent except for the root folder
        root_folder_obj = folder_inv_collection.data.detect { |obj| obj.data[:parent].nil? }
        return if root_folder_obj.nil?

        root_folder = folder_inv_collection.model_class.find(root_folder_obj.id)
        root_folder.with_relationship_type(:ems_metadata) { root_folder.parent = ems }
      end

      attributes = {
        :association       => :root_folder_relationships,
        :custom_save_block => root_folder_save_block,
      }
      attributes.merge!(extra_attributes)
    end

    def relationships(relationship_key, relationship_type, parent_type, association, extra_attributes = {})
      relationship_save_block = lambda do |_ems, inventory_collection|
        children_by_parent = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } }
        parent_by_child    = Hash.new { |h, k| h[k] = {} }

        inventory_collection.dependency_attributes.each_value do |dependency_collections|
          next if dependency_collections.blank?

          dependency_collections.each do |collection|
            next if collection.blank?

            collection.data.each do |obj|
              parent = obj.data[relationship_key].try(&:load)
              next if parent.nil?

              parent_klass = parent.inventory_collection.model_class

              children_by_parent[parent_klass][parent.id] << [collection.model_class, obj.id]
              parent_by_child[collection.model_class][obj.id] = [parent_klass, parent.id]
            end
          end
        end

        ActiveRecord::Base.transaction do
          child_recs = parent_by_child.each_with_object({}) do |(model_class, child_ids), hash|
            hash[model_class] = model_class.find(child_ids.keys).index_by(&:id)
          end

          children_to_remove = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } }
          children_to_add    = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } }

          parent_recs_needed = Hash.new { |h, k| h[k] = [] }

          child_recs.each do |model_class, children_by_id|
            children_by_id.each_value do |child|
              new_parent_klass, new_parent_id = parent_by_child[model_class][child.id]
              prev_parent = child.with_relationship_type(relationship_type) { child.parent(:of_type => parent_type) }

              next if prev_parent && (prev_parent.class.base_class == new_parent_klass && prev_parent.id == new_parent_id)

              children_to_remove[prev_parent.class.base_class][prev_parent.id] << child if prev_parent
              children_to_add[new_parent_klass][new_parent_id] << child

              parent_recs_needed[prev_parent.class.base_class] << prev_parent.id if prev_parent
              parent_recs_needed[new_parent_klass] << new_parent_id
            end
          end

          parent_recs = parent_recs_needed.each_with_object({}) do |(model_class, parent_ids), hash|
            hash[model_class] = model_class.find(parent_ids.uniq)
          end

          parent_recs.each do |model_class, parents|
            parents.each do |parent|
              old_children = children_to_remove[model_class][parent.id]
              new_children = children_to_add[model_class][parent.id]

              parent.remove_children(old_children) unless old_children.blank?
              parent.add_children(new_children) unless new_children.blank?
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
