class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::Folder < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def inventory_collection
    persister.ems_folders
  end

  def base_result_hash
    {
      :type    => "EmsFolder",
      :ems_ref => manager_ref,
      :uid_ems => manager_ref,
    }
  end
end
