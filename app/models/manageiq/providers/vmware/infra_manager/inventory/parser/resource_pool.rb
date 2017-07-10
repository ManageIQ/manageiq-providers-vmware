class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  module ResourcePool
    def parse_resource_pool_memory_allocation(cluster_hash, props)
      if props.include?("summary.config.memoryAllocation.reservation")
        cluster_hash[:memory_reserve] = props["summary.config.memoryAllocation.reservation"]
      end
      if props.include?("summary.config.memoryAllocation.expandableReservation")
        expandable_reservation = props["summary.config.memoryAllocation.expandableReservation"]
        cluster_hash[:memory_reserve_expand] = expandable_reservation.to_s.downcase == "true"
      end
      if props.include?("summary.config.memoryAllocation.limit")
        cluster_hash[:memory_limit] = props["summary.config.memoryAllocation.limit"]
      end
      if props.include?("summary.config.memoryAllocation.shares.shares")
        cluster_hash[:memory_shares] = props["summary.config.memoryAllocation.shares.shares"]
      end
      if props.include?("summary.config.memoryAllocation.shares.level")
        cluster_hash[:memory_shares_level] = props["summary.config.memoryAllocation.shares.level"]
      end
    end

    def parse_resource_pool_cpu_allocation(cluster_hash, props)
      if props.include?("summary.config.cpuAllocation.reservation")
        cluster_hash[:cpu_reserve] = props["summary.config.cpuAllocation.reservation"]
      end
      if props.include?("summary.config.cpuAllocation.expandableReservation")
        expandable_reservation = props["summary.config.cpuAllocation.expandableReservation"]
        cluster_hash[:cpu_reserve_expand] = expandable_reservation.to_s.downcase == "true"
      end
      if props.include?("summary.config.cpuAllocation.limit")
        cluster_hash[:cpu_limit] = props["summary.config.cpuAllocation.limit"]
      end
      if props.include?("summary.config.cpuAllocation.shares.shares")
        cluster_hash[:cpu_shares] = props["summary.config.cpuAllocation.shares.shares"]
      end
      if props.include?("summary.config.cpuAllocation.limit.limit")
        cluster_hash[:cpu_shares_level] = props["summary.config.cpuAllocation.limit.limit"]
      end
    end

    def parse_resource_pool_children(cluster_hash, props)
      cluster_hash[:ems_children] = {
        :rp => [],
        :vm => [],
      }

      if props.include?("resourcePool")
        props["resourcePool"].to_a.each do |rp|
          cluster_hash[:ems_children][:rp] << persister.resource_pools.lazy_find(rp._ref)
        end
      end
      if props.include?("vm")
        props["vm"].to_a.each do |vm|
          cluster_hash[:ems_children][:vm] << persister.resource_pools.lazy_find(vm._ref)
        end
      end
    end
  end
end
