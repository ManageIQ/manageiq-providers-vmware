class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  def initialize(ems, persister, object_update)
    @ems         = ems
    @persister   = persister
    @object      = object_update.obj
    @kind        = object_update.kind
    @change_set  = object_update.changeSet
    @missing_set = object_update.missingSet
  end

  def parse
    inventory_collection.manager_uuids << manager_ref

    send(parse_kind_method)
  end

  private

  attr_reader :ems, :persister, :object, :kind, :change_set, :missing_set, :inventory_object

  def manager_ref
    object._ref
  end

  def base_result_hash
    {
      :ems_ref => manager_ref,
      :uid_ems => manager_ref,
    }
  end

  def inventory_collection
    raise NotImplementedError, "must be implemented in subclass"
  end

  def inventory_object
    @inventory_object ||= inventory_collection.find_or_build(manager_ref)
  end

  def parse_leave
    nil
  end

  def parse_modify
    inventory_object.assign_attributes(base_result_hash)

    change_set.each do |property_change|
      name = property_change.name
      op   = property_change.op
      val  = property_change.val

      parse_property_change(name, op, val)
    end
  end

  def parse_enter
    parse_modify
  end

  def parse_property_change(name, _op, val)
    case name
    when "name"
      name = URI.decode(val) unless val.nil?
      inventory_object.name = name
    end
  end

  def parse_kind_method
    "parse_#{kind}"
  end
end
