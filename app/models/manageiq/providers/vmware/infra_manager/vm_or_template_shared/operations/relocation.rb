module ManageIQ::Providers::Vmware::InfraManager::VmOrTemplateShared::Operations::Relocation
  extend ActiveSupport::Concern

  included do
    supports :migrate do
      reason   = _("Migrate not supported because VM is blank")    if blank?
      reason ||= _("Migrate not supported because VM is orphaned") if orphaned?
      reason ||= _("Migrate not supported because VM is archived") if archived?
      unsupported_reason_add(:migrate, reason) if reason
    end
    supports :move_into_folder do
      reason = _("Move not supported because VM is not active") if ext_management_system.nil?
      unsupported_reason_add(:migrate, reason) if reason
    end
    supports :relocate do
      reason = _("Relocate not supported because VM is not active") if ext_management_system.nil?
      unsupported_reason_add(:migrate, reason) if reason
    end
  end

  def raw_migrate(host, pool = nil, priority = "defaultPriority", state = nil)
    raise _("Host not specified, unable to migrate VM") unless host.kind_of?(Host)

    if pool.nil?
      pool = host.default_resource_pool || (host.ems_cluster && host.ems_cluster.default_resource_pool)
      unless pool.kind_of?(ResourcePool)
        raise _("Default Resource Pool for Host <%{name}> not found, unable to migrate VM") % {:name => host.name}
      end
    else
      unless pool.kind_of?(ResourcePool)
        raise _("Specified Resource Pool <%{pool_name}> for Host <%{name}> is invalid, unable to migrate VM") %
                {:pool_name => pool.inspect, :name => host.name}
      end
    end

    if host_id == host.id
      raise _("The VM '%{name}' can not be migrated to the same host it is already running on.") % {:name => name}
    end

    host_mor = host.ems_ref_obj
    pool_mor = pool.ems_ref_obj
    run_command_via_parent(:vm_migrate, :host => host_mor, :pool => pool_mor, :priority => priority, :state => state)
  end

  def raw_relocate(host, pool = nil, datastore = nil, disk_transform = nil, transform = nil, priority = "defaultPriority", disk = nil)
    raise _("Unable to relocate VM: Specified Host is not a valid object") if host && !host.kind_of?(Host)
    if pool && !pool.kind_of?(ResourcePool)
      raise _("Unable to relocate VM: Specified Resource Pool is not a valid object")
    end
    if datastore && !datastore.kind_of?(Storage)
      raise _("Unable to relocate VM: Specified Datastore is not a valid object")
    end

    if pool.nil?
      if host
        pool = host.default_resource_pool || (host.ems_cluster && host.ems_cluster.default_resource_pool)
        unless pool.kind_of?(ResourcePool)
          raise _("Default Resource Pool for Host <%{name}> not found, unable to migrate VM") % {:name => host.name}
        end
      end
    else
      unless pool.kind_of?(ResourcePool)
        raise _("Specified Resource Pool <%{pool_name}> for Host <%{name}> is invalid, unable to migrate VM") %
                {:pool_name => pool.inspect, :name => host.name}
      end
    end

    host_mor      = host.ems_ref_obj      if host
    pool_mor      = pool.ems_ref_obj      if pool
    datastore_mor = datastore.ems_ref_obj if datastore

    disk_move_type = case disk_transform
      when 'thin'  then VimString.new('sparse', "VirtualMachineRelocateTransformation")
      when 'thick' then VimString.new('flat', "VirtualMachineRelocateTransformation")
      else disk_transform
      end

    run_command_via_parent(:vm_relocate, :host => host_mor, :pool => pool_mor, :datastore => datastore_mor, :disk_move_type => disk_move_type, :transform => transform, :priority => priority, :disk => disk)
  end

  def raw_move_into_folder(folder)
    run_command_via_parent(:vm_move_into_folder, :folder => folder)
  end
end
