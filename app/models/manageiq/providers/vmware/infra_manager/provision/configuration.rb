module ManageIQ::Providers::Vmware::InfraManager::Provision::Configuration
  extend ActiveSupport::Concern

  include_concern 'Container'
  include_concern 'Network'
  include_concern 'Disk'

  def reconfigure_container_on_destination?
    # Do we need to perform a post-clone hardware reconfigure on the new VM?
    [:cpu_limit, :memory_limit, :cpu_reserve, :memory_reserve].any? do |k|
      return false unless options.key?(k)
      destination.send(k) != options[k]
    end
  end

  def reconfigure_disk_on_destination?
    return false unless options.key?(:allocated_disk_storage)

    # TODO: short-term fix to only enable :allocated_disk_storage in machines that have a single hard disk
    #   in the long-term it should be able to deal with multiple hard disks
    if vm.hardware.disks.where(:device_type => "disk").length != 1
      _log.info("custom disk size is currently only supported for machines that have a single hard disk")
      return false
    end

    default_size = vm.hardware.disks.find_by(:device_type => "disk").size / (1024**3)
    get_option(:allocated_disk_storage).to_f > default_size
  end

  def reconfigure_hardware
    config_spec = VimHash.new("VirtualMachineConfigSpec") do |vmcs|
      set_cpu_and_memory_allocation(vmcs) if reconfigure_container_on_destination?
      set_disk_allocation(vm, vmcs) if reconfigure_disk_on_destination?
    end
    return if config_spec.empty?

    _log.info("Calling VM reconfiguration")
    dump_obj(config_spec, "#{_log.prefix} Post-create Config spec: ", $log, :info)
    vm.spec_reconfigure(config_spec)
  end
end
