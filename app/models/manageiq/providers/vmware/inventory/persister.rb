class ManageIQ::Providers::Vmware::Inventory::Persister < ManagerRefresh::Inventory::Persister
  require_nested :CloudManager

  protected

  def cloud
    ManageIQ::Providers::Vmware::InventoryCollectionDefault::CloudManager
  end

  def targeted?
    false
  end

  def strategy
    nil
  end

  def shared_options
    settings_options = options[:inventory_collections].try(:to_hash) || {}

    settings_options.merge(
      :strategy => strategy,
      :targeted => targeted?,
    )
  end
end
