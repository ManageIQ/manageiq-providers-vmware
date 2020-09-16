class ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister::Full < ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister

  def initialize_inventory_collections
    super

    initialize_tag_mapper
  end

  private

  def initialize_tag_mapper
    @tag_mapper = ContainerLabelTagMapping.mapper
    collections[:tags_to_resolve] = @tag_mapper.tags_to_resolve_collection
  end
end
