class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  include_concern :ComputeResource
  include_concern :Datacenter
  include_concern :Datastore
  include_concern :Folder
  include_concern :HostSystem
  include_concern :ResourcePool
  include_concern :VirtualMachine

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

    parse_compute_resource_summary(cluster_hash, props)
    parse_compute_resource_das_config(cluster_hash, props)
    parse_compute_resource_drs_config(cluster_hash, props)
    parse_compute_resource_children(cluster_hash, props)

    persister.ems_clusters.build(cluster_hash)
  end
  alias parse_cluster_compute_resource parse_compute_resource

  def parse_datacenter(object, props)
    persister.ems_folders.manager_uuids << object._ref
    return if props.nil?

    dc_hash = {
      :ems_ref      => object._ref,
      :uid_ems      => object._ref,
      :type         => "Datacenter",
      :ems_children => {},
    }

    if props.include?("name")
      dc_hash[:name] = URI.decode(props["name"])
    end

    parse_datacenter_children(dc_hash, props)

    persister.ems_folders.build(dc_hash)
  end

  def parse_datastore(object, props)
    persister.storages.manager_uuids << object._ref
    return if props.nil?

    storage_hash = {
      :ems_ref => object._ref,
    }

    parse_datastore_summary(storage_hash, props)
    parse_datastore_capability(storage_hash, props)

    storage = persister.storages.build(storage_hash)

    parse_datastore_host_mount(storage, object._ref, props)
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

    folder_hash = {
      :ems_ref      => object._ref,
      :uid_ems      => object._ref,
      :type         => "EmsFolder",
      :ems_children => {},
    }

    if props.include?("name")
      folder_hash[:name] = URI.decode(props["name"])
    end

    parse_folder_children(folder_hash, props)

    persister.ems_folders.build(folder_hash)
  end

  def parse_host_system(object, props)
    persister.hosts.manager_uuids << object._ref
    return if props.nil?

    host_hash = {
      :ems_ref => object._ref,
    }

    parse_host_system_config(host_hash, props)
    parse_host_system_product(host_hash, props)
    parse_host_system_network(host_hash, props)
    parse_host_system_runtime(host_hash, props)
    parse_host_system_system_info(host_hash, props)
    parse_host_system_children(host_hash, props)

    host_hash[:type] = if host_hash.include?(:vmm_product) && !%w(esx esxi).include?(host_hash[:vmm_product].to_s.downcase)
                         "ManageIQ::Providers::Vmware::InfraManager::Host"
                       else
                         "ManageIQ::Providers::Vmware::InfraManager::HostEsx"
                       end

    host = persister.hosts.build(host_hash)

    parse_host_system_operating_system(host, props)
    parse_host_system_system_services(host, props)
    parse_host_system_hardware(host, props)
    parse_host_system_switches(host, props)
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

    parse_resource_pool_memory_allocation(rp_hash, props)
    parse_resource_pool_cpu_allocation(rp_hash, props)
    parse_resource_pool_children(rp_hash, props)

    persister.resource_pools.build(rp_hash)
  end
  alias parse_virtual_app parse_resource_pool

  def parse_storage_pod(object, props)
    persister.ems_folders.manager_uuids << object._ref
    return if props.nil?

    pod_hash = {
      :ems_ref => object._ref,
      :uid_ems => object._ref,
      :type    => "StorageCluster",
    }

    if props.include?("summary.name")
      pod_hash[:name] = URI.decode(props["summary.name"])
    end

    persister.ems_folders.build(pod_hash)
  end

  def parse_virtual_machine(object, props)
    persister.vms_and_templates.manager_uuids << object._ref
    return if props.nil?

    vm_hash = {
      :ems_ref => object._ref,
      :vendor  => "vmware",
    }

    parse_virtual_machine_config(vm_hash, props)
    parse_virtual_machine_resource_config(vm_hash, props)
    parse_virtual_machine_summary(vm_hash, props)

    vm = persister.vms_and_templates.build(vm_hash)

    parse_virtual_machine_operating_system(vm, props)
    parse_virtual_machine_hardware(vm, props)
    parse_virtual_machine_custom_attributes(vm, props)
    parse_virtual_machine_snapshots(vm, props)
  end
end
