class ManageIQ::Providers::Vmware::InfraManager::OperationsWorker::Runner < ::MiqWorker::Runner
  OPTIONS_PARSER_SETTINGS = ::MiqWorker::Runner::OPTIONS_PARSER_SETTINGS + [
    [:ems_id, 'EMS Instance ID', String],
  ]

  def after_initialize
    @ems = ExtManagementSystem.find(@cfg[:ems_id])
    do_exit("Unable to find instance for EMS ID [#{@cfg[:ems_id]}].", 1) if @ems.nil?
    do_exit("EMS ID [#{@cfg[:ems_id]}] failed authentication check.", 1) unless @ems.authentication_check.first

    @operations_class = @ems.class::Operations
  end

  def do_before_work_loop
    start_rest_server
  end

  def do_work
    return if rest_server_thread_alive?

    _log.warn("REST server not running, restarting...")
    start_rest_server
    _log.info("Restarted REST server thread")
  end

  def before_exit(_message, _exit_code)
    stop_rest_server_thread

    unless rest_server_thread.nil?
      rest_server_thread.join(10) rescue nil
    end
  end

  private

  attr_reader :ems, :operations_class, :rest_server_thread

  def start_rest_server
    thread_started = Concurrent::Event.new

    _log.info("Starting Operations REST server...")

    @rest_server_thread = Thread.new { rest_server(thread_started) }
    thread_started.wait

    if rest_server_thread.alive?
      update_worker_uri(rest_server_uri)
      _log.info("Starting Operations REST server...Complete")
    else
      _log.warn("Starting Operations REST server...Failed")
    end
  end

  def stop_rest_server_thread
    operations_class.quit!
  end

  def rest_server_thread_alive?
    rest_server_thread.try(:alive?)
  end

  def rest_server(started_event)
    operations_class.run!(:port => rest_server_port) { started_event.set }
    rest_server_instance.shutdown
  rescue => err
    _log.warn("Exception in Operations REST server: #{err}")
    _log.log_backtrace(err)
  ensure
    started_event.set
  end

  def update_worker_uri(uri)
    @worker.update_attributes(:uri => uri)
  end

  def rest_server_port
    return ENV['PORT'] if ENV['PORT'].present?

    # Get the ems_id without the region factor
    short_ems_id = ApplicationRecord.split_id(ems.id).last

    base_port_number = ENV['BASE_PORT'] || 6_000
    base_port_number + short_ems_id
  end

  def rest_server_uri
    "#{operations_class.bind}:#{operations_class.port}"
  end

  def rest_server_instance
    # HACK: can't find another way to get at the sinatra instance to
    # gracefully shutdown connections
    operations_class.prototype.instance_variable_get(:@instance)
  end
end
