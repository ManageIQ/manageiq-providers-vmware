class ManageIQ::Providers::Vmware::InfraManager::Inventory::Saver
  include Vmdb::Logging

  def initialize(threaded: true)
    @join_limit  = 30
    @queue       = Queue.new
    @should_exit = false
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

    @should_exit = true
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
    loop do
      while (persister = dequeue)
        save_inventory(persister)
      end

      break if should_exit

      sleep(5)
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

  def dequeue
    queue.deq(:non_block => true)
  rescue ThreadError
  end

  def save_inventory(persister)
    persister.persist!
  end
end
