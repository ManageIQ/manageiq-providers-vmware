class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  module HostSystem
    def parse_host_config(host_hash, props)
      if props.include?("config.name")
        host_hash[:uid_ems] = props["config.name"]
      end
      if props.include?("config.adminDisabled")
        host_hash[:admin_disabled] = props["config.adminDisabled"].to_s.downcase == "true"
      end
      if props.include?("config.hyperThread.active")
        host_hash[:hyperthreading] = props["config.hyperThread.active"].to_s.downcase == "true"
      end
    end

    def parse_host_network(host_hash, props)
      if props.include?("config.network.dnsConfig.hostName")
        hostname = props["config.network.dnsConfig.hostName"]
        host_hash[:name] = host_hash[:hostname] = hostname
      end
      if props.include?("config.network.dnsConfig.domainName")
        _domain_name = props["config.network.dnsConfig.domainName"]
      end

      default_gw = if props.include?("config.network.ipRouteConfig.defaultGateway")
                     require 'ipaddr'
                     IPAddr.new(props["config.network.ipRouteConfig.defaultGateway"])
                   end
      unless default_gw.nil?
        vnics = []

        if props.include?("config.network.consoleVnic")
          console_vnic = props["config.network.consoleVnic"]
          vnics.concat(console_vnic) unless console_vnic.blank?
        end
        if props.include?("config.network.vnic")
          network_vnic = props["config.network.vnic"]
          vnics.concat(network_vnic) unless network_vnic.blank?
        end

        vnics.each do |vnic|
          ip = vnic.spec.ip.ipAddress
          subnet_mask = vnic.spec.ip.subnetMask

          next if ip.blank? || subnet_mask.blank? || !default_gw.mask(subnet_mask).include?(ip)

          host_hash[:ipaddress] = ip
          break
        end
      end
    end

    def parse_host_product(host_hash, props)
      if props.include?("summary.config.product.vendor")
        vendor = props["summary.config.product.vendor"].split(",").first.to_s.downcase
        vendor = "unknown" unless Host::VENDOR_TYPES.include?(vendor)

        host_hash[:vmm_vendor] = vendor
      end
      if props.include?("summary.config.product.name")
        product_name = props["summary.config.product.name"]
        host_hash[:vmm_product] = product_name.nil? ? nil : product_name.to_s.gsub(/^VMware\s*/i, "")
      end
      if props.include?("summary.config.product.version")
        host_hash[:vmm_version] = props["summary.config.product.version"]
      end
      if props.include?("summary.config.product.build")
        host_hash[:vmm_buildnumber] = props["summary.config.product.build"]
      end
    end

    def parse_host_runtime(host_hash, props)
      if props.include?("summary.runtime.connectionState")
        connection_state = props["summary.runtime.connectionState"]

        if ['disconnected', 'notResponding', nil, ''].include?(connection_state)
        end

        host_hash[:connection_state] = connection_state
      end
      if props.include?("summary.runtime.inMaintenanceMode")
        maintenance_mode = props["summary.runtime.connectionState"]
        host_hash[:maintenance] = maintenance_mode.to_s.downcase == "true"
      end
      if props.include?("summary.runtime.inMaintenanceMode") && props.include?("summary.runtime.connectionState")
        host_hash[:power_state] = if host_hash[:connection_state] != "connected"
                                    "off"
                                  elsif host_hash[:maintenance]
                                    "maintenance"
                                  else
                                    "on"
                                  end
      end
    end

    def parse_host_system_info(host_hash, props)
      return unless props.include?("hardware.systemInfo.otherIdentifyingInfo")

      asset_tag = service_tag = nil
      props["hardware.systemInfo.otherIdentifyingInfo"].each do |info|
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

    def parse_host_children(host_hash, props)
      # TODO
    end

    def parse_host_operating_system(host, props)
      persister.host_operating_systems.build(
        :host         => host,
        :name         => host.data[:hostname],
        :product_name => host.data[:vmm_product],
        :version      => host.data[:vmm_version],
        :build_number => host.data[:vmm_buildnumber],
        :product_type => props["summary.config.product.osType"],
      )
    end

    def parse_host_system_services(host, props)
      # TODO
    end

    def parse_host_hardware(host, props)
      hardware_hash = {:host => host}

      if props.include?("summary.hardware.cpuMhz")
        hardware_hash[:cpu_speed] = props["summary.hardware.cpuMhz"]
      end
      if props.include?("summary.hardware.cpuModel")
        hardware_hash[:cpu_type] = props["summary.hardware.cpuModel"]
      end
      if props.include?("summary.hardware.manufacturer")
        hardware_hash[:manufacturer] = props["summary.hardware.manufacturer"]
      end
      if props.include?("summary.hardware.model")
        hardware_hash[:model] = props["summary.hardware.model"]
      end
      if props.include?("summary.hardware.numNics")
        hardware_hash[:number_of_nics] = props["summary.hardware.numNics"]
      end
      if props.include?("summary.hardware.memorySize")
        memory_size = props["summary.hardware.memorySize"]

        # Value provided by VC is in bytes, need to convert to MB
        hardware_hash[:memory_mb] = is_numeric?(memory_size) ? (memory_size.to_f / 1.megabyte).round : nil
      end
      if props.include?("console.consoleReservation.serviceConsoleReserved")
        memory_console = props["console.consoleReservation.serviceConsoleReserved"]
        hardware_hash[:memory_console] = is_numeric?(memory_console) ? (memory_console.to_f / 1.megabyte).round : nil
      end
      if props.include?("summary.hardware.numCpuPkgs")
        hardware_hash[:cpu_sockets] = props["summary.hardware.numCpuPkgs"]
      end
      if props.include?("summary.hardware.numCpuCores")
        hardware_hash[:cpu_total_cores] = props["summary.hardware.numCpuCores"]
      end
      if props.include?("summary.hardware.numCpuPkgs") && props.include?("summary.hardware.numCpuCores")
        hardware_hash[:cpu_cores_per_socket] = (hardware_hash[:cpu_total_cores].to_f / hardware_hash[:cpu_sockets].to_f).to_i
      end
      if props.include?("summary.config.product.name")
        guest_os = props["summary.config.product.name"].to_s.gsub(/^VMware\s*/i, "")
        hardware_hash[:guest_os] = guest_os
        hardware_hash[:guest_os_full_name] = guest_os
      end
      if props.include?("summary.config.vmotionEnabled")
        vmotion_enabled = props["summary.config.vmotionEnabled"]
        hardware_hash[:vmotion_enabled] = vmotion_enabled.to_s.downcase == "true"
      end
      if props.include?("summary.quickStats.overallCpuUsage")
        hardware_hash[:cpu_usage] = props["summary.quickStats.overallCpuUsage"]
      end
      if props.include?("summary.quickStats.overallMemoryUsage")
        hardware_hash[:memory_usage] = props["summary.quickStats.overallMemoryUsage"]
      end

      hardware = persister.host_hardwares.build(hardware_hash)

      parse_host_guest_devices(hardware, props)
    end

    def parse_host_guest_devices(hardware, props)
      if props.include?("config.network.pnic")
        props["config.network.pnic"].to_a.each do |pnic|
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
            :switch          => persister.switches.lazy_find(pnic.key)
          )
        end
      end

      if props.include?("config.storageDevice.hostBusAdapter")
        props["config.storageDevice.hostBusAdapter"].to_a.each do |hba|
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
    end

    def parse_host_switches(host, props)
      # TODO
    end
  end
end
