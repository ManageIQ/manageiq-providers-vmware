class ManageIQ::Providers::Vmware::InfraManager::OperationsWorker < MiqWorker
  require_nested :Runner

  include PerEmsWorkerMixin

  self.required_roles = ["ems_metrics_collector", "ems_operations"]

  def friendly_name
    @friendly_name ||= begin
      ems = ext_management_system
      if ems.nil?
        queue_name.titleize
      else
        _("EMS Operations Worker for Provider: %{name}") % {:name => ems.name}
      end
    end
  end

  def self.ems_class
    parent
  end
end
