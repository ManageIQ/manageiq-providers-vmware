class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  module HostSystem
    def datacenter_ref_by_host(host)
      @datacenter_ref_by_host ||= {}
      @datacenter_ref_by_host[host._ref] ||= find_parent_datacenter(host)
    end

    def network_ref_by_datacenter_and_name
      @network_ref_by_datacenter_and_name ||= cache["Network"].each_with_object({}) do |(ref, data), result|
        result[find_parent_datacenter(data[:parent])._ref] ||= {}
        result[find_parent_datacenter(data[:parent])._ref][data[:name]] = ref
      end
    end

    def validate_host_system_props(object, props)
      # We use summary and summary.config in order to set some required properties for hosts,
      # if these are missing we won't have enough information to build a useful record.
      if props.fetch_path(:summary, :config, :product).nil?
        [true, "Missing summary for Host [#{object._ref}]"]
      else
        false
      end
    end

    def parse_host_system_summary(host_hash, props)
      summary = props[:summary]
      return if summary.nil?

      host_hash[:uid_ems] = summary.fetch_path(:config, :name)
    end

    def parse_host_system_config(host_hash, props)
      config = props[:config]
      return if config.nil?

      host_hash[:admin_disabled] = config[:adminDisabled].to_s.downcase == "true"
      host_hash[:hyperthreading] = config.fetch_path(:hyperThread, :active).to_s.downcase == "true"
    end

    def parse_host_system_network(host_hash, props)
      network = props.fetch_path(:config, :network)
      return if network.nil?

      dns_config = network[:dnsConfig]
      if dns_config
        hostname    = dns_config[:hostName]
        domain_name = dns_config[:domainName]

        hostname = "#{hostname}.#{domain_name}" if domain_name

        host_hash[:name]     = hostname
        host_hash[:hostname] = hostname
      end

      if network.fetch_path(:ipRouteConfig, :defaultGateway)
        require 'ipaddr'
        default_gw = IPAddr.new(network.fetch_path(:ipRouteConfig, :defaultGateway))
      end

      unless default_gw.nil?
        vnics = []

        console_vnic = network[:consoleVnic]
        vnics.concat(console_vnic) if console_vnic.present?

        network_vnic = network[:vnic]
        vnics.concat(network_vnic) if network_vnic.present?

        vnics.each do |vnic|
          ip = vnic.spec.ip.ipAddress
          subnet_mask = vnic.spec.ip.subnetMask

          next if ip.blank? || subnet_mask.blank? || !default_gw.mask(subnet_mask).include?(ip)

          host_hash[:ipaddress] = ip
          break
        end
      end
    end

    def parse_host_system_host_networks(_host, hardware, props)
      network = props.fetch_path(:config, :network)
      return if network.nil?

      vnics = Array(network[:consoleVnic]) + Array(network[:vnic])
      vnics.each do |vnic|
        port_key = vnic.port
        portgroup = Array(network[:portgroup]).find { |pg| pg.port.find { |p| p.key == port_key } }
        next if portgroup.nil?

        vswitch_key = portgroup[:vswitch]
        vswitch = network[:vswitch].find { |v| v.key == vswitch_key }
        next if vswitch.nil?

        pnic_key = vswitch.pnic.first
        pnic = network[:pnic].find { |p| p.key == pnic_key }
        next if pnic.nil?

        ip = vnic.spec&.ip
        next if ip.nil?

        persister.host_networks.build(
          :hardware     => hardware,
          :description  => pnic.device,
          :dhcp_enabled => ip.dhcp,
          :ipaddress    => ip.ipAddress,
          :subnet_mask  => ip.subnetMask
        )
      end
    end

    def parse_host_system_product(host_hash, props)
      product = props.fetch_path(:summary, :config, :product)
      return if product.nil?

      vendor = product[:vendor].split(",").first.to_s.downcase
      vendor = "unknown" unless Host::VENDOR_TYPES.include?(vendor)
      host_hash[:vmm_vendor] = vendor

      product_name = product[:name]
      host_hash[:vmm_product]     = product_name.nil? ? nil : product_name.to_s.gsub(/^VMware\s*/i, "")
      host_hash[:vmm_version]     = product[:version]
      host_hash[:vmm_buildnumber] = product[:build]
    end

    def parse_host_system_runtime(host_hash, props)
      runtime = props.fetch_path(:summary, :runtime)
      return if runtime.nil?

      host_hash[:connection_state] = runtime[:connectionState]

      host_hash[:maintenance] = runtime[:inMaintenanceMode].to_s.downcase == "true"
      host_hash[:power_state] = if host_hash[:connection_state] != "connected"
                                  "off"
                                elsif host_hash[:maintenance]
                                  "maintenance"
                                else
                                  "on"
                                end
    end

    def parse_host_system_system_info(host_hash, props)
      other_identifying_info = props.fetch_path(:hardware, :systemInfo, :otherIdentifyingInfo)
      return if other_identifying_info.nil?

      asset_tag = service_tag = nil
      other_identifying_info.each do |info|
        value = info.identifierValue.to_s.strip
        value = nil if value.blank?

        case info.identifierType.key
        when "AssetTag"   then asset_tag   = value
        when "ServiceTag" then service_tag = value
        end
      end

      host_hash[:asset_tag] = asset_tag
      host_hash[:service_tag] = service_tag
    end

    def parse_host_system_operating_system(host, props)
      persister.host_operating_systems.build(
        :host         => host,
        :name         => host.data[:hostname],
        :product_name => host.data[:vmm_product],
        :version      => host.data[:vmm_version],
        :build_number => host.data[:vmm_buildnumber],
        :product_type => props.fetch_path(:summary, :config, :product, :osType)
      )
    end

    def parse_host_system_system_services(host, props)
      host_service_info = props.fetch_path(:config, :service, :service)
      return if host_service_info.nil?

      host_service_info.each do |service|
        persister.host_system_services.build(
          :host         => host,
          :name         => service[:key],
          :display_name => service[:label],
          :running      => service[:running]
        )
      end
    end

    def parse_host_system_hardware(host, props)
      hardware_hash = {:host => host}

      hardware = props.fetch_path(:summary, :hardware)
      if hardware
        hardware_hash[:cpu_speed] = hardware[:cpuMhz]
        hardware_hash[:cpu_type] = hardware[:cpuModel]
        hardware_hash[:manufacturer] = hardware[:vendor]
        hardware_hash[:model] = hardware[:model]
        hardware_hash[:number_of_nics] = hardware[:numNics]

        # Value provided by VC is in bytes, need to convert to MB
        memory_size = hardware[:memorySize]
        hardware_hash[:memory_mb] = is_numeric?(memory_size) ? (memory_size.to_f / 1.megabyte).round : nil

        memory_console = props.fetch_path(:console, :consoleReservation, :serviceConsoleReserved)
        hardware_hash[:memory_console] = is_numeric?(memory_console) ? (memory_console.to_f / 1.megabyte).round : nil
        hardware_hash[:cpu_sockets] = hardware[:numCpuPkgs]
        hardware_hash[:cpu_total_cores] = hardware[:numCpuCores]
        hardware_hash[:cpu_cores_per_socket] = (hardware_hash[:cpu_total_cores].to_f / hardware_hash[:cpu_sockets]).to_i
      end

      summary_config = props.fetch_path(:summary, :config)
      if summary_config
        guest_os = summary_config.fetch_path(:product, :name).to_s.gsub(/^VMware\s*/i, "")
        hardware_hash[:guest_os] = guest_os
        hardware_hash[:guest_os_full_name] = guest_os

        vmotion_enabled = summary_config[:vmotionEnabled]
        hardware_hash[:vmotion_enabled] = vmotion_enabled.to_s.downcase == "true"
      end

      quick_stats = props.fetch_path(:summary, :quickStats)
      if quick_stats
        hardware_hash[:cpu_usage] = quick_stats[:overallCpuUsage]
        hardware_hash[:memory_usage] = quick_stats[:overallMemoryUsage]
      end

      persister_hardware = persister.host_hardwares.build(hardware_hash)

      parse_host_system_network_adapters(persister_hardware, props)
      parse_host_system_storage_adapters(persister_hardware, props)

      persister_hardware
    end

    def parse_host_system_network_adapters(hardware, props)
      pnics = props.fetch_path(:config, :network, :pnic)
      pnics.to_a.each do |pnic|
        name = uid = pnic.device

        link_speed  = pnic.linkSpeed&.speedMb
        link_speed *= 1000 if link_speed

        persister.host_guest_devices.build(
          :hardware        => hardware,
          :uid_ems         => uid,
          :device_name     => name,
          :device_type     => 'ethernet',
          :location        => pnic.pci,
          :present         => true,
          :controller_type => 'ethernet',
          :address         => pnic.mac,
          :speed           => link_speed
        )
      end
    end

    def parse_host_system_scsi_luns(scsi_luns)
      scsi_luns.to_a.each_with_object({}) do |lun, result|
        if lun.kind_of?(RbVmomi::VIM::HostScsiDisk)
          n_blocks   = lun.capacity.block
          block_size = lun.capacity.blockSize
          capacity   = (n_blocks * block_size) / 1024
        end

        lun_hash = {
          :uid_ems        => lun.uuid,
          :lun_type       => lun.lunType,
          :canonical_name => lun.canonicalName,
          :device_name    => lun.deviceName,
          :device_type    => lun.deviceType,
          :block          => n_blocks,
          :block_size     => block_size,
          :capacity       => capacity,
        }

        result[lun.key] = lun_hash
      end
    end

    def parse_host_system_scsi_targets(scsi_adapters, scsi_lun_uids)
      scsi_adapters.to_a.each_with_object({}) do |adapter, result|
        result[adapter.adapter] = adapter.target.to_a.map do |target|
          uid = target.target.to_s

          transport = target.transport
          if transport && transport.kind_of?(RbVmomi::VIM::HostInternetScsiTargetTransport)
            iscsi_name  = target.transport.iScsiName
            iscsi_alias = target.transport.iScsiAlias
            address     = target.transport.address
          end

          scsi_luns = target.lun.to_a.map do |lun|
            scsi_lun_uids[lun.scsiLun]&.merge(:lun => lun.lun.to_s)
          end

          {
            :uid_ems       => uid,
            :target        => uid,
            :iscsi_name    => iscsi_name,
            :iscsi_alias   => iscsi_alias,
            :address       => address,
            :miq_scsi_luns => scsi_luns,
          }
        end
      end
    end

    def parse_host_system_storage_adapters(hardware, props)
      storage_devices = props.dig(:config, :storageDevice)
      return if storage_devices.blank?

      scsi_lun_uids = parse_host_system_scsi_luns(storage_devices[:scsiLun])

      scsi_adapters = storage_devices.dig(:scsiTopology, :adapter)
      scsi_targets_by_adapter = parse_host_system_scsi_targets(scsi_adapters, scsi_lun_uids)

      hbas = storage_devices[:hostBusAdapter]
      hbas.to_a.each do |hba|
        name = uid = hba.device
        location = hba.pci
        model = hba.model

        if hba.kind_of?(RbVmomi::VIM::HostInternetScsiHba)
          iscsi_name = hba.iScsiName
          iscsi_alias = hba.iScsiAlias
          chap_auth_enabled = hba.authenticationProperties.chapAuthEnabled
        end

        controller_type = case hba
                          when RbVmomi::VIM::HostBlockHba
                            "Block"
                          when RbVmomi::VIM::HostFibreChannelHba
                            "Fibre"
                          when RbVmomi::VIM::HostInternetScsiHba
                            "iSCSI"
                          when RbVmomi::VIM::HostParallelScsiHba
                            "SCSI"
                          else
                            "HBA"
                          end

        persister_guest_device = persister.host_guest_devices.build(
          :hardware          => hardware,
          :uid_ems           => uid,
          :device_name       => name,
          :device_type       => 'storage',
          :present           => true,
          :iscsi_name        => iscsi_name,
          :iscsi_alias       => iscsi_alias,
          :location          => location,
          :model             => model,
          :chap_auth_enabled => chap_auth_enabled,
          :controller_type   => controller_type
        )

        scsi_targets_by_adapter[hba.key].to_a.each do |scsi_target|
          miq_scsi_luns = Array.wrap(scsi_target.delete(:miq_scsi_luns))

          persister_scsi_target = persister.miq_scsi_targets.build(
            scsi_target.merge(:guest_device => persister_guest_device)
          )

          miq_scsi_luns.each do |miq_scsi_lun|
            persister.miq_scsi_luns.build(
              miq_scsi_lun.merge(:miq_scsi_target => persister_scsi_target)
            )
          end
        end
      end
    end

    def parse_host_system_switches(host, props)
      network = props.fetch_path(:config, :network)
      return if network.blank?

      type = ManageIQ::Providers::Vmware::InfraManager::HostVirtualSwitch.name

      switches = network[:vswitch]
      persister_switches = switches.to_a.map do |switch|
        security_policy = switch.spec&.policy&.security
        if security_policy
          allow_promiscuous = security_policy[:allowPromiscuous]
          forged_transmits  = security_policy[:forgedTransmits]
          mac_changes       = security_policy[:macChanges]
        end

        persister_switch = persister.host_virtual_switches.build(
          :host              => host,
          :uid_ems           => switch[:name],
          :mtu               => switch[:mtu],
          :name              => switch[:name],
          :type              => type,
          :ports             => switch[:numPorts],
          :allow_promiscuous => allow_promiscuous,
          :forged_transmits  => forged_transmits,
          :mac_changes       => mac_changes
        )

        switch.pnic.to_a.each do |pnic|
          pnic_uid_ems = pnic.split("-").last
          next if pnic_uid_ems.nil?

          hardware = persister.host_hardwares.find(host)
          persister_guest_device = persister.host_guest_devices.find_or_build_by(:hardware => hardware, :uid_ems => pnic_uid_ems)
          persister_guest_device.assign_attributes(
            :switch => persister_switch
          )
        end

        persister_switch
      end

      type = ManageIQ::Providers::Vmware::InfraManager::OpaqueSwitch.name
      opaque_persister_switches = network[:opaqueSwitch].to_a.map do |switch|
        uid = switch.key
        persister.host_virtual_switches.build(
          :host    => host,
          :uid_ems => uid,
          :name    => switch.name,
          :type    => type
        )
      end

      persister_switches.concat(opaque_persister_switches)
    end

    def parse_host_system_distributed_switches(host)
      dvs_mors = %w[VmwareDistributedVirtualSwitch DistributedVirtualSwitch].flat_map do |dvs_klass|
        dvs = cache[dvs_klass].select do |_mor, props|
          props.fetch_path(:summary, :hostMember).any? { |h| h._ref == host.ems_ref }
        end

        dvs.collect { |mor, _| mor }
      end
      dvs_mors.collect { |mor| persister.distributed_virtual_switches.lazy_find(mor) }
    end

    def parse_host_system_host_switches(host, switches)
      switches.each do |switch|
        persister.host_switches.build(:host => host, :switch => switch)
      end
    end

    def parse_host_system_lans(object, host, switches, props)
      network = props.fetch_path(:config, :network)
      return if network.blank?

      switch_uids = switches.index_by(&:name)
      datacenter = datacenter_ref_by_host(object)

      network[:portgroup].to_a.each do |portgroup|
        next if portgroup.spec.nil?

        name    = portgroup.spec.name
        ems_ref = network_ref_by_datacenter_and_name.dig(datacenter._ref, name) if datacenter

        lan_hash = {
          :uid_ems => name,
          :name    => name,
          :tag     => portgroup.spec.vlanId.to_s,
          :switch  => switch_uids[portgroup.spec.vswitchName],
          :ems_ref => ems_ref
        }

        security = portgroup.spec.policy&.security
        if security
          lan_hash[:allow_promiscuous] = security.allowPromiscuous
          lan_hash[:forged_transmits]  = security.forgedTransmits
          lan_hash[:mac_changes]       = security.macChanges
        end

        computed_security = portgroup.computedPolicy&.security
        if computed_security
          lan_hash[:computed_allow_promiscuous] = computed_security.allowPromiscuous
          lan_hash[:computed_forged_transmits]  = computed_security.forgedTransmits
          lan_hash[:computed_mac_changes]       = computed_security.macChanges
        end

        persister.host_virtual_lans.build(lan_hash)
      end

      network[:opaqueNetwork].to_a.each do |opaque_network|
        switch_key = cache["HostSystem"][host.ems_ref]&.dig(:config, :network, :opaqueSwitch)&.pluck(:key)&.sort&.first
        next if switch_key.nil?

        extra_config     = Hash[opaque_network.extraConfig.to_a.map { |ec| [ec.key, ec.value] }]
        nsx_network_uuid = extra_config["com.vmware.opaquenetwork.segment.path"]&.split("/")&.last

        name    = opaque_network.opaqueNetworkName
        ems_ref = nsx_network_uuid || name
        uid_ems = opaque_network.opaqueNetworkId
        switch  = persister.host_virtual_switches.lazy_find(:host => host, :uid_ems => switch_key)

        persister.host_virtual_lans.build(
          :switch  => switch,
          :ems_ref => ems_ref,
          :uid_ems => uid_ems,
          :name    => name
        )
      end
    end
  end
end
