class ManageIQ::Providers::Vmware::InfraManager::EventCatcher::Runner < ManageIQ::Providers::BaseManager::EventCatcher::Runner
  def event_monitor_handle
    require 'VMwareWebService/MiqVimEventMonitor'
    @event_monitor_handle ||= MiqVimEventMonitor.new(
      :server    => @ems.hostname,
      :username  => @ems.authentication_userid,
      :password  => @ems.authentication_password,
      :page_size => worker_settings[:ems_event_page_size],
      :max_wait  => worker_settings[:ems_event_max_wait]
    )
  end

  def reset_event_monitor_handle
    @event_monitor_handle = nil
  end

  def stop_event_monitor
    @event_monitor_handle.stop unless @event_monitor_handle.nil?
  rescue Exception => err
    _log.warn("#{log_prefix} Event Monitor Stop errored because [#{err.message}]")
    _log.warn("#{log_prefix} Error details: [#{err.details}]")
    _log.log_backtrace(err)
  ensure
    reset_event_monitor_handle
  end

  def monitor_events
    event_monitor_running
    event_monitor_handle.monitorEvents do |ea|
      @queue.enq(ea)
      sleep_poll_normal
    end
  rescue Handsoap::Fault => err
    if  @exit_requested && (err.code == "ServerFaultCode") && (err.reason == "The task was canceled by a user.")
      _log.info("#{log_prefix} Event Monitor Thread terminated normally")
    else
      _log.error("#{log_prefix} Event Monitor Thread aborted because [#{err.message}]")
      _log.error("#{log_prefix} Error details: [#{err.details}]")
      _log.log_backtrace(err)
    end
    raise EventCatcherHandledException
  ensure
    reset_event_monitor_handle
  end

  def event_dedup_key(event)
    # duplicate the event but remove ids and timestamps that change with every event
    # the remaining attributes are used to determine whether an event is a duplicate of another
    event.except("key", "chainId", "createdTime").tap do |hash|
      hash["info"] &&= hash["info"].except("key", "task", "queueTime", "eventChainId")
    end
  end

  def event_dedup_descriptor(event)
    event_dedup_key(event)
  end

  def filtered?(event)
    event_type = event['eventType']
    return true if event_type.nil?

    sub_event_type, display_name = sub_type_and_name(event)

    return false unless filtered_events.include?(event_type) || filtered_events.include?(sub_event_type)

    _log.info("#{log_prefix} Skipping caught event [#{display_name}] chainId [#{event['chainId']}]")
    true
  end

  def queue_event(event)
    _sub_event_type, display_name = sub_type_and_name(event)
    _log.info("#{log_prefix} Queueing event [#{display_name}] chainId [#{event['chainId']}]")
    event_hash = ManageIQ::Providers::Vmware::InfraManager::EventParser.event_to_hash(event, @cfg[:ems_id])
    EmsEvent.add_queue('add', @cfg[:ems_id], event_hash)
  end

  def sub_type_and_name(event)
    event_type = event['eventType']
    return if event_type.nil?

    case event_type
    when "TaskEvent"
      sub_event_type = event.fetch_path('info', 'name')
      display_name   = "#{event_type}]-[#{sub_event_type}"
    when "EventEx"
      sub_event_type = event['eventTypeId']
      display_name   = "#{event_type}]-[#{sub_event_type}"
    else
      sub_event_type = nil
      display_name   = event_type
    end

    [sub_event_type, display_name]
  end
end
