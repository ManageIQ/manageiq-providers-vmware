class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  def initialize(ems, persister, object_update)
    @ems         = ems
    @persister   = persister
    @object      = object_update.obj
    @kind        = object_update.kind
    @change_set  = object_update.changeSet
    @missing_set = object_update.missingSet
  end

  private

  attr_reader :ems, :persister, :object, :kind, :change_set, :missing_set
end
