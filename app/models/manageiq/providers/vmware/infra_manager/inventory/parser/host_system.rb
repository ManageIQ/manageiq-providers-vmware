class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::HostSystem < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def inventory_collection
    persister.hosts
  end

  def base_result_hash
    {
      :ems_ref => manager_ref,
    }
  end

  def parse_property_change(name, op, val)
    result = super

    case name
    when "hardware.systemInfo.uuid"
      result[:uid_ems] = val
    end

    result
  end
end
