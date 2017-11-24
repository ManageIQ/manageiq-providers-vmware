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

    parsed_hash = send(parse_kind_method)

    inventory_collection.build(parsed_hash) unless parsed_hash.nil?
  end

  private

  attr_reader :ems, :persister, :object, :kind, :change_set, :missing_set

  def manager_ref
    object._ref
  end

  def inventory_collection
    raise NotImplementedError, "must be implemented in subclass"
  end

  def parse_leave
    nil
  end

  def parse_modify
    result = base_result_hash

    change_set.each do |property_change|
      name = property_change.name
      op   = property_change.op
      val  = property_change.val

      parsed = parse_property_change(name, op, val)
      result.merge!(parsed)
    end

    result
  end

  def parse_enter
    parse_modify
  end

  def base_result_hash
    {}
  end

  def parse_property_change(name, _op, val)
    result = {}

    case name
    when "name"
      name = URI.decode(val) unless val.nil?
      result[:name] = name
    end

    result
  end

  def parse_kind_method
    "parse_#{kind}"
  end
end
