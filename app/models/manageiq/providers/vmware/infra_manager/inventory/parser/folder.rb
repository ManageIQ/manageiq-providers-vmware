class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  module Folder
    def parse_folder_children(folder_hash, props)
      folder_hash[:ems_children] = {}

      if props.include?("childEntity")
        props["childEntity"].to_a.each do |child|
          folder_hash[:ems_children][child.class.wsdl_name] ||= []
          folder_hash[:ems_children][child.class.wsdl_name] << child._ref
        end
      end

      folder_hash
    end
  end
end
