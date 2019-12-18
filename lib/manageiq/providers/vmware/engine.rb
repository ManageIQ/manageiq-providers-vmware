module ManageIQ
  module Providers
    module Vmware
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Vmware

        def self.vmdb_plugin?
          true
        end

        def self.plugin_name
          _('VMware Provider')
        end

        def self.seedable_classes
          %w[ManageIQ::Providers::Vmware]
        end
      end
    end
  end
end
