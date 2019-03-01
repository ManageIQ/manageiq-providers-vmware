module ManageIQ::Providers::Vmware::Inventory::Persister::Definitions::InfraCollections
  extend ActiveSupport::Concern

  def initialize_infra_inventory_collections
    add_vms_and_templates

    %i(customization_specs
       ext_management_system
       host_hardwares
       host_guest_devices
       host_networks
       host_storages
       host_switches
       host_system_services
       host_operating_systems
       host_virtual_switches
       lans
       miq_scsi_luns
       miq_scsi_targets
       storage_profiles).each do |name|

      add_collection(infra, name)
    end

    add_hosts

    %i(disks
       guest_devices
       hardwares
       operating_systems
       ems_custom_attributes
       networks).each do |name|

      add_collection(infra,
                     name,
                     :parent_inventory_collections => %i(vms_and_templates))
    end

    add_snapshots
    add_distributed_virtual_switches

    %i(ems_clusters
       ems_folders
       resource_pools
       storages).each do |name|

      add_collection(infra,
                     name,
                     :attributes_blacklist => %i(parent))
    end

    add_parent_blue_folders
    add_vm_parent_blue_folders
    add_vm_resource_pools
    add_root_folder_relationship
  end

  # ------ IC provider specific definitions -------------------------
  def add_vms_and_templates
    add_collection(infra, :vms_and_templates) do |builder|
      builder.add_properties(
        :model_class            => ::VmOrTemplate,
        :delete_method          => :disconnect_inv,
        :attributes_blacklist   => %i(parent resource_pool),
        :custom_reconnect_block => infra::INVENTORY_RECONNECT_BLOCK,
      )
      builder.add_default_values(:ems_id => manager.id)
    end
  end

  def add_hosts
    add_collection(infra, :hosts) do |builder|
      builder.add_properties(
        :attributes_blacklist => %i(parent),
        :model_class          => ManageIQ::Providers::Vmware::InfraManager::HostEsx
      )
    end
  end


  def add_snapshots
    add_collection(infra, :snapshots) do |builder|
      builder.add_properties(
        :manager_ref                  => %i(vm_or_template uid),
        :parent_inventory_collections => %i(vms_and_templates)
      )
    end
  end

  def add_distributed_virtual_switches
    add_collection(infra, :distributed_virtual_switches) do |builder|
      builder.add_properties(
        :attributes_blacklist => %i(parent),
        :secondary_refs       => {:by_switch_uuid => %i(switch_uuid)}
      )
    end
  end

  def add_parent_blue_folders
    add_collection(infra,
                   :parent_blue_folders,
                   shared_options_overrides,
                   :without_model_class => true) do |builder|

      builder.add_properties(
        :custom_save_block => relationship_save_block(:parent, :ems_metadata, nil),
      )

      builder.add_dependency_attributes(
        %i(ems_clusters
           ems_folders
           hosts
           resource_pools
           storages).each_with_object({}) do |collection_key, obj|

          obj[collection_key] = [collections[collection_key]]
        end
      )
    end
  end

  def add_vm_parent_blue_folders
    add_collection(infra,
                   :vm_parent_blue_folders,
                   shared_options_overrides,
                   :without_model_class => true) do |builder|

      builder.add_properties(
        :custom_save_block => relationship_save_block(:parent, :ems_metadata, "EmsFolder")
      )

      builder.add_dependency_attributes(
        :vms_and_templates => [collections[:vms_and_templates]]
      )
    end
  end

  def add_vm_resource_pools
    add_collection(infra,
                   :vm_resource_pools,
                   shared_options_overrides,
                   :without_model_class => true) do |builder|

      builder.add_properties(
        :custom_save_block => relationship_save_block(:resource_pool, :ems_metadata, "ResourcePool")
      )

      builder.add_dependency_attributes(
        :vms_and_templates => [collections[:vms_and_templates]]
      )
    end
  end

  def add_root_folder_relationship
    add_collection(infra,
                   :root_folder_relationship,
                   shared_options_overrides,
                   :without_model_class => true) do |builder|

      builder.add_properties(
        :custom_save_block => root_folder_save_block
      )

      builder.add_dependency_attributes(
        :ems_folders => [collections[:ems_folders]]
      )
    end
  end

  # --------------
  # options used for overwrite the default one for special ICs
  def shared_options_overrides
    {
      :complete       => nil,
      :saver_strategy => nil,
      :strategy       => nil,
      :targeted       => nil
    }
  end

  def relationship_save_block(relationship_key, relationship_type, parent_type)
    lambda do |_ems, inventory_collection|
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
            prev_parent = child.with_relationship_type(relationship_type) { child.parents(:of_type => parent_type)&.first }

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

            parent.remove_children(old_children) if old_children.present?
            parent.add_children(new_children) if new_children.present?
          end
        end
      end
    end
  end

  def root_folder_save_block
    lambda do |ems, inventory_collection|
      folder_inv_collection = inventory_collection.dependency_attributes[:ems_folders]&.first
      return if folder_inv_collection.nil?

      # All folders must have a parent except for the root folder
      root_folder_obj = folder_inv_collection.data.detect { |obj| obj.data[:parent].nil? }
      return if root_folder_obj.nil?

      root_folder = folder_inv_collection.model_class.find(root_folder_obj.id)
      root_folder.with_relationship_type(:ems_metadata) { root_folder.parent = ems }
    end
  end
end
