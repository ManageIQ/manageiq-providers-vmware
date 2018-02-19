class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  module ComputeResource
    def parse_compute_resource_summary(cluster_hash, props)
      summary = props[:summary]
      return if summary.nil?

      effective_cpu = summary[:effectiveCpu]
      cluster_hash[:effective_cpu] = effective_cpu.blank? ? nil : effective_cpu.to_i

      effective_memory = summary[:effectiveMemory]
      cluster_hash[:effective_memory] = effective_memory.blank? ? nil : effective_memory.to_i.megabytes
    end

    def parse_compute_resource_das_config(cluster_hash, props)
      das_config = props.fetch_path(:configuration, :dasConfig)
      return if das_config.nil?

      cluster_hash[:ha_enabled]       = das_config[:enabled].to_s.downcase == "true"
      cluster_hash[:ha_admit_control] = das_config[:admissionControlEnabled].to_s.downcase == "true"
      cluster_hash[:ha_max_failures]  = das_config[:failoverLevel]
    end

    def parse_compute_resource_drs_config(cluster_hash, props)
      drs_config = props.fetch_path(:configuration, :drsConfig)
      return if drs_config.nil?

      cluster_hash[:drs_enabled]             = drs_config[:enabled].to_s.downcase == "true"
      cluster_hash[:drs_automation_level]    = drs_config[:defaultVmBehavior]
      cluster_hash[:drs_migration_threshold] = drs_config[:vmotionRate]
    end

    def parse_compute_resource_children(cluster_hash, props)
      cluster_hash[:ems_children] = {:rp => []}
      rp = props[:resourcePool]
      unless rp.nil?
        cluster_hash[:ems_children][:rp] << persister.resource_pools.lazy_find(rp._ref)
      end
    end
  end
end
