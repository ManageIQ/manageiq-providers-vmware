class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister::Stream < ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister
  def inventory_collection_options
    {
      :complete => false,
      :strategy => :local_db_find_missing_references,
    }
  end
end
