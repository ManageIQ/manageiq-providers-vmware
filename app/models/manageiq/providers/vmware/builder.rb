class ManageIQ::Providers::Vmware::Builder
  class << self
    def build_inventory(ems, target)
      case target
      when ManageIQ::Providers::Vmware::CloudManager
        cloud_manager_inventory(ems, target)
      when ManageIQ::Providers::Vmware::NetworkManager
        inventory(
          ems,
          target,
          ManageIQ::Providers::Vmware::Inventory::Collector::NetworkManager,
          ManageIQ::Providers::Vmware::Inventory::Persister::NetworkManager,
          [ManageIQ::Providers::Vmware::Inventory::Parser::NetworkManager]
        )
      else
        # Fallback to ems refresh
        cloud_manager_inventory(ems, target)
      end
    end

    private

    def cloud_manager_inventory(ems, target)
      inventory(
        ems,
        target,
        ManageIQ::Providers::Vmware::Inventory::Collector::CloudManager,
        ManageIQ::Providers::Vmware::Inventory::Persister::CloudManager,
        [ManageIQ::Providers::Vmware::Inventory::Parser::CloudManager]
      )
    end

    def inventory(manager, raw_target, collector_class, persister_class, parsers_classes)
      collector = collector_class.new(manager, raw_target)
      persister = persister_class.new(manager, raw_target)

      ::ManageIQ::Providers::Vmware::Inventory.new(
        persister,
        collector,
        parsers_classes.map(&:new)
      )
    end
  end
end
