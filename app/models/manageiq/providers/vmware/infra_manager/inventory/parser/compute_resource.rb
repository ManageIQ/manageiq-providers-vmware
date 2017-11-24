class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ComputeResource < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def inventory_collection
    persister.ems_clusters
  end

  def base_result_hash
    {
      :ems_ref => manager_ref,
      :uid_ems => manager_ref,
    }
  end
end
