module ManageIQ::Providers::Vmware::InfraManager::Provision::StateMachine
  def create_destination
    signal :determine_placement
  end

  def determine_placement
    host, cluster, datastore = placement

    options[:dest_host]    = [host.id, host.name]       if host
    options[:dest_cluster] = [cluster.id, cluster.name] if cluster
    options[:dest_storage] = [datastore.id, datastore.name]
    signal :start_clone_task
  end

  def start_clone_task
    update_and_notify_parent(:message => "Starting Clone of #{clone_direction}")

    # Use this ID to validate the VM when we check in the post-provision method
    phase_context[:new_vm_validation_guid] = SecureRandom.uuid

    clone_options = prepare_for_clone_task
    log_clone_options(clone_options)
    phase_context[:clone_task_mor] = start_clone(clone_options)
    signal :poll_clone_complete
  end

  def poll_clone_complete
    task_mor = VimString.new(phase_context[:clone_task_mor], "Task", :ManagedObjectReference)
    clone_status, status_message = do_clone_task_check(task_mor)

    status_message = "completed; post provision work queued" if clone_status
    message = "Clone of #{clone_direction} is #{status_message}"
    _log.info(message.to_s)
    update_and_notify_parent(:message => message)

    if clone_status
      phase_context.delete(:clone_task_mor)
      EmsRefresh.queue_refresh(dest_host)
      signal :poll_destination_in_vmdb
    else
      requeue_phase
    end
  end

  def poll_destination_in_vmdb
    update_and_notify_parent(:message => "Validating New #{destination_type}")

    self.destination = find_destination_in_vmdb
    if destination
      phase_context.delete(:new_vm_validation_guid)
      signal :customize_destination
    else
      _log.info("Unable to find #{destination_type} [#{dest_name}] with ems_ref [#{phase_context[:new_vm_ems_ref]}], will retry")
      requeue_phase
    end
  end

  def autostart_destination
    return signal :post_create_destination unless get_option(:vm_auto_start)

    _log.info("Starting #{for_destination}")
    update_and_notify_parent(:message => "Starting")

    destination.raw_start
    signal :post_create_destination
  rescue MiqException::MiqVimResourceNotFound
    _log.info("Unable to start #{for_destination}.  Retrying...")
    requeue_phase
  end

  def customize_destination
    _log.info("Post-processing #{destination_type} id: [#{destination.id}], name: [#{dest_name}]")
    update_and_notify_parent(:message => "Starting New #{destination_type} Customization")

    reconfigure_hardware
    signal :autostart_destination
  end

  private

  def powered_off_in_provider?
    destination.with_provider_object(&:poweredOff?)
  end

  def powered_on_in_provider?
    destination.with_provider_object(&:poweredOn?)
  end
end
