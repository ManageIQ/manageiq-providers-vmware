class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::VirtualMachine < ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser::ManagedEntity
  private

  def inventory_collection
    persister.vms_and_templates
  end

  def base_result_hash
    {
      :ems_ref => manager_ref,
    }
  end

  def parse_property_change(name, op, val)
    result = super

    case name
    when "summary.config.template"
      template = val
      result[:template] = template

      type = template ? ems.class::Template.name : ems.class::Vm.name
      result[:type] = type
    when "summary.config.uuid"
      result[:uid_ems] = val
    when "summary.runtime.powerState"
      result[:raw_power_state] = val
    end

    result
  end
end
