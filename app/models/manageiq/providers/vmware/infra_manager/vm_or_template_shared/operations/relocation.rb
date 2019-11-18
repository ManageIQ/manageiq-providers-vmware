module ManageIQ::Providers::Vmware::InfraManager::VmOrTemplateShared::Operations::Relocation
  extend ActiveSupport::Concern

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

  def raw_relocate(host, pool = nil, datastore = nil, disk_move_type = nil, transform = nil, priority = "defaultPriority", disk = nil)
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

    host_mor      = host.ems_ref_obj if host
    pool_mor      = pool.ems_ref_obj if pool
    datastore_mor = VimString.new(datastore.ems_ref, datastore.ems_ref_type, :ManagedObjectReference) if datastore

    run_command_via_parent(:vm_relocate, :host => host_mor, :pool => pool_mor, :datastore => datastore_mor, :disk_move_type => disk_move_type, :transform => transform, :priority => priority, :disk => disk)
  end

  def raw_move_into_folder(folder)
    run_command_via_parent(:vm_move_into_folder, :folder => folder)
  end
end
