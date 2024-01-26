class ManageIQ::Providers::Vmware::InfraManager::ProvisionViaPxe < ManageIQ::Providers::Vmware::InfraManager::Provision
  include Cloning
  include Pxe
  include StateMachine
end
