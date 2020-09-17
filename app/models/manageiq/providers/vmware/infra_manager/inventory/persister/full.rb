class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister::Full < ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister
  def initialize_inventory_collections
    super

    initialize_tag_mapper
  end
end
