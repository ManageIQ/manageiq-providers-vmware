class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister::Batch < ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister
  def complete
    false
  end

  def strategy
    :local_db_find_missing_references
  end
end
