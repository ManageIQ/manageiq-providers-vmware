class ManageIQ::Providers::Vmware::InfraManager::DistributedVirtualSwitch < ManageIQ::Providers::InfraManager::DistributedVirtualSwitch
  belongs_to :ext_management_system, :foreign_key => :ems_id
end
