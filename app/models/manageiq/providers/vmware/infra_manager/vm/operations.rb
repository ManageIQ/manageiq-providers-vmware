module ManageIQ::Providers::Vmware::InfraManager::Vm::Operations
  extend ActiveSupport::Concern

  include_concern 'Guest'
  include_concern 'Snapshot'

  def rename(new_name, vim = nil)
    provider_object(vim).renameVM(new_name)
  end
end
