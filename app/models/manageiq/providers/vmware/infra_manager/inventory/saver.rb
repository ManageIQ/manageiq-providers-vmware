class ManageIQ::Providers::Vmware::InfraManager::Inventory::Saver
  include Vmdb::Logging

  def initialize(threaded: true)
    @join_limit  = 30
    @queue       = Queue.new
    @should_exit = Concurrent::AtomicBoolean.new
    @threaded    = threaded
    @thread      = nil
  end

  def start_thread
    return unless threaded

    @thread = Thread.new do
      saver_thread
      _log.info("Save inventory thread exiting")
    end

    _log.info("Save inventory thread started")
  end

  def stop_thread(wait: true)
    return unless threaded

    _log.info("Save inventory thread stopping...")

    should_exit.make_true
    queue.push(nil) # Force the blocking queue.pop call to return
    join_thread if wait
  end

  # This method will re-start the saver thread if it has crashed or terminated
  # prematurely, but is only safe to be called from a single thread.  Given
  # wait_for_updates has to be single threaded this should be fine but if you
  # intend to queue up save_inventory from multiple calling threads a mutex
  # must be added around ensure_saver_thread
  def queue_save_inventory(persister)
    if threaded
      ensure_saver_thread
      queue.push(persister)
    else
      save_inventory(persister)
    end
  end

  private

  attr_reader :join_limit, :queue, :should_exit, :thread, :threaded

  def saver_thread
    until should_exit.true?
      persister = queue.pop
      next if persister.nil?

      save_inventory(persister)
    end
  rescue => err
    _log.warn(err)
    _log.log_backtrace(err)
  end

  def join_thread
    return unless thread&.alive?

    unless thread.join(join_limit)
      thread.kill
    end
  end

  def ensure_saver_thread
    return if thread&.alive?

    _log.warn("Save inventory thread exited, restarting")
    start_thread
  end

  def save_inventory(persister)
    save_inventory_start_time = Time.now.utc
    persister.persist!
    update_ems_refresh_stats(persister.manager)
    post_refresh(persister.manager, save_inventory_start_time)
  rescue => err
    log_header = log_header_for_ems(persister.manager)

    _log.error("#{log_header} Save Inventory failed")
    _log.log_backtrace(err)

    update_ems_refresh_stats(persister.manager, :error => err.to_s)
  end

  def update_ems_refresh_stats(ems, error: nil)
    ems.update(:last_refresh_error => error, :last_refresh_date => Time.now.utc)
  end

  def post_refresh(ems, save_inventory_start_time)
    log_header = log_header_for_ems(ems)

    # Do any post-operations for this EMS
    post_process_refresh_classes.each do |klass|
      next unless klass.respond_to?(:post_refresh_ems)
      _log.info("#{log_header} Performing post-refresh operations for #{klass} instances...")
      klass.post_refresh_ems(ems.id, save_inventory_start_time)
      _log.info("#{log_header} Performing post-refresh operations for #{klass} instances...Complete")
    end
  end

  def post_process_refresh_classes
    [VmOrTemplate]
  end

  def log_header_for_ems(ems)
    "EMS: [#{ems.name}], id: [#{ems.id}]"
  end
end
