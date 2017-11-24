module ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector::PropertyCollector
  EmsRefreshPropMap = {
    :ManagedEntity  => [
      "name",
      "parent",
    ],
    :VirtualMachine => [
      "summary.config.template",
      "summary.config.uuid",
      "summary.runtime.powerState",
    ],
  }.freeze

  def create_property_filter(vim)
    root_folder = vim.serviceContent.rootFolder

    spec = RbVmomi::VIM.PropertyFilterSpec(
      :objectSet => [full_traversal_object_spec(root_folder)],
      :propSet   => prop_set
    )

    vim.propertyCollector.CreateFilter(:spec => spec, :partialUpdates => true)
  end

  def full_traversal_object_spec(root)
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
end
