class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::Datacenter < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::Folder
  private

  def inventory_collection
    persister.ems_folders
  end

  def base_result_hash
    super.merge(:type => "Datacenter")
  end
end
