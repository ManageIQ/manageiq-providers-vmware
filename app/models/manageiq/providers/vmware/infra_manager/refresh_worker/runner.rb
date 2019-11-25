class ManageIQ::Providers::Vmware::InfraManager::RefreshWorker::Runner < ManageIQ::Providers::BaseManager::RefreshWorker::Runner
  self.require_vim_broker           = false
  self.delay_startup_for_vim_broker = false

  def after_initialize
    super
    self.ems = @emss.first
  end

  def before_exit(_message, _exit_code)
    stop_inventory_collector
  end

  def do_before_work_loop
    # No need to queue an initial full refresh if we are streaming
  end

  def do_work
    ensure_inventory_collector

    super
  end

  def deliver_queue_message(msg)
    if refresh_queued?(msg)
      super do
        if full_refresh_queued?(msg)
          restart_inventory_collector
        else
          _log.info("Dropping refresh targets [#{msg.data}] because streaming refresh is enabled")
        end
      end
    end
  end

  private

  attr_accessor :ems, :collector

  def start_inventory_collector
    self.collector = ems.class::Inventory::Collector.new(ems)
    collector.start
    _log.info("Started inventory collector")
  end

  def ensure_inventory_collector
    return if collector&.running?

    _log.warn("Inventory collector thread not running, restarting...") unless collector.nil?
    start_inventory_collector
  end

  def stop_inventory_collector
    collector&.stop
    self.collector = nil
  end

  def restart_inventory_collector
    _log.info("Restarting inventory collector...")
    collector&.restart
    _log.info("Restarting inventory collector...Complete")
  end

  def refresh_queued?(msg)
    msg.class_name == "EmsRefresh" && msg.method_name == "refresh"
  end

  def full_refresh_queued?(msg)
    refresh_queued?(msg) && msg.data.any? { |klass, _id| klass == ems.class.name }
  end
end
