class ManageIQ::Providers::Vmware::InfraManager::Template < ManageIQ::Providers::InfraManager::Template
  include ManageIQ::Providers::Vmware::InfraManager::VmOrTemplateShared
  include Scanning

  supports :provisioning do
    if ext_management_system
      ext_management_system.unsupported_reason(:provisioning)
    else
      _('not connected to ems')
    end
  end

  supports :terminate
  supports :rename
  supports :set_description
end
