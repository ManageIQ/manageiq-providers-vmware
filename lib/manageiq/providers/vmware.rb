require "manageiq/providers/vmware/engine"
require "manageiq/providers/vmware/version"

module ManageIQ
  module Providers
    module Vmware
      def self.seed
        MiqServer.my_server.capabilities["vix_disk_lib"] = vix_disk_lib_installed?
        MiqServer.my_server.save!
      end

      def self.vix_disk_lib_installed?
        require "ffi-vix_disk_lib"
        true
      rescue LoadError
        false
      end
    end
  end
end
