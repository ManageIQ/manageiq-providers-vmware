class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  module VirtualMachine
    def parse_virtual_machine_config(vm_hash, props)
      config = props[:config]
      return if config.nil?

      affinity_set = config.fetch_path(:cpuAffinity, :affinitySet)

      cpu_affinity = nil
      cpu_affinity = affinity_set.kind_of?(Array) ? affinity_set.join(",") : affinity_set.to_s if affinity_set

      vm_hash[:cpu_affinity] = cpu_affinity

      standby_act = config.fetch_path(:defaultPowerOps, :standbyAction)
      vm_hash[:standby_action] = standby_act unless standby_act.nil?
      vm_hash[:cpu_hot_add_enabled] = config[:cpuHotAddEnabled]
      vm_hash[:cpu_hot_remove_enabled] = config[:cpuHotRemoveEnabled]
      vm_hash[:memory_hot_add_enabled] = config[:memoryHotAddEnabled]
      vm_hash[:memory_hot_add_limit] = config[:hotPlugMemoryLimit]
      vm_hash[:memory_hot_add_increment] = config[:hotPlugMemoryIncrementSize]
    end

    def parse_virtual_machine_summary(vm_hash, props)
      summary = props[:summary]
      return if summary.nil?

      summary_config = summary[:config]
      if summary_config
        uuid = summary_config[:uuid]
        unless uuid.blank?
          vm_hash[:uid_ems] = MiqUUID.clean_guid(uuid) || uuid
        end

        name = summary_config[:name]
        vm_hash[:name] = CGI.unescape(name) if name

        pathname = summary_config[:vmPathName]
        begin
          _storage_name, location = VmOrTemplate.repository_parse_path(pathname)
        rescue
          location = VmOrTemplate.location2uri(pathname)
        end
        vm_hash[:location] = location

        template = summary_config[:template]
        type = "ManageIQ::Providers::Vmware::InfraManager::#{template ? "Template" : "Vm"}"

        vm_hash[:type]     = type
        vm_hash[:template] = template
      end

      summary_guest = summary[:guest]
      if summary_guest
        tools_status = summary_guest[:toolsStatus]
        tools_status = nil if tools_status.blank?

        vm_hash[:tools_status] = tools_status
      end

      parse_virtual_machine_summary_runtime(vm_hash, props)
    end

    def parse_virtual_machine_storage(vm_hash, props)
      vm_path_name = props.fetch_path(:summary, :config, :vmPathName)
      return if vm_path_name.nil?

      datastore_name = vm_path_name.gsub(/^\[([^\]]*)\].*/, '\1')
      return if datastore_name.nil?

      datastore = props[:datastore].to_a.detect do |ds|
        cache.find(ds)&.dig(:summary, :name) == datastore_name
      end

      datastore_props = cache.find(datastore) if datastore
      vm_hash[:storage] = persister.storages.lazy_find(parse_datastore_location(datastore_props)) if datastore_props
    end

    def parse_virtual_machine_summary_runtime(vm_hash, props)
      runtime = props.fetch_path(:summary, :runtime)
      return if runtime.nil?

      vm_hash[:connection_state] = runtime[:connectionState]
      vm_hash[:host] = lazy_find_managed_object(runtime[:host])
      vm_hash[:ems_cluster] = lazy_find_managed_object(cache.find(runtime[:host])&.dig(:parent))
      vm_hash[:boot_time] = runtime[:bootTime]
      vm_hash[:raw_power_state] = if props.fetch_path(:summary, :config, :template)
                                      "never"
                                    else
                                      runtime[:powerState]
                                    end
    end

    def parse_virtual_machine_memory_allocation(vm_hash, props)
      memory_allocation = props.fetch_path(:resourceConfig, :memoryAllocation)
      return if memory_allocation.nil?

      vm_hash[:memory_reserve] = memory_allocation[:reservation]
      vm_hash[:memory_reserve_expand] = memory_allocation[:expandableReservation].to_s.downcase == "true"
      vm_hash[:memory_limit] = memory_allocation[:limit]
      vm_hash[:memory_shares] = memory_allocation.fetch_path(:shares, :shares)
      vm_hash[:memory_shares_level] = memory_allocation.fetch_path(:shares, :level)
    end

    def parse_virtual_machine_cpu_allocation(vm_hash, props)
      cpu_allocation = props.fetch_path(:resourceConfig, :cpuAllocation)
      vm_hash[:cpu_reserve] = cpu_allocation[:reservation]
      vm_hash[:cpu_reserve_expand] = cpu_allocation[:expandableReservation].to_s.downcase == "true"
      vm_hash[:cpu_limit] = cpu_allocation[:limit]
      vm_hash[:cpu_shares] = cpu_allocation.fetch_path(:shares, :shares)
      vm_hash[:cpu_shares_level] = cpu_allocation.fetch_path(:shares, :level)
    end

    def parse_virtual_machine_resource_config(vm_hash, props)
      parse_virtual_machine_cpu_allocation(vm_hash, props)
      parse_virtual_machine_memory_allocation(vm_hash, props)
    end

    def parse_virtual_machine_operating_system(vm, props)
      guest_full_name = props.fetch_path(:summary, :config, :guestFullName)
      persister.operating_systems.build(
        :vm_or_template => vm,
        :product_name   => guest_full_name.blank? ? "Other" : guest_full_name
      )
    end

    def parse_virtual_machine_hardware(vm, props)
      hardware_hash = {:vm_or_template => vm}

      summary_config = props.fetch_path(:summary, :config)
      if summary_config
        guest_id = summary_config[:guestId]
        hardware_hash[:guest_os] = guest_id.blank? ? "Other" : guest_id.to_s.downcase.chomp("guest")

        guest_full_name = summary_config[:guestFullName]
        hardware_hash[:guest_os_full_name] = guest_full_name.blank? ? "Other" : guest_full_name

        uuid = summary_config[:uuid]
        bios = MiqUUID.clean_guid(uuid) || uuid
        hardware_hash[:bios] = bios unless bios.blank?

        hardware_hash[:cpu_total_cores] = summary_config[:numCpu].to_i

        annotation = summary_config[:annotation]
        hardware_hash[:annotation] = annotation.present? ? annotation : nil

        memory_size_mb = summary_config[:memorySizeMB]
        hardware_hash[:memory_mb] = memory_size_mb unless memory_size_mb.blank?
      end

      # cast numCoresPerSocket to an integer so that we can check for nil and 0
      cpu_cores_per_socket                 = props.fetch_path(:config, :hardware, :numCoresPerSocket).to_i
      hardware_hash[:cpu_cores_per_socket] = cpu_cores_per_socket.zero? ? 1 : cpu_cores_per_socket
      hardware_hash[:cpu_sockets]          = hardware_hash[:cpu_total_cores] / hardware_hash[:cpu_cores_per_socket]

      config_version = props.fetch_path(:config, :version)
      hardware_hash[:virtual_hw_version] = config_version.to_s.split('-').last if config_version.present?

      hardware = persister.hardwares.build(hardware_hash)

      parse_virtual_machine_disks(hardware, props)
      parse_virtual_machine_guest_devices(hardware, props)
    end

    def parse_virtual_machine_disks(hardware, props)
      devices = props.fetch_path(:config, :hardware, :device).to_a
      devices.each do |device|
        case device
        when RbVmomi::VIM::VirtualDisk   then device_type = 'disk'
        when RbVmomi::VIM::VirtualFloppy then device_type = 'floppy'
        when RbVmomi::VIM::VirtualCdrom  then device_type = 'cdrom'
        else next
        end

        backing = device.backing
        next if backing.nil?

        if device_type == 'cdrom'
          device_type << if backing.kind_of?(RbVmomi::VIM::VirtualCdromIsoBackingInfo)
                           "-image"
                         else
                           "-raw"
                         end
        end

        controller = devices.detect { |d| d.key == device.controllerKey }
        next if controller.nil?

        controller_type = case controller.class.wsdl_name
                          when /IDE/ then 'ide'
                          when /SIO/ then 'sio'
                          else 'scsi'
                          end
        disk_hash = {
          :hardware        => hardware,
          :device_name     => device.deviceInfo.label,
          :device_type     => device_type,
          :controller_type => controller_type,
          :present         => true,
          :location        => "#{controller.busNumber}:#{device.unitNumber}"
        }

        case backing
        when RbVmomi::VIM::VirtualDeviceFileBackingInfo
          disk_hash[:filename] = backing.fileName

          if backing.datastore
            datastore_props    = cache.find(backing.datastore)
            datastore_location = parse_datastore_location(datastore_props) if datastore_props

            disk_hash[:storage] = persister.storages.lazy_find(datastore_location) if datastore_location
          end
        when RbVmomi::VIM::VirtualDeviceRemoteDeviceBackingInfo
          disk_hash[:filename] = backing.deviceName
        end

        if device_type == "disk"
          disk_hash[:mode] = backing.diskMode
          disk_hash[:size] = device.capacityInKB.to_i.kilobytes
          disk_hash[:disk_type] = if backing.kind_of?(RbVmomi::VIM::VirtualDiskRawDiskMappingVer1BackingInfo)
                                    "rdm-#{backing.compatibilityMode.to_s[0...-4]}" # physicalMode or virtualMode
                                  elsif backing.kind_of?(RbVmomi::VIM::VirtualDiskFlatVer2BackingInfo)
                                    backing.thinProvisioned.to_s.downcase == 'true' ? "thin" : "thick"
                                  else
                                    "thick"
                                  end
        else
          disk_hash[:start_connected] = device.connectable.startConnected
        end

        persister.disks.build(disk_hash)
      end
    end

    def parse_virtual_machine_guest_devices(hardware, props)
      devices = props.fetch_path(:config, :hardware, :device).to_a

      veth_devices = devices.select { |dev| dev.kind_of?(RbVmomi::VIM::VirtualEthernetCard) }
      veth_devices.each do |device|
        next if device.macAddress.nil?
        uid = address = device.macAddress

        name = device.deviceInfo.label
        backing = device.backing

        present = device.connectable.connected
        start_connected = device.connectable.startConnected

        guest_device_hash = {
          :hardware        => hardware,
          :uid_ems         => uid,
          :device_name     => name,
          :device_type     => 'ethernet',
          :controller_type => 'ethernet',
          :present         => present,
          :start_connected => start_connected,
          :address         => address,
        }

        unless backing.nil?
          lan_uid = if backing.kind_of?(RbVmomi::VIM::VirtualEthernetCardDistributedVirtualPortBackingInfo)
                      backing.port.portgroupKey
                    else
                      backing.deviceName
                    end
          # TODO: guest_device_hash[:lan] = persister.lans.lazy_find(lan_uid)
        end

        persister.guest_devices.build(guest_device_hash)
      end
    end

    def parse_virtual_machine_custom_attributes(vm, props)
      available_field = props[:availableField]
      custom_values = props.fetch_path(:summary, :customValue)

      key_to_name = {}
      available_field.to_a.each { |af| key_to_name[af["key"]] = af["name"] }

      custom_values.to_a.each do |cv|
        persister.custom_attributes.build(
          :resource => vm,
          :section  => "custom_field",
          :name     => key_to_name[cv["key"]],
          :value    => cv["value"],
          :source   => "VC",
        )
      end
    end

    def parse_virtual_machine_snapshots(vm, props)
    end
  end
end
