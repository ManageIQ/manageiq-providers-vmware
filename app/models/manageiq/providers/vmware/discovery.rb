require 'manageiq/network_discovery/port'

module ManageIQ
  module Providers
    module Vmware
      class Discovery
        def self.probe(ost)
          # Get Info from VMware (vSphere) Web Service API
          info = retrieve_webservice_info(ost.ipaddr)
          return if info.nil?

          hvisor_type = hypervisor_type(ost.ipaddr, info.productLineId)

          if ost.discover_types&.include?(hvisor_type)
            ost.hypervisor << hvisor_type
            ost.os << hypervisor_os_type(info.osType)
          end

        rescue => err
          _log.debug("Vmware::Discovery: ip = #{ost.ipaddr}, Failed to connect to VMware webservice: #{err}.")
          return
        end

        # Obtains info about IP address from vSphere Web Service API
        # @param ost [OpenStruct]
        def self.retrieve_webservice_info(ip)
          require 'VMwareWebService/MiqVimClientBase'
          vim = MiqVimClientBase.new(ip, "test", "test")
          info = vim&.about

          _log.debug("Vmware::Discovery: ip = #{ip}, Connected to VMware webservice.")

          info
        end

        # Adds product type (as hypervisor value) from vmware api info
        # @param [String] product_line_id
        def self.hypervisor_type(ip, product_line_id)
          case product_line_id.to_s
          when 'vpx'
            _log.debug("Vmware::Discovery: ip = #{ip}, Machine is VirtualCenter.")
            :virtualcenter
          when 'esx'
            _log.debug("Vmware::Discovery: ip = #{ip}, Machine is an ESX server.")
            :esx
          when 'embeddedEsx'
            _log.debug("Vmware::Discovery: ip = #{ip}, Machine is an ESXi server.")
            :esx
          when 'gsx'
            _log.debug("Vmware::Discovery: ip = #{ip}, Machine is an VMWare Server product.")
            :vmwareserver
          else
            _log.error("Vmware::Discovery: ip = #{ip}, Unknown product: #{product_line_id}")
            nil
          end
        end

        # Adds operating system from vmware api info
        def self.hypervisor_os_type(os_type)
          os_type.to_s.include?('win32') ? :mswin : :linux
        end
      end
    end
  end
end
