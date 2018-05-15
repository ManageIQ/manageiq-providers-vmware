class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  include_concern :ComputeResource
  include_concern :Datastore
  include_concern :DistributedVirtualSwitch
  include_concern :HostSystem
  include_concern :ResourcePool
  include_concern :VirtualMachine

  attr_reader :cache, :persister
  private     :cache, :persister

  def initialize(cache, persister)
    @cache     = cache
    @persister = persister
  end

  def parse(object, kind, props)
    object_type = object.class.wsdl_name
    parse_method = "parse_#{object_type.underscore}"

    raise "Missing parser for #{object_type}" unless respond_to?(parse_method)

    send(parse_method, object, kind, props)
  end

  def parse_compute_resource(object, kind, props)
    persister.ems_clusters.targeted_scope << object._ref
    return if kind == "leave"

    cluster_hash = {
      :ems_ref => object._ref,
      :uid_ems => object._ref,
      :name    => CGI.unescape(props[:name]),
      :parent  => lazy_find_managed_object(props[:parent]),
    }

    parse_compute_resource_summary(cluster_hash, props)
    parse_compute_resource_das_config(cluster_hash, props)
    parse_compute_resource_drs_config(cluster_hash, props)

    persister.ems_clusters.build(cluster_hash)
  end
  alias parse_cluster_compute_resource parse_compute_resource

  def parse_datacenter(object, kind, props)
    persister.ems_folders.targeted_scope << object._ref
    return if kind == "leave"

    dc_hash = {
      :ems_ref => object._ref,
      :uid_ems => object._ref,
      :type    => "Datacenter",
      :name    => CGI.unescape(props[:name]),
      :parent  => lazy_find_managed_object(props[:parent]),
    }

    persister.ems_folders.build(dc_hash)
  end

  def parse_datastore(object, kind, props)
    persister.storages.targeted_scope << parse_datastore_location(props)
    return if kind == "leave"

    storage_hash = {
      :ems_ref => object._ref,
      :parent  => lazy_find_managed_object(props[:parent]),
    }

    parse_datastore_summary(storage_hash, props)
    parse_datastore_capability(storage_hash, props)

    storage = persister.storages.build(storage_hash)

    parse_datastore_host_mount(storage, object._ref, props)
  end

  def parse_distributed_virtual_switch(object, kind, props)
    persister.switches.targeted_scope << object._ref
    return if kind == "leave"

    type = ManageIQ::Providers::Vmware::InfraManager::DistributedVirtualSwitch.name

    switch_hash = {
      :uid_ems => object._ref,
      :type    => type,
      :shared  => true,
    }

    parse_dvs_config(switch_hash, props[:config])
    parse_dvs_summary(switch_hash, props[:summary])

    persister_switch = persister.switches.build(switch_hash)

    parser_dvs_hosts(persister_switch, props)
  end
  alias parse_vmware_distributed_virtual_switch parse_distributed_virtual_switch

  def parse_folder(object, kind, props)
    persister.ems_folders.targeted_scope << object._ref
    return if kind == "leave"

    folder_hash = {
      :ems_ref => object._ref,
      :uid_ems => object._ref,
      :type    => "EmsFolder",
      :name    => CGI.unescape(props[:name]),
      :parent  => lazy_find_managed_object(props[:parent]),
    }

    persister.ems_folders.build(folder_hash)
  end

  def parse_host_system(object, kind, props)
    persister.hosts.targeted_scope << object._ref
    return if kind == "leave"

    cluster = lazy_find_managed_object(props[:parent])
    host_hash = {
      :ems_cluster => cluster,
      :ems_ref     => object._ref,
      :parent      => cluster,
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

    switches = parse_host_system_switches(host, props)
    parse_host_system_host_switches(host, switches)
    parse_host_system_lans(switches, props)
  end

  def parse_network(object, kind, props)
  end

  def parse_distributed_virtual_portgroup(object, kind, props)
    persister.lans.targeted_scope << object._ref
    return if kind == "leave"

    name = props.fetch_path(:summary, :name) || props.fetch_path(:config, :name)
    name = CGI.unescape(name) unless name.nil?

    default_port_config = props.fetch_path(:config, :defaultPortConfig)
    security_policy = default_port_config&.securityPolicy

    if security_policy
      allow_promiscuous = security_policy.allowPromiscuous&.value
      forged_transmits  = security_policy.forgedTransmits&.value
      mac_changes       = security_policy.macChanges&.value
    end

    dvs    = props.fetch_path(:config, :distributedVirtualSwitch)
    switch = persister.switches.lazy_find(dvs._ref) unless dvs.nil?

    lan_hash = {
      :uid_ems           => object._ref,
      :name              => name,
      :switch            => switch,
      :allow_promiscuous => allow_promiscuous,
      :forged_transmits  => forged_transmits,
      :mac_changes       => mac_changes,
    }

    persister.lans.build(lan_hash)
  end

  def parse_resource_pool(object, kind, props)
    persister.resource_pools.targeted_scope << object._ref
    return if kind == "leave"

    rp_hash = {
      :ems_ref => object._ref,
      :uid_ems => object._ref,
      :name    => CGI.unescape(props[:name]),
      :vapp    => object.kind_of?(RbVmomi::VIM::VirtualApp),
      :parent  => lazy_find_managed_object(props[:parent]),
    }

    parse_resource_pool_memory_allocation(rp_hash, props)
    parse_resource_pool_cpu_allocation(rp_hash, props)

    persister.resource_pools.build(rp_hash)
  end
  alias parse_virtual_app parse_resource_pool

  def parse_storage_pod(object, kind, props)
    persister.ems_folders.targeted_scope << object._ref
    return if kind == "leave"

    name = props.fetch_path(:summary, :name)

    pod_hash = {
      :ems_ref => object._ref,
      :uid_ems => object._ref,
      :type    => "StorageCluster",
      :name    => CGI.unescape(name),
      :parent  => lazy_find_managed_object(props[:parent]),
    }

    persister.ems_folders.build(pod_hash)
  end

  def parse_virtual_machine(object, kind, props)
    persister.vms_and_templates.targeted_scope << object._ref
    return if kind == "leave"

    vm_hash = {
      :ems_ref       => object._ref,
      :vendor        => "vmware",
      :parent        => lazy_find_managed_object(props[:parent]),
      :resource_pool => lazy_find_managed_object(props[:resourcePool]),
    }

    parse_virtual_machine_config(vm_hash, props)
    parse_virtual_machine_resource_config(vm_hash, props)
    parse_virtual_machine_summary(vm_hash, props)
    parse_virtual_machine_storage(vm_hash, props)

    vm = persister.vms_and_templates.build(vm_hash)

    parse_virtual_machine_operating_system(vm, props)
    parse_virtual_machine_hardware(vm, props)
    parse_virtual_machine_custom_attributes(vm, props)
    parse_virtual_machine_snapshots(vm, props)
  end

  def lazy_find_managed_object(managed_object)
    return if managed_object.nil?

    parent_collection = persister.vim_class_to_collection(managed_object)
    parent_collection.lazy_find(managed_object._ref)
  end
end
