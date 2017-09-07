class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister::Batch < ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister
  def complete
    false
  end

  def saver_strategy
    :concurrent_safe_batch
  end

  def strategy
    :local_db_find_missing_references
  end

  def targeted
    true
  end
end
