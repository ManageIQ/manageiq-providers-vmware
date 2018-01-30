class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::Datastore < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def inventory_collection
    persister.storages
  end

  def base_result_hash
    {
      :ems_ref => manager_ref,
    }
  end

  alias storage inventory_object

  def parse_property_change(name, op, val)
    super

    case name
    when "host"
      val.each do |host_mount|
        read_only = host_mount.mountInfo.accessMode == "readOnly"
        host_ref  = host_mount.key._ref

        persister.host_storages.find_or_build_by(
          :host    => persister.hosts.find_or_build(host_ref),
          :storage => persister.storages.find_or_build(manager_ref),
        ).assign_attributes(
          :read_only => read_only,
          :ems_ref   => manager_ref
        )
      end
    when "summary.capacity"
      storage.total_space = val
    when "summary.freeSpace"
      storage.free_space = val
    when "summary.uncommitted"
      storage.uncommitted = val
    when "summary.url"
      storage.location = manager_ref # TODO: set to val when manager_ref is fixed
    end
  end
end
