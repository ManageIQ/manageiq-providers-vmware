class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::Datacenter < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::Folder
  private

  def inventory_collection
    persister.datacenters
  end
end
