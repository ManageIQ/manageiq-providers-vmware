module ManageIQ::Providers::Vmware::CloudManager::Vm::Operations::Snapshot
  extend ActiveSupport::Concern

  def raw_create_snapshot(name, desc = nil, memory)
    run_command_via_parent(:vm_create_snapshot, :name => name, :desc => desc, :memory => memory)
  rescue => err
    create_notification(:vm_snapshot_failure, :error => err.to_s, :snapshot_op => "create")
    raise MiqException::MiqVmSnapshotError, err.to_s
  end

  def raw_revert_to_snapshot(snapshot_id)
    raise MiqException::MiqVmError, unsupported_reason(:revert_to_snapshot) unless supports_revert_to_snapshot?
    snapshot = snapshots.find_by(:id => snapshot_id)
    raise _("Requested VM snapshot not found, unable to RevertTo snapshot") unless snapshot
    run_command_via_parent(:vm_revert_to_snapshot, :snMor => snapshot.uid_ems)
  end
end
