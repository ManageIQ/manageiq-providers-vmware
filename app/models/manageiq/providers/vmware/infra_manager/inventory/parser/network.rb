class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::Network < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def inventory_collection
    persister.lans
  end
end
