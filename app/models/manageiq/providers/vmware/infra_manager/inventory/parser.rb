require 'VMwareWebService/VimTypes'

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
      :ems_ref     => object._ref,
      :ems_ref_obj => managed_object_to_vim_string(object),
      :uid_ems     => object._ref,
      :name        => CGI.unescape(props[:name]),
      :parent      => lazy_find_managed_object(props[:parent]),
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
      :ems_ref     => object._ref,
      :ems_ref_obj => managed_object_to_vim_string(object),
      :uid_ems     => object._ref,
      :type        => "Datacenter",
      :name        => CGI.unescape(props[:name]),
      :parent      => lazy_find_managed_object(props[:parent]),
    }

    persister.ems_folders.build(dc_hash)
  end

  def parse_datastore(object, kind, props)
    persister.storages.targeted_scope << parse_datastore_location(props)
    return if kind == "leave"

    storage_hash = {
      :ems_ref     => object._ref,
      :ems_ref_obj => managed_object_to_vim_string(object),
      :parent      => lazy_find_managed_object(props[:parent]),
    }

    parse_datastore_summary(storage_hash, props)
    parse_datastore_capability(storage_hash, props)

    storage = persister.storages.build(storage_hash)

    parse_datastore_host_mount(storage, object._ref, props)
  end

  def parse_distributed_virtual_switch(object, kind, props)
    persister.distributed_virtual_switches.targeted_scope << object._ref
    return if kind == "leave"

    type = ManageIQ::Providers::Vmware::InfraManager::DistributedVirtualSwitch.name

    switch_hash = {
      :uid_ems => object._ref,
      :type    => type,
      :shared  => true,
    }

    parse_dvs_config(switch_hash, props[:config])
    parse_dvs_summary(switch_hash, props[:summary])

    persister_switch = persister.distributed_virtual_switches.build(switch_hash)

    parser_dvs_hosts(persister_switch, props)
  end
  alias parse_vmware_distributed_virtual_switch parse_distributed_virtual_switch

  def parse_folder(object, kind, props)
    persister.ems_folders.targeted_scope << object._ref
    return if kind == "leave"

    # "Hidden" folders are folders which exist in the VIM API but are not shown
    # on the vSphere UI.  These folders are the root folder above the datacenters
    # named "Datacenters", and the 4 child folders of each datacenter (datastore,
    # host, network, vm)
    hidden = props[:parent].nil? || props[:parent].kind_of?(RbVmomi::VIM::Datacenter)

    folder_hash = {
      :ems_ref     => object._ref,
      :ems_ref_obj => managed_object_to_vim_string(object),
      :uid_ems     => object._ref,
      :name        => CGI.unescape(props[:name]),
      :parent      => lazy_find_managed_object(props[:parent]),
      :hidden      => hidden,
    }

    persister.ems_folders.build(folder_hash)
  end

  def parse_host_system(object, kind, props)
    persister.hosts.targeted_scope << object._ref
    return if kind == "leave"

    cluster = lazy_find_managed_object(props[:parent])
    host_hash = {
      :ems_ref     => object._ref,
      :ems_ref_obj => managed_object_to_vim_string(object),
      :ems_cluster => cluster,
      :parent      => cluster,
    }

    parse_host_system_summary(host_hash, props)
    parse_host_system_config(host_hash, props)
    parse_host_system_product(host_hash, props)
    parse_host_system_network(host_hash, props)
    parse_host_system_runtime(host_hash, props)
    parse_host_system_system_info(host_hash, props)

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
    return if kind == "leave"
    return if props[:tag].detect { |tag| tag.key == "SYSTEM/DVS.UPLINKPG" }

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
    switch = persister.distributed_virtual_switches.lazy_find(dvs._ref) unless dvs.nil?

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

    parent = props[:parent]

    # Default resource pools are ones whose parent is a Cluster or a Host,
    # resource pools which show up on the vSphere UI all have resource pools
    # as parents.
    is_default = parent && !parent.kind_of?(RbVmomi::VIM::ResourcePool)
    name       = if is_default
                   cached_parent = cache.find(parent) if parent
                   parent_model = persister.vim_class_to_collection(parent).base_class_name

                   "Default for #{Dictionary.gettext(parent_model, :type => :model, :notfound => :titleize)} #{cached_parent[:name]}"
                 else
                   CGI.unescape(props[:name])
                 end

    rp_hash = {
      :ems_ref     => object._ref,
      :ems_ref_obj => managed_object_to_vim_string(object),
      :uid_ems     => object._ref,
      :name        => name,
      :vapp        => object.kind_of?(RbVmomi::VIM::VirtualApp),
      :parent      => lazy_find_managed_object(parent),
      :is_default  => is_default,
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
      :ems_ref_obj   => managed_object_to_vim_string(object),
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

  def managed_object_to_vim_string(object)
    ref = object._ref
    vim_type = object.class.wsdl_name.to_sym
    xsi_type = :ManagedObjectReference

    VimString.new(ref, vim_type, xsi_type)
  end
end
