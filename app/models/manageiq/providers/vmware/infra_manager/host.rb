class ManageIQ::Providers::Vmware::InfraManager::Host < ::Host
  include ManageIQ::Providers::Vmware::InfraManager::VimConnectMixin
  include ManageIQ::Providers::Vmware::InfraManager::EmsRefObjMixin

  supports :capture

  # overrides base start to support "standby" powerstate
  supports :start do
    if !supports?(:ipmi)
      unsupported_reason_add(:start, unsupported_reason(:ipmi))
    elsif %w[off standby].exclude?(power_state)
      unsupported_reason_add(:start, _("The Host is not in power state off or standby"))
    end
  end

  def connect(options = {})
    vim_connect(options)
  end

  def start
    if verbose_supports?(:start)
      if power_state == 'standby'
        check_policy_prevent("request_host_start", "vim_power_up_from_standby")
      else
        super
      end
    end
  end

  def provider_object(connection)
    api_type = connection.about["apiType"]
    mor =
      case api_type
      when "VirtualCenter"
        # The ems_ref in the VMDB is from the vCenter perspective
        ems_ref
      when "HostAgent"
        # Since we are going directly to the host, it acts like a VC
        # Thus, there is only a single host in it
        # It has a MOR for itself, which is different from the vCenter MOR
        connection.hostSystemsByMor.keys.first
      else
        raise "Unknown connection API type '#{api_type}'"
      end

    connection.getVimHostByMor(mor)
  end

  def provider_object_release(handle)
    handle.release if handle rescue nil
  end

  def refresh_files_on_datastore(datastore)
    raise _("Host must be connected to an EMS to refresh datastore files") if ext_management_system.nil?
    ext_management_system.refresh_files_on_datastore(datastore)
  end

  def reserve_next_available_vnc_port
    port_start = ext_management_system.try(:host_default_vnc_port_start).try(:to_i) || 5900
    port_end   = ext_management_system.try(:host_default_vnc_port_end).try(:to_i) || 5999

    lock do
      port = next_available_vnc_port
      port = port_start unless port.in?(port_start..port_end)

      next_port = (port == port_end ? port_start : port + 1)
      update(:next_available_vnc_port => next_port)

      port
    end
  end

  def detect_discovered_hypervisor(_ost, ipaddr)
    find_method = :find_by_ipaddress

    self.name        = "VMware ESX Server (#{ipaddr})"
    self.ipaddress   = ipaddr
    self.vmm_vendor  = "vmware"
    self.vmm_product = "Esx"
    if has_credentials?(:ws)
      begin
        with_provider_connection(:ip => ipaddr) do |vim|
          _log.info("VIM Information for ESX Host with IP Address: [#{ipaddr}], Information: #{vim.about.inspect}")
          self.vmm_product     = vim.about['name'].dup.split(' ').last
          self.vmm_version     = vim.about['version']
          self.vmm_buildnumber = vim.about['build']
          self.name            = "#{vim.about['name']} (#{ipaddr})"
        end
      rescue => err
        _log.warn("Cannot connect to ESX Host with IP Address: [#{ipaddr}], Username: [#{authentication_userid(:ws)}] because #{err.message}")
      end
    end
    self.type = %w(esx esxi).include?(vmm_product.to_s.downcase) ? "ManageIQ::Providers::Vmware::InfraManager::HostEsx" : "ManageIQ::Providers::Vmware::InfraManager::Host"

    find_method
  end

  supports :quick_stats

  def self.display_name(number = 1)
    n_('Host (Vmware)', 'Hosts (Vmware)', number)
  end
end
