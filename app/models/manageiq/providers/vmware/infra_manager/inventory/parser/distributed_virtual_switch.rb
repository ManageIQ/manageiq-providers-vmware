class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  module DistributedVirtualSwitch
    def parse_dvs_config(dvs_hash, config)
      return if config.nil?

      dvs_hash[:name] ||= CGI.unparse(config[:name]) if config[:name].present?
      dvs_hash[:ports] = config[:numPorts] || 0
      dvs_hash[:switch_uuid] ||= config[:uuid]

      parse_dvs_security_policy(dvs_hash, config[:defaultPortConfig]&.securityPolicy)
    end

    def parse_dvs_summary(dvs_hash, summary)
      return if summary.nil?

      dvs_hash[:name] ||= CGI.unescape(summary[:name]) if summary[:name].present?
      dvs_hash[:switch_uuid] ||= summary[:uuid]
    end

    def parse_dvs_security_policy(dvs_hash, security_policy)
      return if security_policy.nil?

      dvs_hash[:allow_promiscuous] = security_policy.allowPromiscuous&.value
      dvs_hash[:forged_transmits]  = security_policy.forgedTransmits&.value
      dvs_hash[:mac_changes]       = security_policy.macChanges&.value
    end
  end
end
