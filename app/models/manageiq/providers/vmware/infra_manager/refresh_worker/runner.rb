class ManageIQ::Providers::Vmware::InfraManager::RefreshWorker::Runner < ManageIQ::Providers::BaseManager::RefreshWorker::Runner
  # When using update_driven_refresh we don't need to use the VimBrokerWorker
  self.require_vim_broker           = !Settings.prototype.ems_vmware.update_driven_refresh
  self.delay_startup_for_vim_broker = !Settings.prototype.ems_vmware.update_driven_refresh

  def after_initialize
    super
    self.ems = @emss.first
  end

  def do_before_work_loop
    # Override Standard EmsRefreshWorker's method of queueing up a Refresh
    # This will be done by the VimBrokerWorker, when he is ready.
    return unless update_driven_refresh?

    start_inventory_collector
  end

  def before_exit(_message, _exit_code)
    stop_inventory_collector if inventory_collector_running?
  end

  def do_work
    if update_driven_refresh?
      ensure_inventory_collector
    elsif inventory_collector_running?
      stop_inventory_collector
    end

    super
  end

  private

  attr_accessor :ems, :collector, :collector_thread

  def start_inventory_collector
    self.collector = ems.class::Inventory::Collector.new(ems)
    self.collector_thread = Thread.new do
      begin
        collector.run
      rescue => err
        _log.error("Inventory collector aborted because [#{err.message}]")
        _log.log_backtrace(err)
        Thread.exit
      end
    end

    _log.info("Started inventory collector")
  end

  def ensure_inventory_collector
    return if inventory_collector_running?

    _log.warn("Inventory collector thread not running, restarting...")
    start_inventory_collector
  end

  def stop_inventory_collector
    collector.stop

    # The WaitOptions for WaitForUpdatesEx call sets maxWaitSeconds to 60 seconds
    collector_thread.join(60.seconds) # TODO: make this configurable

    self.collector_thread = nil
    self.collector = nil
  end

  def inventory_collector_running?
    collector_thread&.alive?
  end

  def update_driven_refresh?
    Settings.prototype.ems_vmware.update_driven_refresh
  end
end
