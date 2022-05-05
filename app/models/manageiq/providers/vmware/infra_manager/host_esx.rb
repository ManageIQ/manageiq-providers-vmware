class ManageIQ::Providers::Vmware::InfraManager::HostEsx < ManageIQ::Providers::Vmware::InfraManager::Host
  supports :refresh_advanced_settings
  supports :refresh_firewall_rules
  supports :refresh_logs
  supports :reboot { validate_active_with_power_state(:reboot, "on") }
  supports :shutdown { validate_active_with_power_state(:shutdown, "on") }
  supports :standby { validate_active_with_power_state(:standby, "on") }
  supports :enter_maint_mode { validate_active_with_power_state(:enter_maint_mode, "on") }
  supports :exit_maint_mode { validate_active_with_power_state(:exit_maint_mode, "maintenance") }
  supports :enable_vmotion { validate_active_with_power_state(:enable_vmotion, "on") }
  supports :disable_vmotion { validate_active_with_power_state(:disable_vmotion, "on") }
  supports :vmotion { validate_active_with_power_state(:vmotion, "on") }

  def vim_shutdown(force = false)
    with_provider_object do |vim_host|
      _log.info "Invoking with: force: [#{force}]"
      vim_host.shutdownHost(force)
    end
  end

  def vim_reboot(force = false)
    with_provider_object do |vim_host|
      _log.info "Invoking with: force: [#{force}]"
      vim_host.rebootHost(force)
    end
  end

  def vim_enter_maintenance_mode(timeout = 0, evacuate_powered_off_vms = false)
    with_provider_object do |vim_host|
      _log.info "Invoking with: timeout: [#{timeout}], evacuate_powered_off_vms: [#{evacuate_powered_off_vms}]"
      vim_host.enterMaintenanceMode(timeout, evacuate_powered_off_vms)
    end
  end

  def vim_exit_maintenance_mode(timeout = 0)
    with_provider_object do |vim_host|
      _log.info "Invoking with: timeout: [#{timeout}]"
      vim_host.exitMaintenanceMode(timeout)
    end
  end

  def vim_in_maintenance_mode?
    with_provider_object do |vim_host|
      _log.info "Invoking"
      vim_host.inMaintenanceMode?
    end
  end

  def vim_power_down_to_standby(timeout = 0, evacuate_powered_off_vms = false)
    with_provider_object do |vim_host|
      _log.info "Invoking with: timeout: [#{timeout}], evacuate_powered_off_vms: [#{evacuate_powered_off_vms}]"
      vim_host.powerDownHostToStandBy(timeout, evacuate_powered_off_vms)
    end
  end

  def vim_power_up_from_standby(timeout = 0)
    with_provider_object do |vim_host|
      _log.info "Invoking with: timeout: [#{timeout}]"
      vim_host.powerUpHostFromStandBy(timeout)
    end
  end

  def vim_vmotion_enabled?(device = nil)
    with_provider_object do |vim_host|
      vnm      = vim_host.hostVirtualNicManager
      selected = vnm.selectedVnicsByType("vmotion")
      selected = selected.select { |vnic| vnic.device == device } unless device.nil?
      return !selected.empty?
    end
  end

  def vim_enable_vmotion(device = nil)
    with_provider_object do |vim_host|
      vnm      = vim_host.hostVirtualNicManager
      device ||= vnm.candidateVnicsByType("vmotion").first.device rescue nil
      _log.info "Invoking for device=<#{device}>"
      vnm.selectVnicForNicType("vmotion", device) unless device.nil?
    end
  end

  def vim_disable_vmotion(device = nil)
    with_provider_object do |vim_host|
      vnm      = vim_host.hostVirtualNicManager
      device ||= vnm.candidateVnicsByType("vmotion").first.device rescue nil
      _log.info "Invoking for device=<#{device}>"
      vnm.deselectVnicForNicType("vmotion", device) unless device.nil?
    end
  end

  def get_host_virtual_nic_manager_with_vmotion_device(vim_host, device = nil)
    vnm = vim_host.hostVirtualNicManager
    device ||= vnm.candidateVnicsByType("vmotion").first.device rescue nil
    return vnm, device
  end

  def vim_firewall_rules
    data = {'config' => {}}
    with_provider_object do |vim_host|
      fws = vim_host.firewallSystem
      return [] if fws.nil?
      data['config']['firewall'] = fws.firewallInfo
    end

    ManageIQ::Providers::Vmware::InfraManager::RefreshParser.host_inv_to_firewall_rules_hashes(data)
  end

  def vim_advanced_settings
    data = {'config' => {}}
    with_provider_object do |vim_host|
      aom = vim_host.advancedOptionManager
      return nil if aom.nil?
      data['config']['option'] = aom.setting
      data['config']['optionDef'] = aom.supportedOption
    end

    ManageIQ::Providers::Vmware::InfraManager::RefreshParser.host_inv_to_advanced_settings_hashes(data)
  end

  def verify_credentials_with_ws(auth_type = nil)
    raise "No credentials defined" if self.missing_credentials?(auth_type)

    begin
      with_provider_connection(:use_broker => false, :auth_type => auth_type) {}
    rescue SocketError, Errno::EHOSTUNREACH, Errno::ENETUNREACH => err
      raise MiqException::MiqUnreachableError, err.message
    rescue Handsoap::Fault => err
      _log.warn(err.inspect)
      if err.respond_to?(:reason)
        raise MiqException::MiqInvalidCredentialsError, err.reason if err.reason =~ /Authorize Exception|incorrect user name or password/
        raise err.reason
      end
      raise err.message
    rescue Exception => err
      _log.warn(err.inspect)
      raise "Unexpected response returned from system, see log for details"
    else
      true
    end
  end

  def refresh_logs
    if self.missing_credentials?
      _log.warn "No credentials defined for Host [#{name}]"
      return
    end

    begin
      vim = connect
      unless vim.nil?
        sp = HostScanProfiles.new(ScanItem.get_profile("host default"))
        hashes = sp.parse_data_hostd(vim)
        EventLog.add_elements(self, hashes)
      end
    rescue Timeout::Error
      _log.warn "Timeout encountered during log collection for Host [#{name}]"
    rescue => err
      _log.log_backtrace(err)
    ensure
      vim.disconnect rescue nil
    end
  end

  def refresh_firewall_rules
    return if ext_management_system.nil? || operating_system.nil?

    fwh = vim_firewall_rules
    return if fwh.nil?

    FirewallRule.add_elements(self, fwh)
    operating_system.try(:save)
  end

  def refresh_advanced_settings
    return if ext_management_system.nil?

    ash = vim_advanced_settings
    AdvancedSetting.add_elements(self, ash) unless ash.nil?
  end

  def self.display_name(number = 1)
    n_('Host (Vmware)', 'Hosts (Vmware)', number)
  end

  def thumbprint_sha1
    require 'VMwareWebService/esx_thumb_print'
    ESXThumbPrint.new(ipaddress, authentication_userid, authentication_password).to_sha1
  end

  private

  def validate_active_with_power_state(feature, expected_power_state)
    return unsupported_reason_add(feature, _("The Host is not connected to an active Provider"))   unless has_active_ems?
    return unsupported_reason_add(feature, _("The host is not powered '#{expected_power_state}'")) unless expected_power_state == power_state
  end
end
