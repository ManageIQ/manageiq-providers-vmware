class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ComputeResource < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def inventory_collection
    persister.ems_clusters
  end
end
