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

  delegate :[], :keys, :to => :data

  private

  attr_reader :data

  def process_change_set(props, change_set)
    change_set.each do |prop_change|
      process_prop_change(props, prop_change)
    end
  end

  def process_prop_change(prop_hash, prop_change)
  end
end
