require "manageiq/providers/vmware/engine"
require "manageiq/providers/vmware/version"

module ManageIQ
  module Providers
    module Vmware
      def self.seed
        MiqServer.my_server.update!(:has_vix_disk_lib => vix_disk_lib_installed?)
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
