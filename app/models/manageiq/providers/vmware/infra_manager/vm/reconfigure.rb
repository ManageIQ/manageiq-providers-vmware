module ManageIQ::Providers::Vmware::InfraManager::Vm::Reconfigure
  # Show Reconfigure VM task
  def reconfigurable?
    true
  end

  def max_total_vcpus
    host ? [host.hardware.cpu_total_cores, max_total_vcpus_by_version].min : max_total_vcpus_by_version
  end

  def max_total_vcpus_by_version
    case hardware.virtual_hw_version
    when "04"       then 4
    when "07"       then 8
    when "08"       then 32
    when "09", "10" then 64
    when "11"       then 128
    else
      _log.warn("Add support for new hardware version [#{hardware.virtual_hw_version}].")
      128
    end
  end

  def max_cpu_cores_per_socket(_total_vcpus = nil)
    case hardware.virtual_hw_version
    when "04"       then 1
    when "07"       then 8
    when "08"       then 32
    when "09", "10" then 64
    when "11"       then 128
    else
      _log.warn("Add support for new hardware version [#{hardware.virtual_hw_version}].")
      128
    end
  end

  def max_vcpus
    max_total_vcpus
  end

  def max_memory_mb
    case hardware.virtual_hw_version
    when "04"             then   64.gigabyte / 1.megabyte
    when "07"             then  255.gigabyte / 1.megabyte
    when "08", "09", "10" then 1011.gigabyte / 1.megabyte
    when "11"             then    4.terabyte / 1.megabyte
    else
      _log.warn("Add support for new hardware version [#{hardware.virtual_hw_version}].")
      4.terabyte / 1.megabyte
    end
  end

  def validate_config_spec(options)
    # Check hot-plug settings if the VM is on
    if power_state == "on"
      if options[:number_of_cpus]
        number_of_cpus   = options[:number_of_cpus].to_i
        cores_per_socket = options[:cores_per_socket].to_i

        raise MiqException::MiqVmError, "CPU Hot-Add not enabled"                            if number_of_cpus > cpu_total_cores && !cpu_hot_add_enabled
        raise MiqException::MiqVmError, "Cannot remove CPUs from a running VM"               if number_of_cpus < cpu_total_cores && !cpu_hot_remove_enabled
        raise MiqException::MiqVmError, "Cannot change CPU cores per socket on a running VM" if cores_per_socket != cpu_cores_per_socket
      end

      if options[:vm_memory]
        vm_memory = options[:vm_memory].to_i

        raise MiqException::MiqVmError, "Memory Hot-Add not enabled"                                if vm_memory > ram_size && !memory_hot_add_enabled
        raise MiqException::MiqVmError, "Cannot add more than #{memory_hot_add_limit}MB to this VM" if vm_memory > ram_size && vm_memory > memory_hot_add_limit
        raise MiqException::MiqVmError, "Cannot remove memory from a running VM"                    if vm_memory < ram_size
      end
    end
  end

  def build_config_spec(options)
    validate_config_spec(options)

    VimHash.new("VirtualMachineConfigSpec") do |vmcs|
      case hardware.virtual_hw_version
      when "07"
        ec =  VimArray.new('ArrayOfOptionValue')
        ec << VimHash.new('OptionValue') do |ov|
          ov.key   = "cpuid.coresPerSocket"
          ov.value = VimString.new(options[:cores_per_socket].to_s, nil, "xsd:string")
        end
        vmcs.extraConfig = ec
      else
        set_spec_option(vmcs, :numCoresPerSocket, options[:cores_per_socket], :to_i)
      end
      set_spec_option(vmcs, :memoryMB, options[:vm_memory],      :to_i)
      set_spec_option(vmcs, :numCPUs,  options[:number_of_cpus], :to_i)

      if options[:disk_remove] || options[:disk_add] || options[:disk_resize] || options[:network_adapter_add] || options[:network_adapter_remove]
        with_provider_object do |vim_obj|
          hardware = vim_obj.getHardware

          remove_disks(vim_obj, vmcs, hardware, options[:disk_remove]) if options[:disk_remove]
          resize_disks(vim_obj, vmcs, hardware, options[:disk_resize]) if options[:disk_resize]
          add_disks(vim_obj, vmcs, hardware, options[:disk_add])       if options[:disk_add]
          remove_network_adapters(vim_obj, vmcs, options[:network_adapter_remove]) if options[:network_adapter_remove]
          add_network_adapters(vim_obj, vmcs, options[:network_adapter_add]) if options[:network_adapter_add]
        end
      end
    end
  end

  def resize_disks(vim_obj, vmcs, hardware, disks)
    disks.each do |disk|
      resize_disk_config_spec(vim_obj, vmcs, hardware, disk)
    end
  end

  def remove_disks(vim_obj, vmcs, hardware, disks)
    disks.each do |disk|
      remove_disk_config_spec(vim_obj, vmcs, hardware, disk)
    end
  end

  def add_disks(vim_obj, vmcs, hardware, disks)
    available_units         = vim_obj.available_scsi_units(hardware)
    available_scsi_buses    = vim_obj.available_scsi_buses(hardware)
    new_scsi_controller_key = -99

    disks.each do |d|
      # Grab the first available unit
      controller_key, unit_number = available_units.shift
      if controller_key.nil?
        # If we need to add a new scsi controller find the next bus number
        new_scsi_bus_number = available_scsi_buses.shift
        break if new_scsi_bus_number.nil? # No more scsi controllers can be added

        # Use the controller type passed in if it is available
        new_scsi_type = d[:new_controller_type]

        # Add a new controller with this reconfig task
        add_scsi_controller(vim_obj, vmcs, hardware, new_scsi_type, new_scsi_bus_number, new_scsi_controller_key)

        # Add all units on the new controller as available
        new_scsi_units = scsi_controller_units(new_scsi_controller_key)
        available_units.concat(new_scsi_units)

        controller_key, unit_number = available_units.shift

        new_scsi_controller_key += 1
      end

      d[:controller_key] = controller_key
      d[:unit_number]    = unit_number

      add_disk_config_spec(vmcs, d)
    end
  end

  def remove_network_adapters(vim_obj, vmcs, network_adapters)
    network_adapters.each do |n|
      remove_network_adapter_config_spec(vim_obj, vmcs, n)
    end
  end


  def add_network_adapters(vim_obj, vmcs, network_adapters)
    network_adapters.each do |n|
      add_network_adapter_config_spec(vmcs, n)
    end
  end

  def scsi_controller_units(controller_key)
    [*0..6, *8..15].each.collect do |unit_number|
      [controller_key, unit_number]
    end
  end

  def add_scsi_controller(vim_obj, vmcs, hardware, device_type, bus_number, dev_key)
    device_type ||= get_new_scsi_controller_device_type(vim_obj, hardware)
    add_device_config_spec(vmcs, VirtualDeviceConfigSpecOperation::Add) do |vdcs|
      vdcs.device = VimHash.new(device_type) do |dev|
        dev.sharedBus = VimString.new('noSharing', 'VirtualSCSISharing')
        dev.busNumber = bus_number
        dev.key       = dev_key
      end
    end
  end

  def scsi_controller_types
    %w(VirtualLsiLogicController ParaVirtualSCSIController VirtualBusLogicController VirtualLsiLogicSASController)
  end

  def scsi_controller_default_type
    'VirtualLsiLogicController'
  end

  def get_new_scsi_controller_device_type(vim_obj, hardware)
    scsi_controllers = vim_obj.getScsiControllers(hardware)

    last_scsi_controller = scsi_controllers.sort_by { |c| c["key"].to_i }.last
    device_type = last_scsi_controller.try(:xsiType) || scsi_controller_default_type

    device_type
  end

  def backing_filename
    # create the new disk in the same datastore as the primary disk or the VM's config file
    datastore = hardware.disks.order(:location).find_by(:device_type => 'disk').try(:storage) || storage
    "[#{datastore.name}]"
  end

  def disk_mode(dependent, persistent)
    if dependent
      persistent ? VirtualDiskMode::Persistent : VirtualDiskMode::Nonpersistent
    else
      persistent ? VirtualDiskMode::Independent_persistent : VirtualDiskMode::Independent_nonpersistent
    end
  end

  def validate_device_backing(backing)
    case backing.xsiType
    when 'VirtualDiskFlatVer2BackingInfo'
      valid_flat_ver_2_backing_modes = [
        VirtualDiskMode::Persistent,
        VirtualDiskMode::Independent_persistent,
        VirtualDiskMode::Independent_nonpersistent
      ].freeze

      unless valid_flat_ver_2_backing_modes.include?(backing.diskMode)
        raise MiqException::MiqVmError, "Disk mode #{backing.diskMode} is not supported for virtual disk"
      end
    end
  end

  def validate_device(device)
    validate_device_backing(device.backing)
  end

  def add_disk_config_spec(vmcs, options)
    raise "#{__method__}: Disk size is required to add a new disk." unless options[:disk_size_in_mb]

    options.reverse_merge!(:thin_provisioned => true, :dependent => true, :persistent => true)

    add_device_config_spec(vmcs, VirtualDeviceConfigSpecOperation::Add) do |vdcs|
      vdcs.fileOperation = VirtualDeviceConfigSpecFileOperation::Create
      vdcs.device = VimHash.new("VirtualDisk") do |dev|
        dev.key            = -100 * options[:unit_number]  # temp key for creation
        dev.capacityInKB   = options[:disk_size_in_mb].to_i * 1024
        dev.controllerKey  = options[:controller_key]
        dev.unitNumber     = options[:unit_number]

        dev.connectable = VimHash.new("VirtualDeviceConnectInfo") do |con|
          con.allowGuestControl = "false"
          con.startConnected    = "true"
          con.connected         = "true"
        end

        dev.backing = VimHash.new("VirtualDiskFlatVer2BackingInfo") do |bck|
          bck.diskMode        = disk_mode(options[:dependent], options[:persistent])
          bck.thinProvisioned = options[:thin_provisioned]
          bck.fileName        = backing_filename
        end
      end

      validate_device(vdcs.device)
    end
  end

  def add_network_adapter_config_spec(vmcs, options)
    add_device_config_spec(vmcs, VirtualDeviceConfigSpecOperation::Add) do |vdcs|
      vdcs.device = VimHash.new("VirtualVmxnet3") do |dev|
        dev.key = rand(-9999..-100) # negative integer as temporary key
        dev.unitNumber = 0
        dev.addressType = "Generated"
        dev.wakeOnLanEnabled = "true"
        dev.connectable = VimHash.new("VirtualDeviceConnectInfo") do |con|
          con.allowGuestControl = "true"
          con.connected = "true"
          con.startConnected = "true"
        end
        dev.backing = VimHash.new("VirtualEthernetCardDistributedVirtualPortBackingInfo") do |bck|
          bck.port = VimHash.new("DistributedVirtualSwitchPortConnection") do |pc|

            # A DistributedVirtualPortgroup name is unique in a datacenter so look for a Lan with this name
            # on all switches in the cluster
            lan = Lan.find_by(:name => options[:network], :switch_id => HostSwitch.where(:host_id => host).pluck(:switch_id))

            pc.switchUuid = lan.switch.switch_uuid
            pc.portgroupKey = lan.uid_ems
          end
        end
      end
    end
  end

  def remove_disk_config_spec(vim_obj, vmcs, hardware, options)
    raise "remove_disk_config_spec: disk filename is required." unless options[:disk_name]

    options.reverse_merge!(:delete_backing => false)
    controller_key, key = vim_obj.getDeviceKeysByBacking(options[:disk_name], hardware)
    raise "remove_disk_config_spec: no virtual device associated with: #{options[:disk_name]}" unless key

    add_device_config_spec(vmcs, VirtualDeviceConfigSpecOperation::Remove) do |vdcs|
      vdcs.fileOperation = VirtualDeviceConfigSpecFileOperation::Destroy if options[:delete_backing]
      vdcs.device = VimHash.new("VirtualDisk") do |dev|
        dev.key           = key
        dev.capacityInKB  = 0
        dev.controllerKey = controller_key

        dev.connectable = VimHash.new("VirtualDeviceConnectInfo") do |con|
          con.allowGuestControl = "false"
          con.startConnected    = "true"
          con.connected         = "true"
        end
      end
    end
  end

  def resize_disk_config_spec(vim_obj, vmcs, hardware, options)
    raise "resize_disk_config_spec: disk filename is required." unless options[:disk_name]

    device = vim_obj.getDeviceByBacking(options[:disk_name], hardware)
    raise "resize_disk_config_spec: no virtual device associated with: #{options[:disk_name]}" unless device
    new_capacity_in_kb = options[:disk_size_in_mb].to_i * 1024
    raise "resize_disk_config_spec: decrease size is not supported for: #{options[:disk_name]}" unless device.capacityInKB.to_i <= new_capacity_in_kb

    add_device_config_spec(vmcs, VirtualDeviceConfigSpecOperation::Edit) do |vdcs|
      vdcs.device = VimHash.new("VirtualDisk") do |dev|
        dev.key           = device.key
        dev.capacityInKB  = new_capacity_in_kb
        dev.controllerKey = device.controllerKey
        dev.unitNumber    = device.unitNumber
        dev.backing       = device.backing
      end
    end
  end

  def remove_network_adapter_config_spec(vim_obj, vmcs, options)
    raise "remove_network_adapter_config_spec: network_adapter name is required." unless options[:network][:name]
    networkName = options[:network][:name]
    controller_key, key, unitNumber = vim_obj.send(:getDeviceKeysByNetwork, networkName)
    add_device_config_spec(vmcs, VirtualDeviceConfigSpecOperation::Remove) do |vdcs|
      vdcs.device = VimHash.new("VirtualEthernetCard") do |dev|
        dev.key = key
        dev.controllerKey = controller_key
        dev.unitNumber =  unitNumber
      end
    end
  end

  def add_device_config_spec(vmcs, operation)
    vmcs_vca = vmcs.deviceChange ||= VimArray.new('ArrayOfVirtualDeviceConfigSpec')
    vmcs_vca << VimHash.new('VirtualDeviceConfigSpec') do |vdcs|
      vdcs.operation = operation
      yield(vdcs)
    end
  end

  # Set the value if it is not nil
  def set_spec_option(obj, property, value, modifier = nil)
    unless value.nil?
      # Modifier is a method like :to_s or :to_i
      value = value.to_s if [true, false].include?(value)
      value = value.send(modifier) unless modifier.nil?
      _log.info "#{property} was set to #{value} (#{value.class})"
      obj.send("#{property}=", value)
    else
      value = obj.send(property.to_s)
      if value.nil?
        _log.info "#{property} was NOT set due to nil"
      else
        _log.info "#{property} inheriting value from spec: #{value} (#{value.class})"
      end
    end
  end
end
