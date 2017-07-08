class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  attr_reader :persister
  private     :persister

  def initialize(persister)
    @persister = persister
  end

  def parse(object, props)
    object_type = object.class.wsdl_name
    parse_method = "parse_#{object_type.underscore}"

    raise "Missing parser for #{object_type}" unless respond_to?(parse_method)

    send(parse_method, object, props)
  end

  def parse_compute_resource(object, props)
    persister.ems_clusters.manager_uuids << object._ref
    return if props.nil?

    cluster_hash = {
      :ems_ref => object._ref,
      :uid_ems => object._ref,
    }

    if props.include?("name")
      cluster_hash[:name] = URI.decode(props["name"])
    end

    persister.ems_clusters.build(cluster_hash)
  end
  alias parse_cluster_compute_resource parse_compute_resource

  def parse_datastore(object, props)
    persister.storages.manager_uuids << object._ref
    return if props.nil?

    storage_hash = {
      :ems_ref => object._ref,
    }

    if props.include?("summary.name")
      storage_hash[:name] = props["summary.name"]
    end
    if props.include?("summary.url")
      storage_hash[:location] = props["summary.url"]
    end

    persister.storages.build(storage_hash)
  end

  def parse_distributed_virtual_switch(object, props)
    persister.switches.manager_uuids << object._ref
    return if props.nil?

    switch_hash = {
      :uid_ems => object._ref,
      :shared  => true,
    }

    persister.switches.build(switch_hash)
  end
  alias parse_vmware_distributed_virtual_switch parse_distributed_virtual_switch

  def parse_folder(object, props)
    persister.ems_folders.manager_uuids << object._ref
    return if props.nil?

    type = case object
           when RbVmomi::VIM::Datacenter
             "Datacenter"
           when RbVmomi::VIM::Folder
             "EmsFolder"
           end

    folder_hash = {
      :ems_ref => object._ref,
      :uid_ems => object._ref,
      :type    => type,
    }

    if props.include?("name")
      folder_hash[:name] = URI.decode(props["name"])
    end

    persister.ems_folders.build(folder_hash)
  end
  alias parse_datacenter parse_folder

  def parse_host_system(object, props)
    persister.hosts.manager_uuids << object._ref
    return if props.nil?

    host_hash = {
      :ems_ref => object._ref,
      :type    => "ManageIQ::Providers::Vmware::InfraManager::HostEsx",
    }

    if props.include?("config.network.dnsConfig.hostName")
      host_hash[:name]     = props["config.network.dnsConfig.hostName"]
      host_hash[:hostname] = props["config.network.dnsConfig.hostName"]
    end

    persister.hosts.build(host_hash)
  end

  def parse_network(object, props)
  end
  alias parse_distributed_virtual_portgroup parse_network

  def parse_resource_pool(object, props)
    persister.resource_pools.manager_uuids << object._ref
    return if props.nil?

    rp_hash = {
      :ems_ref => object._ref,
      :uid_ems => object._ref,
      :vapp    => object.kind_of?(RbVmomi::VIM::VirtualApp),
    }

    if props.include?("name")
      rp_hash[:name] = URI.decode(props["name"])
    end

    persister.resource_pools.build(rp_hash)
  end
  alias parse_virtual_app parse_resource_pool

  def parse_virtual_machine(object, props)
    persister.vms_and_templates.manager_uuids << object._ref
    return if props.nil?

    vm_hash = {
      :ems_ref => object._ref,
      :vendor  => "vmware",
    }

    if props.include?("summary.config.uuid")
      vm_hash[:uid_ems] = props["summary.config.uuid"]
    end
    if props.include?("summary.config.name")
      vm_hash[:name] = URI.decode(props["summary.config.name"])
    end
    if props.include?("summary.config.vmPathName")
      vm_hash[:location] = props["summary.config.vmPathName"]
    end
    if props.include?("summary.config.template")
      vm_hash[:template] = props["summary.config.template"].to_s.downcase == "true"

      type = "ManageIQ::Providers::Vmware::InfraManager::#{vm_hash[:template] ? "Template" : "Vm"}"
      vm_hash[:type] = type
    end

    persister.vms_and_templates.build(vm_hash)
  end
end
