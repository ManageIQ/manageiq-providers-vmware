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
    when "summary.capacity"
      storage.total_space = val
    when "summary.freeSpace"
      storage.free_space = val
    when "summary.uncommitted"
      storage.uncommitted = val
    when "summary.url"
      storage.location = val
    end
  end
end
