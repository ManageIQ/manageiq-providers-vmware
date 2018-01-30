class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ResourcePool < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def inventory_collection
    persister.resource_pools
  end
end
