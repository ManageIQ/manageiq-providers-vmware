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
        RbVmomi::VIM.ObjectSpec(:obj => vim.serviceContent.customizationSpecManager),
        RbVmomi::VIM.ObjectSpec(:obj => vim.serviceContent.extensionManager),
        RbVmomi::VIM.ObjectSpec(:obj => vim.serviceContent.rootFolder, :selectSet => root_folder_select_set),
        RbVmomi::VIM.ObjectSpec(:obj => vim.serviceContent.licenseManager),
      ],
      :propSet   => ems_inventory_prop_set(vim.rev)
    )
  end

  def ems_inventory_prop_set(api_version)
    property_set_from_file("ems_inventory", api_version)
  end

  def property_set_from_file(file_name, api_version)
    engine_root = ManageIQ::Providers::Vmware::Engine.root
    hash = YAML.load_file(engine_root.join("config", "property_specs", "#{file_name}.yml"))

    major_minor_version = api_version.split(".").take(2).join(".")

    prop_set = hash["base"]
    prop_set = merge_prop_set!(prop_set, hash[major_minor_version]) if hash.key?(major_minor_version)

    prop_set.collect do |type, props|
      RbVmomi::VIM.PropertySpec(
        :type    => type,
        :all     => props.nil?,
        :pathSet => props
      )
    end
  end

  def merge_prop_set!(base, extra)
    base.deep_merge!(extra) { |_k, v1, v2| v1 + v2 }
  end

  def root_folder_select_set
    traversal_spec_from_file("root_folder")
  end

  def traversal_spec_from_file(file_name)
    engine_root = ManageIQ::Providers::Vmware::Engine.root
    hash = YAML.load_file(engine_root.join("config", "traversal_specs", "#{file_name}.yml"))

    hash.map do |traversal_spec|
      RbVmomi::VIM.TraversalSpec(
        :name      => traversal_spec["name"],
        :type      => traversal_spec["type"],
        :path      => traversal_spec["path"],
        :selectSet => traversal_spec["selectSet"]&.map do |name|
          RbVmomi::VIM.SelectionSpec(:name => name)
        end
      )
    end
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
        a, i = get_array_entry(h[tag], key)
        a[i] = prop_change.val
      else
        h[tag] = prop_change.val
      end
    end
  rescue => err
    _log.warn("Failed to process property change #{prop_change.name}: #{err}")
  end

  def hash_target(base_hash, key_string)
    h = base_hash
    prop_keys = split_prop_path(key_string)

    prop_keys[0...-1].each do |key|
      key, array_key = tag_and_key(key)
      if array_key
        array, idx = get_array_entry(h[key], array_key)
        raise "Could not traverse tree through array element #{key}[#{array_key}] in #{key_string}" unless array

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

    return nil, nil
  end
end
