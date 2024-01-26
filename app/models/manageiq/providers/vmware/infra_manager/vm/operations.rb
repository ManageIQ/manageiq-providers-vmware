module ManageIQ::Providers::Vmware::InfraManager::Vm::Operations
  extend ActiveSupport::Concern
  include Guest
  include Snapshot

  included do
    supports :terminate do
      if !supports?(:control)
        unsupported_reason(:control)
      elsif power_state != "off"
        _('The VM is not powered off')
      end
    end
  end
end
