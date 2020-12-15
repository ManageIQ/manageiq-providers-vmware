class ManageIQ::Providers::Vmware::InfraManager::Scanning::Job < VmScan
  # Make updates to default state machine to take into account snapshots
  def load_transitions
    super.tap do |transitions|
      transitions.merge!(
        :start_snapshot     => {'before_scan'               => 'snapshot_create'},
        :snapshot_complete  => {'snapshot_create'           => 'check_host_credentials',
                                'snapshot_delete'           => 'synchronizing'},
        :start_scan         => {'check_host_credentials'    => 'scanning'},
        :snapshot_delete    => {'after_scan'                => 'snapshot_delete'},
        :data               => {'snapshot_create'           => 'scanning',
                                'scanning'                  => 'scanning',
                                'snapshot_delete'           => 'snapshot_delete',
                                'synchronizing'             => 'synchronizing',
                                'finished'                  => 'finished'}
      )
    end
  end

  def before_scan
    queue_signal(:start_snapshot, role: "ems_operations", queue_name: vm.queue_name_for_ems_operations)
  end

  def after_scan
    queue_signal(:snapshot_delete, role: "ems_operations", queue_name: vm.queue_name_for_ems_operations)
  end

  def call_snapshot_create
    _log.info("Enter")

    begin
      context[:snapshot_mor] = nil

      options[:snapshot] = :skipped
      options[:use_existing_snapshot] = false

      begin
        proxy = MiqServer.find(miq_server_id)

        if proxy && proxy.forceVmScan
          options[:snapshot] = :smartProxy
          _log.info("Skipping snapshot creation, it will be performed by the SmartProxy")
          context[:snapshot_mor] = options[:snapshot_description] = snapshotDescription("(embedded)")
          log_start_user_event_message
        else
          set_status("Creating VM snapshot")

          return unless create_snapshot
        end
      end
      signal(:snapshot_complete)
    rescue Timeout::Error
      msg = case options[:snapshot]
            when :smartProxy, :skipped then "Request to log snapshot user event with EMS timed out."
            else "Request to create snapshot timed out"
            end
      _log.error(msg)
      signal(:abort, msg, "error")
    rescue => err
      _log.log_backtrace(err)
      signal(:abort, err.message, "error")
      return
    end
  end

  def check_host_credentials
    _log.info("Enter")

    begin
      host = MiqServer.find(miq_server_id)
      # Send down metadata to allow the host to make decisions.
      scan_args = create_scan_args
      options[:ems_list] = scan_args["ems"]
      options[:categories] = vm.scan_profile_categories(scan_args["vmScanProfiles"])

      # If the host supports VixDisk Lib then we need to validate that the host has the required credentials set.
      ems_list = scan_args["ems"]
      scan_ci_type = ems_list['connect_to']
      if host.is_vix_disk? && ems_list[scan_ci_type] && (ems_list[scan_ci_type][:username].nil? || ems_list[scan_ci_type][:password].nil?)
        context[:snapshot_mor] = nil unless options[:snapshot] == :created
        raise _("no credentials defined for %{type} %{name}") % {:type => scan_ci_type,
                                                                 :name => ems_list[scan_ci_type][:hostname]}
      end

      if ems_list[scan_ci_type]
        _log.info("[#{host.name}] communicates with [#{scan_ci_type}:#{ems_list[scan_ci_type][:hostname]}"\
                  "(#{ems_list[scan_ci_type][:address]})] to scan vm [#{vm.name}]")
      end
      signal(:start_scan)
    rescue Timeout::Error
      message = "timed out attempting to scan, aborting"
      _log.error(message)
      signal(:abort, message, "error")
      return
    rescue => message
      _log.log_backtrace(message)
      signal(:abort, message.message, "error")
    end
  end

  def config_snapshot
    snapshot = {"use_existing" => options[:use_existing_snapshot],
                "description"  => options[:snapshot_description]}
    snapshot['create_free_percent'] = ::Settings.snapshots.create_free_percent
    snapshot['remove_free_percent'] = ::Settings.snapshots.remove_free_percent
    snapshot['name'] = context[:snapshot_mor]
    snapshot
  end

  def create_scan_args
    super.tap do |scan_args|
      scan_args['snapshot'] = config_snapshot
      scan_args['snapshot']['forceFleeceDefault'] = false if vm.scan_via_ems? && vm.template?
    end
  end

  def call_snapshot_delete
    _log.info("Enter")

    # TODO: remove snapshot here if Vm was running
    if context[:snapshot_mor]
      mor = context[:snapshot_mor]
      context[:snapshot_mor] = nil

      if options[:snapshot] == :smartProxy
        set_status("Snapshot delete was performed by the SmartProxy")
      else
        set_status("Deleting VM snapshot: reference: [#{mor}]")
      end

      if vm.ext_management_system
        _log.info("Deleting snapshot: reference: [#{mor}]")
        begin
          delete_snapshot(mor)
        rescue Timeout::Error
          msg = "Request to delete snapshot timed out"
          _log.error(msg)
        rescue => err
          _log.error(err.to_s)
          return
        end

        unless options[:snapshot] == :smartProxy
          _log.info("Deleted snapshot: reference: [#{mor}]")
          set_status("Snapshot deleted: reference: [#{mor}]")
        end
      else
        _log.error("Deleting snapshot: reference: [#{mor}], No Providers available to delete snapshot")
        set_status("No Providers available to delete snapshot, skipping", "error")
      end
    else
      set_status("Snapshot was not taken, delete not required") if options[:snapshot] == :skipped
      log_end_user_event_message
    end

    signal(:snapshot_complete)
  end

  def delete_snapshot(mor)
    if mor
      begin
        if vm.ext_management_system
          if options[:snapshot] == :smartProxy
            log_end_user_event_message
            delete_snapshot_by_description(mor)
          else
            user_event = end_user_event_message
            vm.ext_management_system.vm_remove_snapshot(vm, :snMor => mor, :user_event => user_event)
          end
        else
          raise _("No Providers available to delete snapshot")
        end
      rescue => err
        _log.error(err.message)
        _log.log_backtrace(err, :debug)
      end
    else
      log_end_user_event_message
    end
  end

  def delete_snapshot_by_description(mor)
    if mor
      ems_type = 'host'
      options[:ems_list] = vm.ems_host_list
      miqVimHost = options[:ems_list][ems_type]

      miqVim = nil
      # Make sure we were given a host to connect to and have a non-nil encrypted password
      if miqVimHost && !miqVimHost[:password].nil?
        server = miqVimHost[:hostname] || miqVimHost[:ipaddress]
        begin
          password_decrypt = ManageIQ::Password.decrypt(miqVimHost[:password])
          require 'VMwareWebService/MiqVim'
          miqVim = MiqVim.new(server, miqVimHost[:username], password_decrypt)

          vimVm = miqVim.getVimVm(vm.path)
          vimVm.removeSnapshotByDescription(mor, true) unless vimVm.nil?
        ensure
          vimVm.release if vimVm rescue nil
          miqVim.disconnect unless miqVim.nil?
        end
      end
    end
  end

  def process_cancel(*args)
    begin
      delete_snapshot_and_reset_snapshot_mor("canceling")
      super
    rescue => err
      _log.log_backtrace(err)
    end

    super
  end

  def process_abort(*args)
    begin
      delete_snapshot_and_reset_snapshot_mor("aborting")
      super
    rescue => err
      _log.log_backtrace(err)
    end

    super
  end

  def snapshot_complete
    if state == 'check_host_credentials'
      check_host_credentials
    else
      call_synchronize
    end
  end

  def start_scan
    scanning
    call_scan
  end

  # All other signals
  alias_method :start_snapshot,     :call_snapshot_create
  alias_method :snapshot_delete,    :call_snapshot_delete

  private

  def create_snapshot
    if vm.ext_management_system
      sn_description = snapshotDescription
      _log.info("Creating snapshot, description: [#{sn_description}]")
      user_event = start_user_event_message
      options[:snapshot] = :server
      begin
        # TODO: should this be a vm method?
        sn = vm.ext_management_system.vm_create_evm_snapshot(vm, :desc => sn_description, :user_event => user_event).to_s
      rescue Exception => err
        msg = "Failed to create evm snapshot with EMS. Error: [#{err.class.name}]: [#{err}]"
        _log.error(msg)
        return false
      end
      context[:snapshot_mor] = sn
      _log.info("Created snapshot, description: [#{sn_description}], reference: [#{context[:snapshot_mor]}]")
      set_status("Snapshot created: reference: [#{context[:snapshot_mor]}]")
      options[:snapshot] = :created
      options[:use_existing_snapshot] = true
      return true
    else
      signal(:abort, "No Providers available to create snapshot, skipping", "error")
      return false
    end
  end

  def snapshotDescription(type = nil)
    Snapshot.evm_snapshot_description(jobid, type)
  end

  def delete_snapshot_and_reset_snapshot_mor(log_verb)
    unless context[:snapshot_mor].nil?
      mor = context[:snapshot_mor]
      context[:snapshot_mor] = nil
      set_status("Deleting snapshot before #{log_verb} job")
      delete_snapshot(mor)
    end
  end

end
