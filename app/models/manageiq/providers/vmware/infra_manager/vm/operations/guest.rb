module ManageIQ::Providers::Vmware::InfraManager::Vm::Operations::Guest
  extend ActiveSupport::Concern

  included do
    supports :reboot_guest do
      unsupported_reason_add(:reboot_guest, unsupported_reason(:control)) unless supports?(:control)
      if current_state == "on"
        if tools_status == 'toolsNotInstalled'
          unsupported_reason_add(:reboot_guest, _("The VM tools is not installed"))
        end
      else
        unsupported_reason_add(:reboot_guest, _("The VM is not powered on"))
      end
    end

    supports :shutdown_guest do
      unsupported_reason_add(:shutdown_guest, unsupported_reason(:control)) unless supports?(:control)
      if current_state == "on"
        if tools_status == 'toolsNotInstalled'
          unsupported_reason_add(:shutdown_guest, _("The VM tools is not installed"))
        end
      else
        unsupported_reason_add(:shutdown_guest, _("The VM is not powered on"))
      end
    end

    supports :reset do
      reason   = unsupported_reason(:control) unless supports?(:control)
      reason ||= _("The VM is not powered on") unless current_state == "on"
      unsupported_reason_add(:reset, reason) if reason
    end

    supports :standby_guest do
      reason   = unsupported_reason(:control) unless supports?(:control)
      reason ||= _("The VM is not powered on") unless current_state == "on"
      unsupported_reason_add(:standby_guest, reason) if reason
    end
  end

  def raw_shutdown_guest
    run_command_via_parent(:vm_shutdown_guest)
  end

  def raw_standby_guest
    run_command_via_parent(:vm_standby_guest)
  end

  def raw_reboot_guest
    run_command_via_parent(:vm_reboot_guest)
  end

  def raw_reset
    run_command_via_parent(:vm_reset)
  end
end
