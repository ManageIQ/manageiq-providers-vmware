module ManageIQ::Providers
  module Vmware
    class InfraManager::Refresher < ManageIQ::Providers::BaseManager::Refresher
      # This is a helper method to allow for developers to run a full refresh from
      # a rails console with the typical `EmsRefresh.refresh(ems)` pattern.
      #
      # In production this is not used as the RefreshWorker processes full refreshes
      # directly by restarting the collector thread, not by actually calling #refresh.
      #
      # If you need to force a full refresh in production mode you can still queue a full
      # refresh with `EmsRefresh.queue_refresh(ems)` or `ems.queue_refresh`
      def refresh
        raise NotImplementedError, "not implemented in production mode" if Rails.env.production?

        ems_by_ems_id.each do |_ems_id, ems|
          collector = ems.class::Inventory::Collector.new(ems)
          collector.refresh
        end
      end
    end
  end
end
