class ManageIQ::Providers::Vmware::InfraManager::MetricsCollectorWorker::Runner < ManageIQ::Providers::BaseManager::MetricsCollectorWorker::Runner
  def do_before_work_loop
    MiqVim.cacheScope = :cache_scope_core
  end

  def before_exit(_message, _exit_code)
    ManageIQ::Providers::Vmware::InfraManager.disconnect_all
  end
end
