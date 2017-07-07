class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  attr_reader :persister
  private     :persister

  def initialize(ems)
    persister_class = ems.class::Inventory::Persister
    @persister = persister_class.new(ems)
  end

  def parse(object, props)
    object_type = object.class.wsdl_name
    parse_method = "parse_#{object_type.underscore}"

    raise "Missing parser for #{object_type}" unless respond_to?(parse_method)

    send(parse_method, object, props)
  end

  def parse_compute_resource(object, props)
  end
  alias parse_cluster_compute_resource parse_compute_resource

  def parse_datastore(object, props)
  end

  def parse_distributed_virtual_switch(object, props)
  end
  alias parse_vmware_distributed_virtual_switch parse_distributed_virtual_switch

  def parse_folder(object, props)
  end
  alias parse_datacenter parse_folder

  def parse_host_system(object, props)
  end

  def parse_network(object, props)
  end
  alias parse_distributed_virtual_portgroup parse_network

  def parse_resource_pool(object, props)
  end
  alias parse_virtual_app parse_resource_pool

  def parse_virtual_machine(object, props)
  end
end
