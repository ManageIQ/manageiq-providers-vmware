module ManageIQ::Providers::Vmware::InfraManager::Vm::Operations::Snapshot
  extend ActiveSupport::Concern

  def snapshotting_memory_allowed?
    current_state == 'on'
  end

  def raw_create_snapshot(name, desc = nil, memory)
    run_command_via_parent(:vm_create_snapshot, :name => name, :desc => desc, :memory => memory)
  rescue => err
    error = String.new(err.message)
    create_notification(:vm_snapshot_failure, :error => error, :snapshot_op => "create")
    raise MiqException::MiqVmSnapshotError, error
  end

  def raw_remove_snapshot(snapshot_id)
    require "VMwareWebService/MiqVimVm"

    raise MiqException::MiqVmError, unsupported_reason(:remove_snapshot) unless supports?(:remove_snapshot)
    snapshot = snapshots.find_by(:id => snapshot_id)
    raise _("Requested VM snapshot not found, unable to remove snapshot") unless snapshot
    raise _("Refusing to delete a VCB Snapshot") if snapshot.name == MiqVimVm::VCB_SNAPSHOT_NAME
    raise _("Refusing to delete snapshot when there is a Consolidate Helper snapshot") if snapshots.any? { |s| MiqVimVm::CH_SNAPSHOT_NAME =~ s.name }

    begin
      _log.info("removing snapshot ID: [#{snapshot.id}] uid_ems: [#{snapshot.uid_ems}] ems_ref: [#{snapshot.ems_ref}] name: [#{snapshot.name}] description [#{snapshot.description}]")

      run_command_via_parent(:vm_remove_snapshot, :snMor => snapshot.uid_ems)
    rescue => err
      error = String.new(err.message)

      create_notification(:vm_snapshot_failure, :error => error, :snapshot_op => "remove")
      if err.kind_of?(VimFault)
        raise MiqException::MiqVmSnapshotError, error
      else
        raise
      end
    end
  end

  def raw_remove_snapshot_by_description(description, refresh = false)
    raise MiqException::MiqVmError, unsupported_reason(:remove_snapshot_by_description) unless supports?(:remove_snapshot_by_description)
    run_command_via_parent(:vm_remove_snapshot_by_description, :description => description, :refresh => refresh)
  end

  def remove_snapshot_by_description(description, refresh = false, retry_time = nil)
    if host.nil? || host.state == "on"
      raw_remove_snapshot_by_description(description, refresh)
    else
      if retry_time.nil?
        raise _("The VM's Host system is unavailable to remove the snapshot. VM id:[%{id}] Snapshot description:[%{description}]") %
                {:id => id, :descrption => description}
      end
      # If the host is off re-queue the action based on the retry_time
      MiqQueue.put(:class_name  => self.class.name,
                   :instance_id => id,
                   :method_name => 'remove_snapshot_by_description',
                   :args        => [description, refresh, retry_time],
                   :deliver_on  => Time.now.utc + retry_time,
                   :role        => "smartstate",
                   :zone        => my_zone)
    end
  end

  def raw_remove_all_snapshots
    raise MiqException::MiqVmError, unsupported_reason(:remove_all_snapshots) unless supports?(:remove_all_snapshots)
    run_command_via_parent(:vm_remove_all_snapshots)
  end

  def raw_revert_to_snapshot(snapshot_id)
    raise MiqException::MiqVmError, unsupported_reason(:revert_to_snapshot) unless supports?(:revert_to_snapshot)
    snapshot = snapshots.find_by(:id => snapshot_id)
    raise _("Requested VM snapshot not found, unable to RevertTo snapshot") unless snapshot
    run_command_via_parent(:vm_revert_to_snapshot, :snMor => snapshot.uid_ems)
  end
end
