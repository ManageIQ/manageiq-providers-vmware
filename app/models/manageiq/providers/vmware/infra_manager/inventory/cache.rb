class ManageIQ::Providers::Vmware::InfraManager::Inventory::Cache
  attr_reader :data
  private     :data

  delegate :[], :keys, :to => :data

  def initialize
    @data = Hash.new { |h, k| h[k] = {} }
  end

  def insert(obj, props = {})
    data[obj.class.wsdl_name][obj._ref] = props
  end

  def delete(obj)
    data[obj.class.wsdl_name].delete(obj._ref)
  end

  def update(obj)
    props = data[obj.class.wsdl_name][obj._ref]
    yield props
    props
  end

  def find(obj)
    data[obj.class.wsdl_name][obj._ref] unless obj.nil?
  end
end
