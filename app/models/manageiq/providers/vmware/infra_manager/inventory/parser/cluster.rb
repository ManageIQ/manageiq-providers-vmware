class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  module Cluster
    def parse_cluster_summary(cluster_hash, props)
      if props.include?("summary.effectiveCpu")
        effective_cpu = props["summary.effectiveCpu"]
        cluster_hash[:effective_cpu] = effective_cpu.blank? ? nil : effective_cpu.to_i
      end
      if props.include?("summary.effectiveMemory")
        effective_memory = props["summary.effectiveMemory"]
        cluster_hash[:effective_memory] = effective_memory.blank? ? nil : effective_memory.to_i.megabytes
      end
    end

    def parse_cluster_das_config(cluster_hash, props)
      if props.include?("configuration.dasConfig.enabled")
        enabled = props["configuration.dasConfig.enabled"]
        cluster_hash[:ha_enabled] = enabled.to_s.downcase == "true"
      end
      if props.include?("configuration.dasConfig.admissionControlEnabled")
        admission_control_enabled = props["configuration.dasConfig.admissionControlEnabled"]
        cluster_hash[:ha_admit_control] = admission_control_enabled.to_s.downcase == "true"
      end
      if props.include?("configuration.dasConfig.failoverLevel")
        failover_level = props["configuration.dasConfig.failoverLevel"]
        cluster_hash[:ha_max_failures] = failover_level
      end
    end

    def parse_cluster_drs_config(cluster_hash, props)
      if props.include?("configuration.drsConfig.enabled")
        enabled = props["configuration.drsConfig.enabled"]
        cluster_hash[:drs_enabled] = enabled.to_s.downcase == "true"
      end
      if props.include?("configuration.drsConfig.defaultVmBehavior")
        cluster_hash[:drs_automation_level] = props["configuration.drsConfig.defaultVmBehavior"]
      end
      if props.include?("configuration.drsConfig.vmotionRate")
        cluster_hash[:drs_migration_threshold] = props["configuration.drsConfig.vmotionRate"]
      end
    end

    def parse_cluster_children(cluster_hash, props)
      cluster_hash[:ems_children] = {:rp => []}

      if props.include?("resourcePool")
        rp = props["resourcePool"]
        unless rp.nil?
          cluster_hash[:ems_children][:rp] << persister.resource_pools.lazy_find(rp._ref)
        end
      end
    end
  end
end
