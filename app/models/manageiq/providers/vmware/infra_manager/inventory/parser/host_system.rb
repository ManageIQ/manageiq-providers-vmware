class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  module HostSystem
    def parse_host_system_config(host_hash, props)
      config = props[:config]
      return if config.nil?

      host_hash[:uid_ems]        = config[:name]
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

    def parse_host_system_children(host_hash, props)
      # TODO
    end

    def parse_host_system_operating_system(host, props)
      persister.host_operating_systems.build(
        :host         => host,
        :name         => host.data[:hostname],
        :product_name => host.data[:vmm_product],
        :version      => host.data[:vmm_version],
        :build_number => host.data[:vmm_buildnumber],
        :product_type => props.fetch_path(:summary, :config, :product, :osType),
      )
    end

    def parse_host_system_system_services(host, props)
      # TODO
    end

    def parse_host_system_hardware(host, props)
      hardware_hash = {:host => host}

      hardware = props.fetch_path(:summary, :hardware)
      if hardware
        hardware_hash[:cpu_speed] = hardware[:cpuMhz]
        hardware_hash[:cpu_type] = hardware[:cpuModel]
        hardware_hash[:manufacturer] = hardware[:manufacturer]
        hardware_hash[:model] = hardware[:model]
        hardware_hash[:number_of_nics] = hardware[:numNics]

        # Value provided by VC is in bytes, need to convert to MB
        memory_size = hardware[:memorySize]
        hardware_hash[:memory_mb] = is_numeric?(memory_size) ? (memory_size.to_f / 1.megabyte).round : nil

        memory_console = props.fetch_path(:console, :consoleReservation, :serviceConsoleReserved)
        hardware_hash[:memory_console] = is_numeric?(memory_console) ? (memory_console.to_f / 1.megabyte).round : nil
        hardware_hash[:cpu_sockets] = hardware[:numCpuPkgs]
        hardware_hash[:cpu_total_cores] = hardware[:numCpuCores]
        hardware_hash[:cpu_cores_per_socket] = (hardware_hash[:cpu_total_cores].to_f / hardware_hash[:cpu_sockets].to_f).to_i
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

      hardware = persister.host_hardwares.build(hardware_hash)

      parse_host_system_guest_devices(hardware, props)
    end

    def parse_host_system_guest_devices(hardware, props)
      pnics = props.fetch_path(:config, :network, :pnic)
      pnics.to_a.each do |pnic|
        name = uid = pnic.device

        persister.guest_devices.build(
          :hardware        => hardware,
          :uid_ems         => uid,
          :device_name     => name,
          :device_type     => 'ethernet',
          :location        => pnic.pci,
          :present         => true,
          :controller_type => 'ethernet',
          :address         => pnic.mac,
          # TODO: :switch          => persister.switches.lazy_find(pnic.device)
        )
      end

      hbas = props.fetch_path(:config, :storageDevice, :hostBusAdapter)
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

        persister.guest_devices.build(
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
          :controller_type   => controller_type,
        )
      end
    end

    def parse_host_system_switches(host, props)
      network = props.fetch_path(:config, :network)
      return if network.blank?

      type = ManageIQ::Providers::Vmware::InfraManager::HostVirtualSwitch.name

      switches = network[:vswitch]
      switches.to_a.each do |switch|
        security_policy = switch.spec&.policy&.security
        if security_policy
          allow_promiscuous = security_policy[:allowPromiscuous]
          forged_transmits  = security_policy[:forgedTransmits]
          mac_changes       = security_policy[:macChanges]
        end

        persister_switch = persister.switches.build(
          :uid_ems           => switch[:name],
          :name              => switch[:name],
          :type              => type,
          :ports             => switch[:numPorts],
          :mtu               => switch[:mtu],
          :allow_promiscuous => allow_promiscuous,
          :forged_transmits  => forged_transmits,
          :mac_changes       => mac_changes,
        )

        persister.host_switches.build(:host => host, :switch => persister_switch)
      end
    end
  end
end
