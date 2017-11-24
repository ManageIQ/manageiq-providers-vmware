class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ResourcePool < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def inventory_collection
    persister.resource_pools
  end

  def base_result_hash
    {
      :ems_ref => manager_ref,
      :uid_ems => manager_ref,
    }
  end
end
