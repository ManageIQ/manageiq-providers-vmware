class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister::Targeted < ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister
  def targeted?
    true
  end

  # Lazily initialize the tag_mapper only if it is needed for a targeted refresh
  def tag_mapper
    initialize_tag_mapper if @tag_mapper.nil?
    @tag_mapper
  end

  def strategy
    :local_db_find_missing_references
  end
end
