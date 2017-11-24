class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::Datastore < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def inventory_collection
    persister.storages
  end
end
