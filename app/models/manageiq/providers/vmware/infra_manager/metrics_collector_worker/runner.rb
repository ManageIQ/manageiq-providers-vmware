class ManageIQ::Providers::Vmware::InfraManager::MetricsCollectorWorker::Runner < ManageIQ::Providers::BaseManager::MetricsCollectorWorker::Runner
  def do_before_work_loop
    require "VMwareWebService/MiqVim"
    MiqVim.cacheScope = :cache_scope_core
    MiqVim.on_log_body { |body| $vim_log.debug(body) } if Settings.ems.ems_vmware.debug_vim_requests
  end

  def before_exit(_message, _exit_code)
    ManageIQ::Providers::Vmware::InfraManager.disconnect_all
  end
end
