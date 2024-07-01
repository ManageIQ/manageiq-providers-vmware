module ManageIQ::Providers::Vmware::InfraManager::Vm::Operations::Guest
  extend ActiveSupport::Concern

  included do
    supports :reboot_guest do
      if current_state != "on"
        _("The VM is not powered on")
      elsif tools_status == 'toolsNotInstalled'
        _("The VM tools is not installed")
      else
        unsupported_reason(:control)
      end
    end

    supports :shutdown_guest do
      if current_state != "on"
        _("The VM is not powered on")
      elsif tools_status == 'toolsNotInstalled'
        _("The VM tools is not installed")
      else
        unsupported_reason(:control)
      end
    end

    supports :reset do
      if current_state != "on"
        _("The VM is not powered on")
      else
        unsupported_reason(:control)
      end
    end

    supports :standby_guest do
      if current_state != "on"
        _("The VM is not powered on")
      else
        unsupported_reason(:control)
      end
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
