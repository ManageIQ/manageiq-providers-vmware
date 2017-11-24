class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::VirtualMachine < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def inventory_collection
    persister.vms_and_templates
  end
end
