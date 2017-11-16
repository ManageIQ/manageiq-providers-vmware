class ManageIQ::Providers::Vmware::InfraManager::RefreshWorker::Runner < ManageIQ::Providers::BaseManager::RefreshWorker::Runner
  self.require_vim_broker = true

  def do_before_work_loop
    # Override Standard EmsRefreshWorker's method of queueing up a Refresh
    # This will be done by the VimBrokerWorker, when he is ready.

    if Settings.prototype.ems_vmware.update_driven_refresh
      ems = @emss.first
      @collector = ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector.new(ems)
      @collector_thread = start_inventory_collector(@collector)
    end
  end

  def before_exit(_message, _exit_code)
    if Settings.prototype.ems_vmware.update_driven_refresh
      stop_inventory_collector(@collector)

      # The WaitOptions for WaitForUpdatesEx call sets maxWaitSeconds to 60 seconds
      @collector_thread.join(60.seconds) # TODO: make this configurable
    end
  end

  def start_inventory_collector(collector)
    thread = Thread.new do
      begin
        collector.run
      rescue => err
        _log.error("Inventory collector aborted because [#{err.message}]")
        _log.log_backtrace(err)
        Thread.exit
      end
    end

    _log.info("Started inventory collector")

    thread
  end

  def stop_inventory_collector(collector)
    collector.stop
  end
end
