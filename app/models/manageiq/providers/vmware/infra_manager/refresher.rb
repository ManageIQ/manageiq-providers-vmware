require 'VMwareWebService/MiqVim'
require 'http-access2' # Required in case it is not already loaded

module ManageIQ::Providers
  module Vmware
    class InfraManager::Refresher < ManageIQ::Providers::BaseManager::Refresher
      # Development helper method for setting up the selector specs for VC
      def self.init_console(*_)
        # TODO remove from core
      end

      def refresh
        collector_klass = ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector

        ems_by_ems_id.each do |_ems_id, ems|
          collector = collector_klass.new(ems)
          collector.refresh
        end
      end
    end
  end
end
