class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::HostSystem < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def inventory_collection
    persister.hosts
  end

  def base_result_hash
    {
      :ems_ref => manager_ref,
    }
  end
end
