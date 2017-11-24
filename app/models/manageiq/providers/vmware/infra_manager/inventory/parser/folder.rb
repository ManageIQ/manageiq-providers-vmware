class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::Folder < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def inventory_collection
    persister.ems_folders
  end
end
