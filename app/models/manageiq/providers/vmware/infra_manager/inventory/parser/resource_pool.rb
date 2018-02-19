class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  module ResourcePool
    def parse_resource_pool_memory_allocation(cluster_hash, props)
      memory_allocation = props.fetch_path(:summary, :config, :memoryAllocation)
      return if memory_allocation.nil?

      cluster_hash[:memory_reserve] = memory_allocation[:reservation]
      cluster_hash[:memory_reserve_expand] = memory_allocation[:expandableReservation].to_s.downcase == "true"
      cluster_hash[:memory_limit] = memory_allocation[:limit]
      cluster_hash[:memory_shares] = memory_allocation.fetch_path(:shares, :shares)
      cluster_hash[:memory_shares_level] = memory_allocation.fetch_path(:shares, :level)
    end

    def parse_resource_pool_cpu_allocation(cluster_hash, props)
      cpu_allocation = props.fetch_path(:summary, :config, :cpuAllocation)
      return if cpu_allocation.nil?

      cluster_hash[:cpu_reserve] = cpu_allocation[:reservation]
      cluster_hash[:cpu_reserve_expand] = cpu_allocation[:expandableReservation].to_s.downcase == "true"
      cluster_hash[:cpu_limit] = cpu_allocation[:limit]
      cluster_hash[:cpu_shares] = cpu_allocation.fetch_path(:shares, :shares)
      cluster_hash[:cpu_shares_level] = cpu_allocation.fetch_path(:limit, :limit)
    end

    def parse_resource_pool_children(cluster_hash, props)
      cluster_hash[:ems_children] = {
        :rp => [],
        :vm => [],
      }

      props[:resourcePool].to_a.each do |rp|
        cluster_hash[:ems_children][:rp] << persister.resource_pools.lazy_find(rp._ref)
      end

      props[:vm].to_a.each do |vm|
        cluster_hash[:ems_children][:vm] << persister.resource_pools.lazy_find(vm._ref)
      end
    end
  end
end
