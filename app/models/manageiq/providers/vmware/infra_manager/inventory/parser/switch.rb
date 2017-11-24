class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::Switch < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def inventory_collection
    persister.switches
  end
end
