module ManageIQ::Providers::Vmware::CloudManager::EventCatcherMixin

  def event_monitor_handle
    unless @event_monitor_handle
      options = @ems.event_monitor_options
      options[:queues]                        = queue_names
      options[:duration]                      = worker_settings[:duration]
      options[:capacity]                      = worker_settings[:capacity]
      options[:heartbeat]                     = worker_settings[:amqp_heartbeat]
      options[:recovery_attempts]             = worker_settings[:amqp_recovery_attempts]
      options[:client_ip]                     = server.ipaddress
      options[:automatic_recovery]            = true
      options[:recover_from_connection_close] = true
      options[:ems]                           = @ems

      @event_monitor_handle = ManageIQ::Providers::Vmware::CloudManager::EventCatcher::Stream.new(options)
    end
    @event_monitor_handle
  end

  def queue_names
    @ems.connect.organizations.all.map do |org|
      "queue-#{org.id}"
    end
  end

  def reset_event_monitor_handle
    @event_monitor_handle = nil
  end

  # Start monitoring for events. This method blocks forever until stop_event_monitor is called.
  def monitor_events
    event_monitor_handle.start
    event_monitor_handle.each_batch do |events|
      event_monitor_running
      if events && !events.empty?
        @queue.enq events
      end
      sleep_poll_normal
    end
  ensure
    reset_event_monitor_handle
  end

  def stop_event_monitor
    @event_monitor_handle.stop unless @event_monitor_handle.nil?
  rescue StandardException => err
    $vcloud_log.warn("Event Monitor Stop errored because [#{err.message}]")
    $vcloud_log.warn("Error details: [#{err.details}]")
    $vcloud_log.log_backtrace(err)
  ensure
    reset_event_monitor_handle
  end

  def queue_event(event)
    $vcloud_log.info("Caught event [#{event.type}]")
    event_hash = ManageIQ::Providers::Vmware::CloudManager::EventParser.event_to_hash(event, @cfg[:ems_id])
    EmsEvent.add_queue('add', @cfg[:ems_id], event_hash)
  end

  def filtered?(event)
    @ems.filtered_event_namess.include?(event.type)
  end
end
