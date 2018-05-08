class ManageIQ::Providers::Vmware::InfraManager::Inventory::Cache
  def initialize
    @data = Hash.new { |h, k| h[k] = {} }
  end

  def insert(obj, change_set = [])
    props = data[obj.class.wsdl_name][obj._ref] = {}
    process_change_set(props, change_set)
    props
  end

  def delete(obj)
    data[obj.class.wsdl_name].delete(obj._ref)
  end

  def update(obj, change_set)
    props = data[obj.class.wsdl_name][obj._ref]
    process_change_set(props, change_set) unless props.nil?
    props
  end

  def find(obj)
    data[obj.class.wsdl_name][obj._ref] unless obj.nil?
  end

  delegate :[], :keys, :to => :data

  private

  attr_reader :data

  def process_change_set(props, change_set)
    change_set.each do |prop_change|
      process_prop_change(props, prop_change)
    end
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
