require "manageiq/providers/vmware/engine"
require "manageiq/providers/vmware/version"

module ManageIQ
  module Providers
    module Vmware
      def self.seed
        MiqServer.my_server.update!(:has_vix_disk_lib => vix_disk_lib_installed?)
      end

      def self.vix_disk_lib_installed?
        return false unless RbConfig::CONFIG["host_os"].match?(/linux/i)

        begin
          require 'VMwareWebService/VixDiskLib/VixDiskLib'
          return true
        rescue Exception
          # It is ok if we hit an error, it just means the library is not available to load.
        end

        false
      end
    end
  end
end
