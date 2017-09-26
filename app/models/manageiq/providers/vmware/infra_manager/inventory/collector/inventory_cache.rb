class ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector
  module InventoryCache
    private

    def inventory_cache
      @inventory_cache ||=
        Hash.new do |h, k|
          h[k] = Hash.new { |h1, k1| h1[k1] = Hash.new }
        end
    end

    def update_inventory_cache(obj_type, obj_ref, props)
      inventory_cache[obj_type][obj_ref] = props
    end
  end
end
