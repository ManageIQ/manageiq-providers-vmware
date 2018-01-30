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

  def hardware
    @hardware ||= persister.hardwares.find_or_build(inventory_object)
  end

  def operating_system
    @operating_system ||= persister.operating_systems.find_or_build(inventory_object)
  end

  alias vm_or_template inventory_object

  def parse_property_change(name, op, val)
    super

    case name
    when "config.version"
      virtual_hw_version = val.to_s.split('-').last
      hardware.assign_attributes(:virtual_hw_version => virtual_hw_version)
    when /resourceConfig/
      parse_resource_config(name, op, val)
    when "summary.config.guestFullName"
      guest_full_name = val.nil? ? "Other" : val
      operating_system.assign_attributes(:product_name => guest_full_name)
    when "summary.config.memorySizeMB"
      hardware.assign_attributes(:memory_mb => val)
    when "summary.config.template"
      template = val
      type = template ? ems.class::Template.name : ems.class::Vm.name

      vm_or_template.template = template
      vm_or_template.type = type
    when "summary.config.uuid"
      vm_or_template.uid_ems = val
    when "summary.config.vmPathName"
      pathname = val
      _, location = VmOrTemplate.repository_parse_path(pathname) unless pathname.nil?
      vm_or_template.location = location
    when "summary.runtime.bootTime"
      vm_or_template.boot_time = val
    when "summary.runtime.host"
      host_ref = val._ref unless val.nil?
      vm_or_template.host = persister.hosts.find_or_build(host_ref)
    when "summary.runtime.powerState"
      vm_or_template.raw_power_state = val
    end
  end

  def parse_resource_config(name, _op, val)
    case name
    when 'resourceConfig.cpuAllocation.expandableReservation'
      vm_or_template.cpu_reserve_expand = val
    when 'resourceConfig.cpuAllocation.limit'
      vm_or_template.cpu_limit = val
    when 'resourceConfig.cpuAllocation.reservation'
      vm_or_template.cpu_reserve = val
    when 'resourceConfig.cpuAllocation.shares.level'
      vm_or_template.cpu_shares_level = val
    when 'resourceConfig.cpuAllocation.shares.shares'
      vm_or_template.cpu_shares = val
    when 'resourceConfig.memoryAllocation.expandableReservation'
      vm_or_template.memory_reserve_expand = val
    when 'resourceConfig.memoryAllocation.limit'
      vm_or_template.memory_limit = val
    when 'resourceConfig.memoryAllocation.reservation'
      vm_or_template.memory_reserve = val
    when 'resourceConfig.memoryAllocation.shares.level'
      vm_or_template.memory_shares_level = val
    when 'resourceConfig.memoryAllocation.shares.shares'
      vm_or_template.memory_shares = val
    end
  end
end
