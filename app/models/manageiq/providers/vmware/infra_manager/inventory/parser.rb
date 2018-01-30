class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  require_nested :ComputeResource
  require_nested :Datastore
  require_nested :Folder
  require_nested :HostSystem
  require_nested :ManagedEntity
  require_nested :Network
  require_nested :ResourcePool
  require_nested :Switch
  require_nested :VirtualMachine

  def initialize(ems, persister)
    @ems       = ems
    @persister = persister
  end

  def parse(object_update)
    object = object_update.obj
    return if object.nil?

    parser_klass = parser_for_object(object)
    return if parser_klass.nil?

    parser_klass.new(ems, persister, object_update).parse
  end

  private

  attr_reader :ems, :persister

  def parser_for_object(object)
    "#{self.class.name}::#{object.class.wsdl_name}".constantize
  rescue
    nil
  end
end
