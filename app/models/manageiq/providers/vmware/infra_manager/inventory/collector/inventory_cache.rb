class ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector
  module InventoryCache
    private

    def inventory_cache
      @inventory_cache ||=
        Hash.new do |h, k|
          h[k] = Hash.new { |h1, k1| h1[k1] = Hash.new }
        end
    end

    INVENTORY_CACHE_PROPERTIES = {
      "VirtualMachine" => %w(
        summary.config.template
        summary.config.name
        summary.config.uuid
        summary.config.vmPathName
      ),
      "Host"           => %w(
        config.network.dnsConfig.hostName
        summary.config.product.name
      ),
      "Datastore"      => %w(
        summary.name
        summary.url
      )
    }.freeze

    def update_inventory_cache(obj_type, obj_ref, props)
      properties_to_cache = INVENTORY_CACHE_PROPERTIES[obj_type]
      return if properties_to_cache.blank?

      cache = inventory_cache[obj_type][obj_ref]
      properties_to_cache.each do |prop_key|
        cache[prop_key] = props[prop_key]
      end
    end
  end
end
