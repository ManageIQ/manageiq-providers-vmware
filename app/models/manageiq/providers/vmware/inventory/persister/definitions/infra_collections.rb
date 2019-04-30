module ManageIQ::Providers::Vmware::Inventory::Persister::Definitions::InfraCollections
  extend ActiveSupport::Concern

  def initialize_infra_inventory_collections
    add_vms_and_templates

    %i(customization_specs
       ext_management_system
       distributed_virtual_switches
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
       snapshots
       operating_systems
       ems_custom_attributes
       networks).each do |name|

      add_collection(infra,
                     name,
                     :parent_inventory_collections => %i(vms_and_templates))
    end

    %i(ems_clusters
       ems_folders
       resource_pools
       storages).each do |name|

      add_collection(infra,
                     name,
                     :attributes_blacklist => %i(parent))
    end

    add_collection(infra, :parent_blue_folders)
    add_collection(infra, :vm_parent_blue_folders)
    add_collection(infra, :vm_resource_pools)
    add_collection(infra, :root_folder_relationship)
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
        :parent_inventory_collections => %i(vms_and_templates)
      )
    end
  end
end
