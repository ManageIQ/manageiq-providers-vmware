require 'VMwareWebService/VimTypes'

class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  include Vmdb::Logging

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

  def parse_ext_management_system(object, about)
    api_version   = about.apiVersion
    instance_uuid = about.instanceUuid

    persister.ext_management_system.build(
      :guid                => object.guid,
      :api_version         => api_version,
      :uid_ems             => instance_uuid,
      :last_inventory_date => Time.now.utc,
    )
  end

  def parse_compute_resource(object, kind, props)
    persister.clusters.targeted_scope << object._ref
    return if kind == "leave"

    # If a host isn't in a cluster VMware still puts it in a ComputeResource
    # parent object but this isn't shown on their UI
    hidden = object.class.wsdl_name == "ComputeResource"

    cluster_hash = {
      :ems_ref      => object._ref,
      :ems_ref_type => object.class.wsdl_name,
      :uid_ems      => object._ref,
      :name         => CGI.unescape(props[:name]),
      :parent       => lazy_find_managed_object(props[:parent]),
      :hidden       => hidden
    }

    parse_compute_resource_summary(cluster_hash, props)
    parse_compute_resource_das_config(cluster_hash, props)
    parse_compute_resource_drs_config(cluster_hash, props)

    persister.clusters.build(cluster_hash)
  end
  alias parse_cluster_compute_resource parse_compute_resource

  def parse_datacenter(object, kind, props)
    persister.ems_folders.targeted_scope << object._ref
    return if kind == "leave"

    dc_hash = {
      :ems_ref      => object._ref,
      :ems_ref_type => object.class.wsdl_name,
      :uid_ems      => object._ref,
      :type        => "ManageIQ::Providers::Vmware::InfraManager::Datacenter",
      :name         => CGI.unescape(props[:name]),
      :parent       => lazy_find_managed_object(props[:parent]),
    }

    persister.ems_folders.build(dc_hash)
  end

  def parse_datastore(object, kind, props)
    persister.storages.targeted_scope << object._ref
    return if kind == "leave"

    storage_hash = {
      :ems_ref      => object._ref,
      :ems_ref_type => object.class.wsdl_name,
      :parent       => lazy_find_managed_object(props[:parent])
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

    # Since Lans aren't a top-level collection but belong_to a switch we have
    # to send all dvportgroups for a dvswitch when doing a targeted refresh of the switch
    cache["DistributedVirtualPortgroup"].select do |_mor, dvpg_props|
      dvpg_props.fetch_path(:config, :distributedVirtualSwitch)&._ref == object._ref
    end.each do |mor, dvpg_props|
      portgroup = RbVmomi::VIM::DistributedVirtualPortgroup(object._connection, mor)
      parse_portgroups_internal(portgroup, dvpg_props)
    end
  end
  alias parse_vmware_distributed_virtual_switch parse_distributed_virtual_switch

  def parse_extension_manager(_object, kind, props)
    return if kind == "leave"

    props[:extensionList].each do |extension|
      persister.ems_extensions.build(
        :ems_ref => extension.key,
        :key     => extension.key,
        :company => extension.company,
        :label   => extension.description.label,
        :summary => extension.description.summary,
        :version => extension.version
      )
    end
  end

  def parse_folder(object, kind, props)
    persister.ems_folders.targeted_scope << object._ref
    return if kind == "leave"

    # "Hidden" folders are folders which exist in the VIM API but are not shown
    # on the vSphere UI.  These folders are the root folder above the datacenters
    # named "Datacenters", and the 4 child folders of each datacenter (datastore,
    # host, network, vm)
    hidden = props[:parent].nil? || props[:parent].kind_of?(RbVmomi::VIM::Datacenter)

    folder_hash = {
      :ems_ref      => object._ref,
      :ems_ref_type => object.class.wsdl_name,
      :type        => "ManageIQ::Providers::Vmware::InfraManager::Folder",
      :uid_ems      => object._ref,
      :name         => CGI.unescape(props[:name]),
      :parent       => lazy_find_managed_object(props[:parent]),
      :hidden       => hidden,
    }

    persister.ems_folders.build(folder_hash)
  end

  def parse_host_system(object, kind, props)
    persister.hosts.targeted_scope << object._ref
    return if kind == "leave"

    invalid, err = if props.fetch_path(:config).nil? || props.fetch_path(:summary, :config, :product).nil? || props.fetch_path(:summary).nil?
      [true, "Missing configuration for Host [#{object._ref}]"]
    elsif props.fetch_path(:config, :network, :dnsConfig, :hostName).blank?
      [true, "Missing hostname information for Host [#{object._ref}]"]
    else
      false
    end

    if invalid
      _log.warn("#{err} Skipping.")

      return
    end

    cluster = lazy_find_managed_object(props[:parent])
    host_hash = {
      :ems_ref      => object._ref,
      :ems_ref_type => object.class.wsdl_name,
      :ems_cluster  => cluster,
      :type         => "ManageIQ::Providers::Vmware::InfraManager::HostEsx",
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

    host_hash[:name] ||= props[:name]

    host = persister.hosts.build(host_hash)

    parse_host_system_operating_system(host, props)
    parse_host_system_system_services(host, props)
    hardware = parse_host_system_hardware(host, props)
    parse_host_system_host_networks(host, hardware, props)

    switches     = parse_host_system_switches(host, props)
    dvs_switches = parse_host_system_distributed_switches(host)

    parse_host_system_host_switches(host, switches + dvs_switches)
    parse_host_system_lans(host, switches, props)
  end

  def parse_license_manager(_object, kind, props)
    return if kind == "leave"

    props[:licenses].to_a.each do |license|
      persister.ems_licenses.build(
        :ems_ref         => license.licenseKey,
        :name            => license.name,
        :license_key     => license.licenseKey,
        :license_edition => license.editionKey,
        :total_licenses  => license.total,
        :used_licenses   => license.used
      )
    end
  end

  def parse_network(object, kind, props)
  end
  alias parse_opaque_network parse_network

  def parse_distributed_virtual_portgroup(_object, kind, props)
    return if kind == "leave"

    dvs = props.fetch_path(:config, :distributedVirtualSwitch)
    parse_distributed_virtual_switch(dvs, kind, cache.find(dvs))
  end

  def parse_portgroups_internal(object, props)
    return if props[:tag].detect { |tag| tag.key == "SYSTEM/DVS.UPLINKPG" }

    ref  = object._ref
    uid  = props.fetch_path(:config, :key)
    name = props.fetch_path(:summary, :name) || props.fetch_path(:config, :name)
    name = CGI.unescape(name) unless name.nil?

    default_port_config = props.fetch_path(:config, :defaultPortConfig)
    security_policy = default_port_config&.securityPolicy
    vlan_spec = default_port_config&.vlan
    tag = vlan_spec.vlanId if vlan_spec&.kind_of?(RbVmomi::VIM::VmwareDistributedVirtualSwitchVlanIdSpec)

    if security_policy
      allow_promiscuous = security_policy.allowPromiscuous&.value
      forged_transmits  = security_policy.forgedTransmits&.value
      mac_changes       = security_policy.macChanges&.value
    end

    dvs    = props.fetch_path(:config, :distributedVirtualSwitch)
    switch = persister.distributed_virtual_switches.lazy_find(dvs._ref) unless dvs.nil?

    lan_hash = {
      :ems_ref           => ref,
      :uid_ems           => uid,
      :name              => name,
      :switch            => switch,
      :allow_promiscuous => allow_promiscuous,
      :forged_transmits  => forged_transmits,
      :mac_changes       => mac_changes,
      :tag               => tag
    }

    persister.distributed_virtual_lans.find_or_build_by(lan_hash)
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

                   _("Default for %{parent_type} %{parent_name}") % {:parent_type => Dictionary.gettext(parent_model, :type => :model, :notfound => :titleize),
                                                                     :parent_name => cached_parent[:name]}
                 else
                   CGI.unescape(props[:name])
                 end

    rp_hash = {
      :ems_ref      => object._ref,
      :ems_ref_type => object.class.wsdl_name,
      :uid_ems      => object._ref,
      :name         => name,
      :vapp         => object.kind_of?(RbVmomi::VIM::VirtualApp),
      :parent       => lazy_find_managed_object(parent),
      :is_default   => is_default,
    }

    parse_resource_pool_memory_allocation(rp_hash, props)
    parse_resource_pool_cpu_allocation(rp_hash, props)

    persister.resource_pools.build(rp_hash)
  end
  alias parse_virtual_app parse_resource_pool

  def parse_pbm_profile(object, _kind, props)
    persister.storage_profiles.build(
      :ems_ref      => object.profileId.uniqueId,
      :name         => props[:name],
      :profile_type => props[:profileCategory]
    )
  end
  alias parse_pbm_capability_profile parse_pbm_profile

  def parse_pbm_placement_hub(persister_storage_profile, _object, _kind, props)
    persister_storage = persister.storages.lazy_find(props[:hubId])
    persister.storage_profile_storages.build(
      :storage_profile => persister_storage_profile,
      :storage         => persister_storage
    )
  end

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

    invalid, err = if props.fetch_path(:summary, :config).nil? || props.fetch_path(:config).nil?
      [true, "Missing configuration for VM [#{object._ref}]"]
    elsif props.fetch_path(:summary, :config, :uuid).blank? && props.fetch_path(:config, :uuid).blank?
      [true, "Missing UUID for VM [#{object._ref}]"]
    elsif props.fetch_path(:summary, :config, :vmPathName).blank?
      [true, "Missing pathname location for VM [#{object._ref}]"]
    else
      false
    end

    if invalid
      _log.warn("#{err} Skipping.")

      return
    end

    vm_hash = {
      :ems_ref       => object._ref,
      :ems_ref_type  => object.class.wsdl_name,
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

  def parse_content_library_item(library_item)
    props = {
      :ems_ref     => library_item.id,
      :name        => library_item.name,
      :description => library_item.description,
      :content     => library_item.type # TODO: currently 'ovf|iso|file'
    }
    persister.orchestration_templates.build(props)
  end

  def lazy_find_managed_object(managed_object)
    return if managed_object.nil?

    parent_collection = persister.vim_class_to_collection(managed_object)
    parent_collection.lazy_find(managed_object._ref)
  end
end
