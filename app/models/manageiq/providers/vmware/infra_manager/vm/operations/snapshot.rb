module ManageIQ::Providers::Vmware::InfraManager::Vm::Operations::Snapshot
  extend ActiveSupport::Concern

  def snapshotting_memory_allowed?
    current_state == 'on'
  end

  def raw_create_snapshot(name, desc = nil, memory)
    run_command_via_parent(:vm_create_snapshot, :name => name, :desc => desc, :memory => memory)
  rescue => err
    create_notification(:vm_snapshot_failure, :error => err.to_s, :snapshot_op => "create")
    raise MiqException::MiqVmSnapshotError, err.to_s
  end

  def raw_remove_snapshot(snapshot_id)
    raise MiqException::MiqVmError, unsupported_reason(:remove_snapshot) unless supports_remove_snapshot?
    snapshot = snapshots.find_by(:id => snapshot_id)
    raise _("Requested VM snapshot not found, unable to remove snapshot") unless snapshot
    begin
      _log.info("removing snapshot ID: [#{snapshot.id}] uid_ems: [#{snapshot.uid_ems}] ems_ref: [#{snapshot.ems_ref}] name: [#{snapshot.name}] description [#{snapshot.description}]")

      run_command_via_parent(:vm_remove_snapshot, :snMor => snapshot.uid_ems)
    rescue => err
      create_notification(:vm_snapshot_failure, :error => err.to_s, :snapshot_op => "remove")
      if err.to_s.include?('not found')
        raise MiqException::MiqVmSnapshotError, err.to_s
      else
        raise
      end
    end
  end

  def raw_remove_snapshot_by_description(description, refresh = false)
    raise MiqException::MiqVmError, unsupported_reason(:remove_snapshot_by_description) unless supports_remove_snapshot_by_description?
    run_command_via_parent(:vm_remove_snapshot_by_description, :description => description, :refresh => refresh)
  end

  def raw_remove_all_snapshots
    raise MiqException::MiqVmError, unsupported_reason(:remove_all_snapshots) unless supports_remove_all_snapshots?
    run_command_via_parent(:vm_remove_all_snapshots)
  end

  def raw_revert_to_snapshot(snapshot_id)
    raise MiqException::MiqVmError, unsupported_reason(:revert_to_snapshot) unless supports_revert_to_snapshot?
    snapshot = snapshots.find_by(:id => snapshot_id)
    raise _("Requested VM snapshot not found, unable to RevertTo snapshot") unless snapshot
    run_command_via_parent(:vm_revert_to_snapshot, :snMor => snapshot.uid_ems)
  end
end
