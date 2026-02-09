module ManageIQ::Providers::Vmware::InfraManager::Provision::Configuration::Network
  def build_config_network_adapters(vmcs)
    requested_networks = normalize_network_adapter_settings
    template_networks  = get_network_adapters

    if requested_networks.blank?
      options[:requested_network_adapter_count] = template_networks.length
      _log.warn "VLan options is nil.  VLan settings will be inherited from the template."
    else
      options[:requested_network_adapter_count] = requested_networks.length
      requested_networks.each_with_index do |net, idx|
        vim_net_adapter = template_networks[idx]

        if net[:is_dvs] || net[:is_opaque]
          build_config_spec_advanced_lan(net, vim_net_adapter, vmcs)
        else
          build_config_spec_vlan(net, vim_net_adapter, vmcs)
        end
      end

      # Remove any unneeded template networks
      # Use Array.wrap to handle cases where more networks are requested than exist on the source VM
      # in which case the array [length..-1] logic will return nil.  (So please do not remove it...again.)
      Array.wrap(template_networks[requested_networks.length..-1]).each do |vim_net_adapter|
        build_config_spec_delete_existing_vlan(vmcs, vim_net_adapter)
      end
    end
  end

  def normalize_network_adapter_settings
    options[:networks] = Array(options[:networks])

    if options[:networks].first.blank?
      convert_vlan_options_to_network_hash
    else
      convert_network_hash_to_vlan_options
    end
    options[:networks]
  end

  def build_config_spec_vlan(network, vnicDev, vmcs)
    target_type = network[:devicetype]
    is_e1000_target = ['VirtualE1000', 'VirtualE1000e'].include?(target_type.to_s)

    # e1000-specific handling is needed in vSphere 8 due to strict schema validation enforcement.
    # 'uptCompatibilityEnabled' is a valid property for VMXNET3 but INVALID for e1000/e1000e.
    # When cloning a VMXNET3 template to an e1000 VM, the standard 'Edit' operation inherits this property
    # from the source, causing an "Invalid configuration for device '0'" error.
    #
    # Technically, uptCompatibilityEnabled existing with a 'false' value would not break things in the current
    # version of the vSphere API. However, due to the VirtualE1000 schema not containing uptCompatibilityEnabled,
    # we should prevent it for all e1000 target NICs.
    #
    # We cannot simply 'edit' the device because vCenter persists uptCompatibilityEnabled (even after attempting to delete the key prior).
    # We must explicitly REMOVE the old VMXNET3 device and ADD a fresh e1000 device.
    upt_enabled_in_source = false
    if vnicDev
      if vnicDev.respond_to?(:uptCompatibilityEnabled)
        upt_enabled_in_source = true
      elsif vnicDev.kind_of?(Hash) && (vnicDev.key?('uptCompatibilityEnabled') || vnicDev.key?(:uptCompatibilityEnabled))
        upt_enabled_in_source = true
      end
    end

    if is_e1000_target && upt_enabled_in_source
      _log.info("[NIC-FIX] DETECTED UPT_COMPATIBILITY_ENABLED INHERITANCE FOR VMXNET3 -> #{target_type}. Switching to REMOVE + ADD strategy.")

      # REMOVE the old device
      add_device_config_spec(vmcs, VirtualDeviceConfigSpecOperation::Remove) do |vdcs|
        vdcs.device = vnicDev
      end

      # ADD the new device (fresh object to ensure no uptCompatibilityEnabled key)
      add_device_config_spec(vmcs, VirtualDeviceConfigSpecOperation::Add) do |vdcs|
        vdcs.device = VimHash.new(target_type) do |dev|
          dev.key = -1 # tells vCenter to create a new device

          dev.deviceInfo = VimHash.new('Description') do |info|
            info.label = vnicDev['deviceInfo']['label'] rescue "Network Adapter"
            info.summary = "Network Adapter"
          end

          # standard connectivity settings
          dev.connectable = vnicDev['connectable'] rescue vnicDev.connectable
          dev.wakeOnLanEnabled = vnicDev['wakeOnLanEnabled'] rescue vnicDev.wakeOnLanEnabled

          # IMPT: preserve MAC address
          dev.macAddress = vnicDev['macAddress'] rescue vnicDev.macAddress
          dev.addressType = vnicDev['addressType'] rescue vnicDev.addressType

          ext_id = vnicDev['externalId'] rescue (vnicDev.externalId rescue nil)
          if ext_id
            dev.externalId = ext_id
          end
        end

        # Apply Backing
        set_backing_standard(vdcs.device, network)
      end

    else
      # STANDARD PATH
      # Used for:
      # 1. New NICs (Add)
      # 2. Same-driver updates (VMXNET3->VMXNET3 or E1000->E1000)
      # 3. E1000->VMXNET3 (Safe because VMXNET3 supports the properties E1000 lacks)
      operation = vnicDev.nil? ? VirtualDeviceConfigSpecOperation::Add : VirtualDeviceConfigSpecOperation::Edit
      add_device_config_spec(vmcs, operation) do |vdcs|
        vdcs.device = vnicDev ? edit_vlan_device(network, vnicDev) : create_vlan_device(network)

        _log.info "Setting target network device to Device Name:<#{network[:network]}>  Device:<#{vdcs.device.inspect}>"

        set_backing_standard(vdcs.device, network)

        #
        # Manually assign MAC address to target VM.
        #
        mac_addr = network[:mac_address]
        unless mac_addr.blank?
          vdcs.device.macAddress = mac_addr
          vdcs.device.addressType = 'Manual'
        end
      end
    end
  end

  def build_config_spec_advanced_lan(network, vnicDev, vmcs)
    # A DistributedVirtualPortgroup name is unique in a datacenter so look for a Lan with this name
    # on all switches in the cluster
    hosts = dest_cluster.try(:hosts) || dest_host
    lan = Lan.find_by(:name => network[:network], :switch_id => HostSwitch.where(:host_id => hosts).pluck(:switch_id))

    raise MiqException::MiqProvisionError, "Port group [#{network[:network]}] is not available on target" if lan.nil?
    _log.info("portgroupName: #{lan.name}, portgroupKey: #{lan.uid_ems}, switchUuid: #{lan.switch.switch_uuid}")

    target_type = network[:devicetype]
    is_e1000_target = ['VirtualE1000', 'VirtualE1000e'].include?(target_type.to_s)

    # e1000-specific handling is needed in vSphere 8 due to strict schema validation enforcement.
    # 'uptCompatibilityEnabled' is a valid property for VMXNET3 but INVALID for e1000/e1000e.
    # When cloning a VMXNET3 template to an e1000 VM, the standard 'Edit' operation inherits this property
    # from the source, causing an "Invalid configuration for device '0'" error.
    #
    # Technically, uptCompatibilityEnabled existing with a 'false' value would not break things in the current
    # version of the vSphere API. However, due to the VirtualE1000 schema not containing uptCompatibilityEnabled,
    # we should prevent it for all e1000 target NICs.
    #
    # We cannot simply 'edit' the device because vCenter persists uptCompatibilityEnabled (even after attempting to delete the key prior).
    # We must explicitly REMOVE the old VMXNET3 device and ADD a fresh e1000 device.
    upt_enabled_in_source = false
    if vnicDev
      if vnicDev.respond_to?(:uptCompatibilityEnabled)
        upt_enabled_in_source = true
      elsif vnicDev.kind_of?(Hash) && (vnicDev.key?('uptCompatibilityEnabled') || vnicDev.key?(:uptCompatibilityEnabled))
        upt_enabled_in_source = true
      end
    end

    if is_e1000_target && upt_enabled_in_source
      _log.info("[NIC-FIX] DETECTED UPT_COMPATIBILITY_ENABLED INHERITANCE FOR VMXNET3 -> #{target_type}. Switching to REMOVE + ADD strategy.")

      # REMOVE the old device
      add_device_config_spec(vmcs, VirtualDeviceConfigSpecOperation::Remove) do |vdcs|
        vdcs.device = vnicDev
      end

      # ADD the new device (fresh object to ensure no uptCompatibilityEnabled key)
      add_device_config_spec(vmcs, VirtualDeviceConfigSpecOperation::Add) do |vdcs|
        vdcs.device = VimHash.new(target_type) do |dev|
          dev.key = -1 # New Device

          dev.deviceInfo = VimHash.new('Description') do |info|
            info.label = vnicDev['deviceInfo']['label'] rescue "Network Adapter"
            info.summary = "Network Adapter"
          end

          # standard connectivity settings
          dev.connectable = vnicDev['connectable'] rescue vnicDev.connectable
          dev.wakeOnLanEnabled = vnicDev['wakeOnLanEnabled'] rescue vnicDev.wakeOnLanEnabled

          # IMPT: preserve MAC address
          dev.macAddress = vnicDev['macAddress'] rescue vnicDev.macAddress
          dev.addressType = vnicDev['addressType'] rescue vnicDev.addressType

          ext_id = vnicDev['externalId'] rescue (vnicDev.externalId rescue nil)
          if ext_id
            dev.externalId = ext_id
          end
        end

        # Apply Backing
        set_backing_advanced(vdcs.device, network, lan)
      end

    else
      # STANDARD PATH
      # Used for:
      # 1. New NICs (Add)
      # 2. Same-driver updates (VMXNET3->VMXNET3 or E1000->E1000)
      # 3. E1000->VMXNET3 (Safe because VMXNET3 supports the properties E1000 lacks)
      operation = vnicDev.nil? ? VirtualDeviceConfigSpecOperation::Add : VirtualDeviceConfigSpecOperation::Edit
      add_device_config_spec(vmcs, operation) do |vdcs|
        vdcs.device = vnicDev ? edit_vlan_device(network, vnicDev) : create_vlan_device(network)
        _log.info "Setting target network device to Device Name:<#{network[:network]}>  Device:<#{vdcs.device.inspect}>"

        set_backing_advanced(vdcs.device, network, lan)

        #
        # Manually assign MAC address to target VM.
        #
        mac_addr = network[:mac_address]
        unless mac_addr.blank?
          vdcs.device.macAddress = mac_addr
          vdcs.device.addressType = 'Manual'
        end
      end
    end
  end

  def create_vlan_device(network)
    device_type = get_config_spec_value(network, 'VirtualPCNet32', nil, [:devicetype])
    VimHash.new(device_type) do |vDev|
      vDev.key = get_next_device_idx
      vDev.connectable = VimHash.new('VirtualDeviceConnectInfo') do |con|
        con.allowGuestControl = get_config_spec_value(network, 'true', nil, [:connectable, :allowguestcontrol])
        con.startConnected    = get_config_spec_value(network, 'true', nil, [:connectable, :startconnected])
        con.connected         = get_config_spec_value(network, 'true', nil, [:connectable, :connected])
      end
    end
  end

  def edit_vlan_device(network, vnic)
    # If a device type was provided override the type of the existing vnic
    device_type = get_config_spec_value(network, nil, nil, [:devicetype])
    if device_type && vnic.xsiType != device_type
      vnic.xsiType = device_type
    end

    vnic
  end

  def find_dvs_by_name(vim, dvs_name)
    dvs = vim.queryDvsConfigTarget(vim.sic.dvSwitchManager, dest_host.ems_ref_obj, nil) rescue nil
    # List the names of the non-uplink portgroups.
    unless dvs.nil? || dvs.distributedVirtualPortgroup.nil?
      return vim.applyFilter(dvs.distributedVirtualPortgroup, 'portgroupName' => dvs_name, 'uplinkPortgroup' => 'false').first
    end
    nil
  end

  def build_config_spec_delete_existing_vlan(vmcs, net_device)
    add_device_config_spec(vmcs, VirtualDeviceConfigSpecOperation::Remove) do |vdcs|
      _log.info "Deleting network device with Device Name:<#{net_device.fetch_path('deviceInfo', 'label')}>"
      vdcs.device    = net_device
    end
  end

  def get_network_adapters
    inventory_hash = source.with_provider_connection do |vim|
      vim.virtualMachineByMor(source.ems_ref_obj)
    end

    devs = inventory_hash.fetch_path("config", "hardware", "device") || []
    devs.select { |d| d.key?('macAddress') }.sort_by { |d| d['unitNumber'].to_i }
  end

  def get_network_device(vimVm, _vmcs, _vim = nil, vlan = nil)
    svm = source
    nic = svm.hardware.nil? ? nil : svm.hardware.nics.first
    unless nic.nil?
      # if passed a vlan, validate that the target host supports it.
      unless vlan.nil?
        raise MiqException::MiqProvisionError, "vLan [#{vlan}] is not available on target host [#{dest_host.name}]" unless dest_host.lans.any? { |l| l.name == vlan }
      end

      vnicDev = vimVm.devicesByFilter('deviceInfo.label' => nic.device_name).first
      raise MiqException::MiqProvisionError, "Target network device <#{nic.device_name}> was not found." if vnicDev.nil?
      return vnicDev
    else
      if svm.hardware.nil?
        raise MiqException::MiqProvisionError, "Source template does not have a connection to the hardware table."
      else
        raise MiqException::MiqProvisionError, "Source template does not have a nic defined."
      end
    end
  end

  private def convert_vlan_options_to_network_hash
    vlan = get_option(:vlan)
    _log.info("vlan: #{vlan.inspect}")
    return unless vlan

    options[:networks][0] = {:network => vlan}.tap do |net|
      net[:mac_address] = get_option_last(:mac_address) if get_option_last(:mac_address)

      if vlan[0, 4] == 'dvs_'
        # Remove the "dvs_" prefix on the name
        net[:network] = vlan[4..-1]
        net[:is_dvs]  = true
      else
        hosts = dest_cluster.try(:hosts) || dest_host
        lan = Lan.find_by(:name => vlan, :switch_id => HostSwitch.where(:host_id => hosts).pluck(:switch_id))
        net[:is_opaque] = lan.switch.type == ManageIQ::Providers::Vmware::InfraManager::OpaqueSwitch.name unless lan.nil?
      end
    end
  end

  private def convert_network_hash_to_vlan_options
    net = options[:networks].first
    options[:vlan] = [net[:is_dvs] == true ? "dvs_#{net[:network]}" : net[:network], net[:network]]
  end

  # helper for build_config_spec_vlan dup logic
  private def set_backing_standard(device, network)
    device.backing = VimHash.new('VirtualEthernetCardNetworkBackingInfo') do |info|
      info.deviceName = network[:network]
    end
  end

  # helper for build_config_spec_advanced_lan dup logic
  private def set_backing_advanced(device, network, lan)
    #
    # Change the port group of the target VM.
    #
    device.backing = if network[:is_dvs]
      VimHash.new('VirtualEthernetCardDistributedVirtualPortBackingInfo') do |info|
        info.port = VimHash.new('DistributedVirtualSwitchPortConnection') do |conn|
          conn.switchUuid   = lan.switch.switch_uuid
          conn.portgroupKey = lan.uid_ems
        end
      end
    else
      VimHash.new('VirtualEthernetCardOpaqueNetworkBackingInfo') do |info|
        info.opaqueNetworkId = lan.uid_ems
        info.opaqueNetworkType = 'nsx.LogicalSwitch'
      end
    end
  end
end
