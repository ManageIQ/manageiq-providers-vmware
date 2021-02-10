require 'VMwareWebService/MiqVim'
require 'http-access2' # Required in case it is not already loaded

module ManageIQ::Providers
  module Vmware
    class InfraManager::Refresher < ManageIQ::Providers::BaseManager::Refresher
      def refresh
        ems_by_ems_id.each do |_ems_id, ems|
          saver     = ems.class::Inventory::Saver.new(:threaded => false)
          collector = ems.class::Inventory::Collector.new(ems, saver)
          collector.refresh
        end
      end
    end
  end
end
