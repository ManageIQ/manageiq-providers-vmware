class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  module Datacenter
    def parse_datacenter_children(dc_hash, props)
      dc_hash[:ems_children] = {:folder => []}

      if props.include?("datastoreFolder")
        dc_hash[:ems_children][:folder] << persister.ems_folders.lazy_find(props["datastoreFolder"]._ref)
      end
      if props.include?("hostFolder")
        dc_hash[:ems_children][:folder] << persister.ems_folders.lazy_find(props["hostFolder"]._ref)
      end
      if props.include?("networkFolder")
        dc_hash[:ems_children][:folder] << persister.ems_folders.lazy_find(props["networkFolder"]._ref)
      end
      if props.include?("vmFolder")
        dc_hash[:ems_children][:folder] << persister.ems_folders.lazy_find(props["vmFolder"]._ref)
      end
    end
  end
end
