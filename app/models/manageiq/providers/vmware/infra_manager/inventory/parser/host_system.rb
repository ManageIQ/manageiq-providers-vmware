class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::HostSystem < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def inventory_collection
    persister.hosts
  end

  def base_result_hash
    {
      :ems_ref => manager_ref,
    }
  end

  alias host inventory_object

  def parse_property_change(name, op, val)
    super

    case name
    when "config.network.dnsConfig.hostName"
      host.hostname = val
    when "hardware.systemInfo.uuid"
      host.uid_ems = val
    when "summary.config.product.build"
      host.vmm_buildnumber = val
    when "summary.config.product.name"
      host.vmm_product = val.to_s.gsub(/^VMware\s*/i, "")
    when "summary.config.product.vendor"
      vendor = val.to_s.split(",").first.to_s.downcase
      vendor = "unknown" unless Host::VENDOR_TYPES.include?(vendor)

      host.vmm_vendor = vendor
    when "summary.config.product.version"
      host.vmm_version = val
    when "summary.runtime.connectionState"
      connection_state = val

      host.connection_state = connection_state
      host.power_state      = connection_state == "connected" ? "on" : "off"
    when "summary.runtime.inMaintenanceMode"
      host.maintenance = val
    end
  end
end
