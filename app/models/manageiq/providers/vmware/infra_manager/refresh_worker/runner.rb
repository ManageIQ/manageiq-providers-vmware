class ManageIQ::Providers::Vmware::InfraManager::RefreshWorker::Runner < ManageIQ::Providers::BaseManager::RefreshWorker::Runner
  # When using update_driven_refresh we don't need to use the VimBrokerWorker
  self.require_vim_broker           = !Settings.prototype.ems_vmware.update_driven_refresh
  self.delay_startup_for_vim_broker = !Settings.prototype.ems_vmware.update_driven_refresh

  def after_initialize
    super
    self.ems = @emss.first
  end

  def before_exit(_message, _exit_code)
    stop_inventory_collector if ems.supports_streaming_refresh?
  end

  def do_before_work_loop
    # No need to queue an initial full refresh if we are streaming
    super unless ems.supports_streaming_refresh?
  end

  def do_work
    if ems.supports_streaming_refresh?
      ensure_inventory_collector
    elsif collector&.running?
      stop_inventory_collector
    end

    super
  end

  def deliver_queue_message(msg)
    return super unless ems.supports_streaming_refresh?

    msg.delivered_on

    # If a full refresh was queued then restart the inventory collector thread
    restart_inventory_collector if full_refresh_queued?(msg)

    msg.delivered(MiqQueue::STATUS_OK, "Message delivered successfully", true)
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

  def full_refresh_queued?(msg)
    msg.class_name == "EmsRefresh" && msg.method_name == "refresh" && msg.data.any? { |klass, _id| klass == ems.class.name }
  end
end
