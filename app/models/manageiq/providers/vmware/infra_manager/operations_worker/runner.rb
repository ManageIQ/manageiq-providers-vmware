class ManageIQ::Providers::Vmware::InfraManager::OperationsWorker::Runner < ::MiqWorker::Runner
  OPTIONS_PARSER_SETTINGS = ::MiqWorker::Runner::OPTIONS_PARSER_SETTINGS + [
    [:ems_id, 'EMS Instance ID', String],
  ]

  def do_work
  end
end
