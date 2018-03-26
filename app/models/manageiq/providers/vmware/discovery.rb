require 'manageiq/network_discovery/port'

module ManageIQ
  module Providers
    module Vmware
      class Discovery
        def self.probe(ost)
          # Get Info from VMware (vSphere) Web Service API
          access_webservice(ost) do |info|
            if add_hypervisor(ost, info)
              add_os(ost, info)
            end
          end
        rescue StandardError => err
          _log&.warn("Vmware::Discovery: Failed to connect to VMware webservice: #{err}. ip = #{ost.ipaddr}")
          return
        end

        # Obtains info about IP address from vSphere Web Service API
        # @param ost [OpenStruct]
        def self.access_webservice(ost)
          require 'VMwareWebService/MiqVimClientBase'
          vim = MiqVimClientBase.new(ost.ipaddr, "test", "test")
          info = vim&.sic&.about

          _log&.debug("Vmware::Discovery: ip = #{ost.ipaddr}, Connected to VMware webservice.")

          yield info
        end

        # Adds product type (as hypervisor value) from vmware api info
        def self.add_hypervisor(ost, info)
          hypervisor = case info&.productLineId
                       when 'vpx'
                         _log&.debug("Vmware::Discovery: ip = #{ost.ipaddr}, Machine is VirtualCenter.")
                         :virtualcenter
                       when 'esx'
                         _log&.debug("Vmware::Discovery: ip = #{ost.ipaddr}, Machine is an ESX server.")
                         :esx
                       when 'embeddedEsx'
                         _log&.debug("Vmware::Discovery: ip = #{ost.ipaddr}, Machine is an ESXi server.")
                         :esx
                       when 'gsx'
                         _log&.debug("Vmware::Discovery: ip = #{ost.ipaddr}, Machine is an VMWare Server product.")
                         :vmwareserver
                       else
                         _log&.error("Vmware::Discovery: ip: #{ost.ipaddr}, Unknown product: #{info&.productLineId}")
                         nil
                       end

          ost.hypervisor << hypervisor if hypervisor
          hypervisor
        end

        # Adds operating system from vmware api info
        def self.add_os(ost, info)
          ost.os << if info&.osType.to_s.include?('win32')
                      :mswin
                    else
                      :linux
                    end
        end
      end
    end
  end
end
