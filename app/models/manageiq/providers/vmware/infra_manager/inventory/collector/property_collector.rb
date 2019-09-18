module ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector::PropertyCollector
  EmsRefreshPropMap = {
    :ManagedEntity               => [
      "name",
      "parent",
    ],
    :VirtualMachine              => [
      "availableField",
      "config.cpuAffinity.affinitySet",
      "config.cpuHotAddEnabled",
      "config.cpuHotRemoveEnabled",
      "config.defaultPowerOps.standbyAction",
      "config.hardware.device",
      "config.hardware.numCoresPerSocket",
      "config.hotPlugMemoryIncrementSize",
      "config.hotPlugMemoryLimit",
      "config.memoryHotAddEnabled",
      "config.version",
      "datastore",
      "guest.net",
      "resourceConfig.cpuAllocation.expandableReservation",
      "resourceConfig.cpuAllocation.limit",
      "resourceConfig.cpuAllocation.reservation",
      "resourceConfig.cpuAllocation.shares.level",
      "resourceConfig.cpuAllocation.shares.shares",
      "resourceConfig.memoryAllocation.expandableReservation",
      "resourceConfig.memoryAllocation.limit",
      "resourceConfig.memoryAllocation.reservation",
      "resourceConfig.memoryAllocation.shares.level",
      "resourceConfig.memoryAllocation.shares.shares",
      "resourcePool",
      "snapshot",
      "summary.vm",
      "summary.config.annotation",
      "summary.config.ftInfo.instanceUuids",
      "summary.config.guestFullName",
      "summary.config.guestId",
      "summary.config.memorySizeMB",
      "summary.config.name",
      "summary.config.numCpu",
      "summary.config.template",
      "summary.config.uuid",
      "summary.config.vmPathName",
      "summary.customValue",
      "summary.guest.hostName",
      "summary.guest.ipAddress",
      "summary.guest.toolsStatus",
      "summary.runtime.bootTime",
      "summary.runtime.connectionState",
      "summary.runtime.host",
      "summary.runtime.powerState",
      "summary.storage.unshared",
      "summary.storage.committed",
    ],
    :ComputeResource             => [
      "host",
      "resourcePool",
    ],
    :ClusterComputeResource      => [
      "configuration.dasConfig.admissionControlPolicy",
      "configuration.dasConfig.admissionControlEnabled",
      "configuration.dasConfig.enabled",
      "configuration.dasConfig.failoverLevel",
      "configuration.drsConfig.defaultVmBehavior",
      "configuration.drsConfig.enabled",
      "configuration.drsConfig.vmotionRate",
      "summary.effectiveCpu",
      "summary.effectiveMemory",
      "host",
      "resourcePool",
    ],
    :ResourcePool                => [
      "resourcePool",
      "summary.config.cpuAllocation.expandableReservation",
      "summary.config.cpuAllocation.limit",
      "summary.config.cpuAllocation.reservation",
      "summary.config.cpuAllocation.shares.level",
      "summary.config.cpuAllocation.shares.shares",
      "summary.config.memoryAllocation.expandableReservation",
      "summary.config.memoryAllocation.limit",
      "summary.config.memoryAllocation.reservation",
      "summary.config.memoryAllocation.shares.level",
      "summary.config.memoryAllocation.shares.shares",
      "vm",
    ],
    :Folder                      => [
    ],
    :Datacenter                  => [
      "datastoreFolder",
      "hostFolder",
      "networkFolder",
      "vmFolder",
    ],
    :HostSystem                  => [
      "config.adminDisabled",
      "config.consoleReservation.serviceConsoleReserved",
      "config.hyperThread.active",
      "config.network.consoleVnic",
      "config.network.dnsConfig.domainName",
      "config.network.dnsConfig.hostName",
      "config.network.ipRouteConfig.defaultGateway",
      "config.network.opaqueNetwork",
      "config.network.opaqueSwitch",
      "config.network.pnic",
      "config.network.portgroup",
      "config.network.vnic",
      "config.network.vswitch",
      "config.service.service",
      "datastore",
      "hardware.systemInfo.otherIdentifyingInfo",
      "summary.host",
      "summary.config.name",
      "summary.config.product.build",
      "summary.config.product.name",
      "summary.config.product.osType",
      "summary.config.product.vendor",
      "summary.config.product.version",
      "summary.config.vmotionEnabled",
      "summary.hardware.cpuMhz",
      "summary.hardware.cpuModel",
      "summary.hardware.memorySize",
      "summary.hardware.model",
      "summary.hardware.numCpuCores",
      "summary.hardware.numCpuPkgs",
      "summary.hardware.numNics",
      "summary.hardware.vendor",
      "summary.quickStats.overallCpuUsage",
      "summary.quickStats.overallMemoryUsage",
      "summary.runtime.connectionState",
      "summary.runtime.inMaintenanceMode",
    ],
    :Datastore                   => [
      "info",
      "host",
      "capability.directoryHierarchySupported",
      "capability.perFileThinProvisioningSupported",
      "capability.rawDiskMappingsSupported",
      "summary.accessible",
      "summary.capacity",
      "summary.datastore",
      "summary.freeSpace",
      "summary.maintenanceMode",
      "summary.multipleHostAccess",
      "summary.name",
      "summary.type",
      "summary.uncommitted",
      "summary.url",
    ],
    :StoragePod                  => [
      "summary.capacity",
      "summary.freeSpace",
      "summary.name",
    ],
    :DistributedVirtualPortgroup => [
      "summary.name",
      "config.key",
      "config.defaultPortConfig",
      "config.distributedVirtualSwitch",
      "config.name",
      "host",
      "tag",
    ],
    :DistributedVirtualSwitch    => [
      "config.uplinkPortgroup",
      "config.defaultPortConfig",
      "config.numPorts",
      "summary.name",
      "summary.uuid",
      "summary.host",
      "summary.hostMember",
    ],
    :LicenseManager              => [
      "licenses"
    ],
    :ExtensionManager            => [
      "extensionList"
    ]
  }.freeze

  def create_property_filter(vim)
    root_folder = vim.serviceContent.rootFolder

    spec = RbVmomi::VIM.PropertyFilterSpec(
      :objectSet => [
        extension_manager_traversal_spec(vim.serviceContent.extensionManager),
        folder_traversal_spec(root_folder),
        license_manager_traversal_spec(vim.serviceContent.licenseManager),
      ],
      :propSet   => prop_set
    )

    vim.propertyCollector.CreateFilter(:spec => spec, :partialUpdates => true)
  end

  def destroy_property_filter(property_filter)
    return if property_filter.nil?

    property_filter.DestroyPropertyFilter
  end

  def extension_manager_traversal_spec(extension_manager)
    RbVmomi::VIM.ObjectSpec(:obj => extension_manager)
  end

  def folder_traversal_spec(root)
    traversal_spec = [
      folder_to_child_entity,
      datacenter_to_datastore_folder,
      datacenter_to_host_folder,
      datacenter_to_network_folder,
      datacenter_to_vm_folder,
      compute_resource_to_host,
      compute_resource_to_resource_pool,
      resource_pool_to_resource_pool,
      resource_pool_to_vm,
    ]

    RbVmomi::VIM.ObjectSpec(:obj => root, :selectSet => traversal_spec)
  end

  def license_manager_traversal_spec(license_manager)
    RbVmomi::VIM.ObjectSpec(:obj => license_manager)
  end

  def prop_set
    EmsRefreshPropMap.collect do |type, props|
      RbVmomi::VIM.PropertySpec(
        :type    => type,
        :all     => props.nil?,
        :pathSet => props
      )
    end
  end

  def folder_to_child_entity
    RbVmomi::VIM.TraversalSpec(
      :name => 'tsFolder', :type => 'Folder', :path => 'childEntity',
      :selectSet => [
        RbVmomi::VIM.SelectionSpec(:name => 'tsFolder'),
        RbVmomi::VIM.SelectionSpec(:name => 'tsDcToDsFolder'),
        RbVmomi::VIM.SelectionSpec(:name => 'tsDcToHostFolder'),
        RbVmomi::VIM.SelectionSpec(:name => 'tsDcToNetworkFolder'),
        RbVmomi::VIM.SelectionSpec(:name => 'tsDcToVmFolder'),
        RbVmomi::VIM.SelectionSpec(:name => 'tsCrToHost'),
        RbVmomi::VIM.SelectionSpec(:name => 'tsCrToRp'),
        RbVmomi::VIM.SelectionSpec(:name => 'tsRpToRp'),
        RbVmomi::VIM.SelectionSpec(:name => 'tsRpToVm')
      ]
    )
  end

  def datacenter_to_datastore_folder
    RbVmomi::VIM.TraversalSpec(
      :name => 'tsDcToDsFolder', :type => 'Datacenter', :path => 'datastoreFolder',
      :selectSet => [RbVmomi::VIM.SelectionSpec(:name => 'tsFolder')]
    )
  end

  def datacenter_to_host_folder
    RbVmomi::VIM.TraversalSpec(
      :name => 'tsDcToHostFolder', :type => 'Datacenter', :path => 'hostFolder',
      :selectSet => [RbVmomi::VIM.SelectionSpec(:name => 'tsFolder')]
    )
  end

  def datacenter_to_network_folder
    RbVmomi::VIM.TraversalSpec(
      :name => 'tsDcToNetworkFolder', :type => 'Datacenter', :path => 'networkFolder',
      :selectSet => [RbVmomi::VIM.SelectionSpec(:name => 'tsFolder')]
    )
  end

  def datacenter_to_vm_folder
    RbVmomi::VIM.TraversalSpec(
      :name => 'tsDcToVmFolder', :type => 'Datacenter', :path => 'vmFolder',
      :selectSet => [RbVmomi::VIM.SelectionSpec(:name => 'tsFolder')]
    )
  end

  def compute_resource_to_host
    RbVmomi::VIM.TraversalSpec(
      :name => 'tsCrToHost', :type => 'ComputeResource', :path => 'host',
    )
  end

  def compute_resource_to_resource_pool
    RbVmomi::VIM.TraversalSpec(
      :name => 'tsCrToRp', :type => 'ComputeResource', :path => 'resourcePool',
      :selectSet => [RbVmomi::VIM.SelectionSpec(:name => 'tsRpToRp')]
    )
  end

  def resource_pool_to_resource_pool
    RbVmomi::VIM.TraversalSpec(
      :name => 'tsRpToRp', :type => 'ResourcePool', :path => 'resourcePool',
      :selectSet => [RbVmomi::VIM.SelectionSpec(:name => 'tsRpToRp')]
    )
  end

  def resource_pool_to_vm
    RbVmomi::VIM.TraversalSpec(
      :name => 'tsRpToVm', :type => 'ResourcePool', :path => 'vm',
    )
  end

  def process_change_set(change_set, props = {})
    change_set.each do |prop_change|
      process_prop_change(props, prop_change)
    end

    props
  end

  def process_prop_change(prop_hash, prop_change)
    h, prop_str = hash_target(prop_hash, prop_change.name)
    tag, key    = tag_and_key(prop_str)

    case prop_change.op
    when "add"
      h[tag] ||= []
      h[tag] << prop_change.val
    when "remove", "indirectRemove"
      if key
        a, i = get_array_entry(h[tag], key)
        a.delete_at(i)
      else
        h.delete(tag)
      end
    when "assign"
      if key
        # TODO
        raise "Array properties aren't supported yet"
      else
        h[tag] = prop_change.val
      end
    end
  end

  def hash_target(base_hash, key_string)
    h = base_hash
    prop_keys = split_prop_path(key_string)

    prop_keys[0...-1].each do |key|
      key, array_key = tag_and_key(key)
      if array_key
        array, idx = get_array_entry(h[key], array_key)
        raise "hashTarget: Could not traverse tree through array element #{k}[#{array_key}] in #{key_string}" unless array
        h = array[idx]
      else
        h[key] ||= {}
        h = h[key]
      end
    end

    return h, prop_keys[-1]
  end

  def split_prop_path(prop_path)
    path_array = []
    in_key     = false
    pc         = ""

    prop_path.split(//).each do |c|
      case c
      when "."
        unless in_key
          path_array << pc
          pc = ""
          next
        end
      when "["
        in_key = true
      when "]"
        in_key = false
      end
      pc << c
    end

    path_array << pc unless pc.empty?
    path_array
  end

  def tag_and_key(prop_str)
    return prop_str.to_sym, nil unless prop_str.include?("[")

    if prop_str =~ /([^\[]+)\[([^\]]+)\]/
      tag, key = $1, $2
    else
      raise "tagAndKey: malformed property string #{prop_str}"
    end
    key = key[1...-1] if key[0, 1] == '"' && key[-1, 1] == '"'
    return tag.to_sym, key
  end

  def get_array_entry(array, key)
    return nil, nil unless array.kind_of?(Array)

    array.each_index do |n|
      array_entry = array[n]

      entry_key = array_entry.respond_to?("key") ? array_entry.key : array_entry
      case entry_key
      when RbVmomi::BasicTypes::ManagedObject
        return array, n if entry_key._ref == key
      else
        return array, n if entry_key.to_s == key
      end
    end
  end
end
