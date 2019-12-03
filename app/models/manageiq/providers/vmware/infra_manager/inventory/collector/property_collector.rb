module ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector::PropertyCollector
  def create_property_filter(vim, spec)
    vim.propertyCollector.CreateFilter(:spec => spec, :partialUpdates => true)
  end

  def destroy_property_filter(property_filter)
    return if property_filter.nil?

    property_filter.DestroyPropertyFilter
  end

  def ems_inventory_filter_spec(vim)
    RbVmomi::VIM.PropertyFilterSpec(
      :objectSet => [
        extension_manager_traversal_spec(vim.serviceContent.extensionManager),
        root_folder_traversal_spec(vim.serviceContent.rootFolder),
        license_manager_traversal_spec(vim.serviceContent.licenseManager),
      ],
      :propSet   => ems_inventory_prop_set
    )
  end

  def extension_manager_traversal_spec(extension_manager)
    RbVmomi::VIM.ObjectSpec(:obj => extension_manager)
  end

  def ems_inventory_prop_set
    property_set_from_hash(
      YAML.load_file(
        ManageIQ::Providers::Vmware::Engine.root.join(
          "db/fixtures/property_specs/ems_inventory.yml"
        )
      )
    )
  end

  def property_set_from_hash(hash)
    hash.collect do |type, props|
      RbVmomi::VIM.PropertySpec(
        :type    => type,
        :all     => props.nil?,
        :pathSet => props
      )
    end
  end

  def root_folder_traversal_spec(root)
    RbVmomi::VIM.ObjectSpec(:obj => root, :selectSet => root_folder_select_set)
  end

  def root_folder_select_set
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
  end

  def license_manager_traversal_spec(license_manager)
    RbVmomi::VIM.ObjectSpec(:obj => license_manager)
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
