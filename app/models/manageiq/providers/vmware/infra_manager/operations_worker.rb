class ManageIQ::Providers::Vmware::InfraManager::OperationsWorker < ManageIQ::Providers::BaseManager::OperationsWorker
  require_nested :Runner

  def self.connect_params(ems)
    {
      :server   => ems.hostname,
      :username => ems.authentication_userid,
      :password => ems.authentication_password,
    }
  end
end
