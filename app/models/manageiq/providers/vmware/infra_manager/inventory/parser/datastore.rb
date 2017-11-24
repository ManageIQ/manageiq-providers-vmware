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

  def parse_property_change(name, op, val)
    result = super

    case name
    when "summary.capacity"
      result[:total_space] = val
    when "summary.freeSpace"
      result[:free_space] = val
    when "summary.uncommitted"
      result[:uncommitted] = val
    when "summary.url"
      result[:location] = val
    end

    result
  end
end
