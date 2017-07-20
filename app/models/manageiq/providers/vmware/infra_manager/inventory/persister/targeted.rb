class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister::Targeted < ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister
  def inventory_collection_options
    {
      :targeted => true,
      :strategy => :local_db_find_missing_references,
    }
  end
end
