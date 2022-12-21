class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :Batch
  require_nested :Full
  require_nested :Targeted

  attr_reader :tracking_uuid

  def initialize_inventory_collections
    # Build a UUID which can be used to track the collection and saving of this persister instance
    @tracking_uuid = SecureRandom.uuid

    add_collection(infra, :customization_specs)
    add_collection(infra, :disks, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :distributed_virtual_switches)
    add_collection(infra, :distributed_virtual_lans)
    add_collection(infra, :clusters)
    add_collection(infra, :ems_custom_attributes, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :vm_and_template_labels, :parent_inventory_collections => %i[vms_and_templates]) do |builder|
      builder.add_properties(:complete => false) if targeted?
    end
    add_collection(infra, :vm_and_template_taggings, :parent_inventory_collections => %i[vms_and_templates]) do |builder|
      builder.add_properties(:complete => false) if targeted?
    end
    add_collection(infra, :ems_extensions)
    add_collection(infra, :ems_folders)
    add_collection(infra, :ems_licenses)
    add_collection(infra, :ext_management_system)
    add_collection(infra, :guest_devices, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :hardwares, :parent_inventory_collections => %i[vms_and_templates]) do |builder|
      builder.add_properties(:track_record_changes => %i[cpu_sockets memory_mb cpu_cores_per_socket cpu_total_cores])
    end

    add_collection(infra, :hosts) do |builder|
      builder.add_properties(:custom_reconnect_block => hosts_reconnect_block)
    end
    add_collection(infra, :host_hardwares)
    add_collection(infra, :host_guest_devices)
    add_collection(infra, :host_networks)
    add_collection(infra, :host_storages, :parent_inventory_collections => %i[storages]) do |builder|
      builder.add_properties(:arel => manager.host_storages.joins(:storage))
    end
    add_collection(infra, :host_switches)
    add_collection(infra, :host_system_services)
    add_collection(infra, :host_operating_systems)
    add_collection(infra, :host_virtual_switches)
    add_collection(infra, :host_virtual_lans)
    add_collection(infra, :miq_scsi_luns)
    add_collection(infra, :miq_scsi_targets)
    add_collection(infra, :networks, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :operating_systems, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :resource_pools)
    add_collection(infra, :snapshots, :parent_inventory_collections => %i[vms_and_templates])
    add_collection(infra, :storages)
    add_collection(infra, :storage_profiles)
    add_collection(infra, :storage_profile_storages)
    add_collection(infra, :parent_blue_folders)
    add_collection(infra, :vms_and_templates, {}, {:without_sti => true}) do |builder|
      builder.vm_template_shared
      builder.add_properties(:custom_reconnect_block => vms_and_templates_reconnect_block)
    end
    add_collection(infra, :vm_parent_blue_folders)
    add_collection(infra, :vm_resource_pools)
    add_collection(infra, :root_folder_relationship)
    add_collection(infra, :orchestration_templates)
    vms_and_templates_assign_created_on if ::Settings.ems_refresh.capture_vm_created_on_date
    track_vm_cpu_memory_changes
  end

  def vim_class_to_collection(managed_object)
    case managed_object
    when RbVmomi::VIM::ComputeResource
      clusters
    when RbVmomi::VIM::Datacenter
      ems_folders
    when RbVmomi::VIM::HostSystem
      hosts
    when RbVmomi::VIM::Folder
      ems_folders
    when RbVmomi::VIM::ResourcePool
      resource_pools
    end
  end

  private

  def track_vm_cpu_memory_changes
    custom_save_block = lambda do |ems, inventory_collection|
      hardwares = inventory_collection.dependency_attributes[:hardwares]&.first
      return if hardwares.nil?
      return if hardwares.record_changes.blank?

      # TODO raise an event
    end

    settings = {:without_model_class => true, :auto_inventory_attributes => false}

    add_collection(infra, :track_vm_cpu_memory_changes, {}, settings) do |builder|
      builder.add_custom_save_block(custom_save_block)
      builder.add_dependency_attributes(:hardwares => ->(persister) { [persister.hardwares] })
    end
  end

  def vms_and_templates_assign_created_on
    custom_save_block = lambda do |ems, inventory_collection|
      vms_and_templates = inventory_collection.dependency_attributes[:vms_and_templates]&.first
      return if vms_and_templates.nil?

      created_vm_ids = vms_and_templates.created_records.map { |rec| rec[:id] }
      ems.assign_ems_created_on_queue(created_vm_ids) unless created_vm_ids.empty?
    end

    settings = {:without_model_class => true, :auto_inventory_attributes => false}

    add_collection(infra, :vms_and_templates_assign_created_on, {}, settings) do |builder|
      builder.add_custom_save_block(custom_save_block)
      builder.add_dependency_attributes(:vms_and_templates => ->(persister) { [persister.vms_and_templates] })
    end
  end

  def hosts_reconnect_block
    lambda do |inventory_collection, inventory_objects_index, attributes_index|
      relation = inventory_collection.model_class.where(:ems_id => nil)
      return if relation.count <= 0

      inventory_objects_index.each do |ref, obj|
        record = look_up_host(relation, obj.hostname, obj.ipaddress)
        next if record.nil?

        inventory_objects_index.delete(ref)
        hash = attributes_index.delete(ref)

        record.assign_attributes(hash.except(:id, :type))
        if !inventory_collection.check_changed? || record.changed?
          record.save!
          inventory_collection.store_updated_records(record)
        end

        obj.id = record.id
      end
    end
  end

  def look_up_host(relation, hostname, ipaddr)
    return if ["localhost", "localhost.localdomain", "127.0.0.1"].include_any?(hostname, ipaddr)

    record   = relation.where("lower(hostname) = ?", hostname.downcase).find_by(:ipaddress => ipaddr) if hostname && ipaddr
    record ||= relation.find_by("lower(hostname) = ?", hostname.downcase)                             if hostname
    record ||= relation.find_by(:ipaddress => ipaddr)                                                 if ipaddr
    record ||= relation.find_by("lower(hostname) LIKE ?", "#{hostname.downcase}.%")                   if hostname

    record
  end

  def vms_and_templates_reconnect_block
    lambda do |inventory_collection, inventory_objects_index, attributes_index|
      relation = inventory_collection.model_class.where(:ems_id => nil)
      return if relation.count <= 0

      vms_by_uid_ems = inventory_objects_index.values.group_by(&:uid_ems).except(nil)
      relation.where(:uid_ems => vms_by_uid_ems.keys).order(:id => :asc).find_each(:batch_size => 100).each do |record|
        inventory_object = vms_by_uid_ems[record.uid_ems].shift
        next if inventory_object.nil?

        hash = attributes_index.delete(inventory_object.ems_ref)
        inventory_objects_index.delete(inventory_object.ems_ref)

        # Skip if hash is blank, which can happen when having several archived entities with the same ref
        next unless hash

        record.assign_attributes(hash.except(:id, :type))
        if !inventory_collection.check_changed? || record.changed?
          record.save!
          inventory_collection.store_updated_records(record)
        end

        inventory_object.id = record.id
      end
    end
  end
end
