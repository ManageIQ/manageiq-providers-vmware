class ManageIQ::Providers::Vmware::InfraManager::OperationsWorker::Runner < ManageIQ::Providers::BaseManager::OperationsWorker::Runner
  def do_before_work_loop
    # Set the cache_scope to minimal for ems_operations
    MiqVim.cacheScope = :cache_scope_core

    # Prime the cache before starting the do_work loop
    ems.connect
  end

  def before_exit(_message, _exit_code)
    Thread.current[:miq_vim].each_value do |vim|
      begin
        vim.disconnect
      rescue => err
      end
    end
  end
end
