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

      parse_virtual_machine_disks(vm, hardware, props)
      guest_devices = parse_virtual_machine_guest_devices(vm, hardware, props)
      parse_virtual_machine_networks(vm, props, hardware, guest_devices)
    end

    def parse_virtual_machine_disks(_vm, hardware, props)
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

    def parse_virtual_machine_guest_devices(vm, hardware, props)
      devices = props.fetch_path(:config, :hardware, :device).to_a

      veth_devices = devices.select { |dev| dev.kind_of?(RbVmomi::VIM::VirtualEthernetCard) }
      veth_devices.map do |device|
        next if device.macAddress.nil?
        uid = address = device.macAddress

        name = device.deviceInfo.label

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
          :model           => device.class.wsdl_name,
          :address         => address,
          :lan             => parse_virtual_machine_guest_device_lan(vm, device),
        }

        persister.guest_devices.build(guest_device_hash)
      end
    end

    def parse_virtual_machine_networks(vm, props, hardware, guest_devices)
      summary_guest = props.fetch_path(:summary, :guest)
      return if summary_guest.nil?

      hostname = summary_guest[:hostName]
      guest_ip = summary_guest[:ipAddress]
      if hostname || guest_ip
        props.fetch_path(:guest, :net).to_a.each do |net|
          ipv4, ipv6 = net[:ipAddress].to_a.compact.collect(&:to_s).sort.partition { |ip| ip =~ /([0-9]{1,3}\.){3}[0-9]{1,3}/ }
          ipv4 << nil if ipv4.empty?
          ipaddresses = ipv4.zip_stretched(ipv6)

          guest_device = guest_devices.detect { |gd| gd.data[:address] == net[:macAddress] }

          ipaddresses.each do |ipaddress, ipv6address|
            persister.networks.build(
              :hardware     => hardware,
              :guest_device => guest_device,
              :hostname     => hostname,
              :ipaddress    => ipaddress,
              :ipv6address  => ipv6address,
            )
          end
        end
      end
    end

    def parse_virtual_machine_custom_attributes(vm, props)
      available_field = props[:availableField]
      custom_values = props.fetch_path(:summary, :customValue)

      key_to_name = {}
      available_field.to_a.each { |af| key_to_name[af["key"]] = af["name"] }

      custom_values.to_a.each do |cv|
        persister.ems_custom_attributes.build(
          :resource => vm,
          :section  => "custom_field",
          :name     => key_to_name[cv["key"]],
          :value    => cv["value"],
          :source   => "VC",
        )
      end
    end

    def parse_virtual_machine_snapshots(vm, props)
      snapshots = props[:snapshot]
      return if snapshots.blank?

      current = snapshots[:currentSnapshot]
      return if current.nil?

      snapshots[:rootSnapshotList].to_a.each do |snapshot|
        parse_virtual_machine_snapshot(vm, snapshot, current)
      end
    end

    def parse_virtual_machine_snapshot(vm, snapshot, current, parent_uid = nil)
      snap = snapshot[:snapshot]
      return if snap.nil?

      create_time = snapshot[:createTime]
      parent = persister.snapshots.lazy_find(:vm_or_template => vm, :uid => Time.parse(parent_uid).iso8601(6)) if parent_uid

      snapshot_hash = {
        :vm_or_template => vm,
        :ems_ref        => snap._ref,
        :ems_ref_obj    => managed_object_to_vim_string(snap),
        :uid_ems        => create_time.to_s,
        :uid            => create_time.iso8601(6),
        :parent_uid     => parent_uid,
        :parent         => parent,
        :name           => CGI.unescape(snapshot[:name]),
        :description    => snapshot[:description],
        :create_time    => create_time.to_s,
        :current        => snap._ref == current._ref,
      }

      persister.snapshots.build(snapshot_hash)

      snapshot[:childSnapshotList].to_a.each do |child_snapshot|
        parse_virtual_machine_snapshot(vm, child_snapshot, current, snapshot_hash[:uid_ems])
      end
    end

    def parse_virtual_machine_guest_device_lan(vm, nic)
      backing = nic.backing
      return if backing.nil?

      if backing.kind_of?(RbVmomi::VIM::VirtualEthernetCardDistributedVirtualPortBackingInfo)
        lan_uid = backing.port.portgroupKey
        persister_switch = persister.distributed_virtual_switches.lazy_find({:switch_uuid => backing.port.switchUuid}, :ref => :by_switch_uuid)
      else
        lan_uid = backing.deviceName

        host_ref = find_vm_host_ref(vm)
        return if host_ref.nil?

        portgroup = find_host_portgroup_by_lan_name(host_ref, lan_uid)
        return if portgroup.nil?

        host       = persister.hosts.lazy_find(host_ref)
        switch_uid = portgroup.spec.vswitchName

        persister_switch = persister.host_virtual_switches.lazy_find(:host => host, :uid_ems => switch_uid)
      end

      return if lan_uid.nil? || persister_switch.nil?

      persister.lans.lazy_find({:switch => persister_switch, :uid_ems => lan_uid}, :transform_nested_lazy_finds => true)
    end

    def find_vm_host_ref(persister_vm)
      host = persister_vm[:host]
      return if host.nil?

      host[:ems_ref]
    end

    def find_host_portgroup_by_lan_name(host_ref, lan_name)
      cached_host = cache["HostSystem"][host_ref]
      return if cached_host.nil?

      host_portgroups = cached_host.dig(:config, :network, :portgroup) || []
      host_portgroups.detect { |portgroup| portgroup.spec.name == lan_name }
    end
  end
end
