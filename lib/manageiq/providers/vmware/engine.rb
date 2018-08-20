module ManageIQ
  module Providers
    module Vmware
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Vmware

        def self.plugin_name
          _('VMware Provider')
        end
      end
    end
  end
end
