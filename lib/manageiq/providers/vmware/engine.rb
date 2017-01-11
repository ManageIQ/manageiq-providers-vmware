module ManageIQ
  module Providers
    module Vmware
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Vmware
      end
    end
  end
end
