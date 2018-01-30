class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::Network < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def base_result_hash
    {
      :uid_ems => manager_ref
    }
  end

  def inventory_collection
    persister.lans
  end
end
