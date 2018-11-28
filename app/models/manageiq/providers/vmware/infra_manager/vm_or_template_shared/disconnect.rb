module ManageIQ::Providers::Vmware::InfraManager::VmOrTemplateShared::Disconnect
  extend ActiveSupport::Concern

  def disconnect_storage
    # If the VM was unregistered don't clear the storage because the disks
    # are still on the underlying datastore
    super unless unregistered?
  end

  def destroyed?
    disconnect_events.last&.event_type == "DestroyVM_Task_Complete"
  end

  def unregistered?
    disconnect_events.last&.event_type == "UnregisterVM_Complete"
  end

  private

  def disconnect_events
    ems_events.where(:event_type => disconnect_event_types)
  end

  def disconnect_event_types
    %w(DestroyVM_Task_Complete UnregisterVM_Complete)
  end
end
