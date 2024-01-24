module ManageIQ::Providers::Vmware::InfraManager::Template::Operations
  extend ActiveSupport::Concern

  included do
    supports :terminate do
      if retired?
        _('The VM is retired')
      elsif terminated?
        _('The VM is terminated')
      elsif disconnected?
        _('The VM does not have a valid connection state')
      elsif !has_active_ems?
        _("The VM is not connected to an active Provider")
      end
    end
  end
end
