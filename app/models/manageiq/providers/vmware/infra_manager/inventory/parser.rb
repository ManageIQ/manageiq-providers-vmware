class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  attr_reader :persister
  private     :persister

  def initialize(persister)
    @persister = persister
  end

  def parse(object_update)
    object = object_update.obj
    return if object.nil?
  end
end
