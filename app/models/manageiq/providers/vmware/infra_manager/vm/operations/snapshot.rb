module ManageIQ::Providers::Vmware::InfraManager::Vm::Operations::Snapshot
  extend ActiveSupport::Concern

  def snapshotting_memory_allowed?
    current_state == 'on'
  end
end
