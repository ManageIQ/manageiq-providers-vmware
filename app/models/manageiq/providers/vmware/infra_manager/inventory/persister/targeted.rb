class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister::Targeted < ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister
  def targeted
    true
  end

  def strategy
    :local_db_find_missing_references
  end
end
