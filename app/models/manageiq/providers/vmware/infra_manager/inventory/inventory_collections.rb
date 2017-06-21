class ManageIQ::Providers::Vmware::InfraManager::Inventory::InventoryCollections < ManagerRefresh::InventoryCollectionDefault::InfraManager
  class << self
    def vms(extra_attributes = {})
      attributes = {:model_class => ManageIQ::Providers::Vmware::InfraManager::Vm}
      super(attributes.merge(extra_attributes))
    end

    def hosts(extra_attributes = {})
      attributes = {:model_class => ManageIQ::Providers::Vmware::InfraManager::HostEsx}
      super(attributes.merge(extra_attributes))
    end
  end
end
