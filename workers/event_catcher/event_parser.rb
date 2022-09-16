class EventParser
  def self.parse_event(event)
    event_type = event.class.wsdl_name
    is_task    = event_type == "TaskEvent"

    if is_task
      sub_event_type = event.info&.name

      # Handle special cases
      case sub_event_type
      when nil
        # Handle cases wehre event name is missing
        sub_event_type   = "PowerOnVM_Task"    if event.fullFormattedMessage.to_s.downcase == "task: power on virtual machine"
        sub_event_type ||= "DrsMigrateVM_Task" if event.info&.descriptionId == "Drm.ExecuteVMotionLRO"
        if sub_event_type.nil?
          sub_event_type = "TaskEvent"
        end
      when "Rename_Task", "Destroy_Task"
        # Handle case where event name is overloaded
        sub_event_name = event.info.descriptionId.split(".").first
        sub_event_name = "VM"      if sub_event_name == "VirtualMachine"
        sub_event_name = "Cluster" if sub_event_name == "ClusterComputeResource"
        sub_event_type.gsub!(/_/, "#{sub_event_name}_")
      end

      event_type = sub_event_type
    elsif event_type == "EventEx"
      sub_event_type = event.eventTypeId
      event_type     = sub_event_type if sub_event_type.present?
    end

    result = {
      :event_type => event_type,
      :chain_id   => event.chainId,
      :is_task    => is_task,
      :source     => "VC",
      :message    => event.fullFormattedMessage,
      :timestamp  => event.createdTime,
      :full_data  => event.props
    }

    result[:username] = event.userName if event.userName.present?

    # Get the vm information
    vm_key = "vm"          if event.props.key?("vm")
    vm_key = "sourceVm"    if event.props.key?("sourceVm")
    vm_key = "srcTemplate" if event.props.key?("srcTemplate")
    if vm_key
      vm_data = event.send(vm_key)

      result[:vm_ems_ref]  = vm_data&.vm                 if vm_data&.vm
      result[:vm_name]     = CGI.unescape(vm_data&.name) if vm_data&.name
      result[:vm_location] = vm_data&.path               if vm_data&.path
      result[:vm_uid_ems]  = vm_data&.uuid               if vm_data&.uuid

      result
    end

    # Get the dest vm information
    has_dest = false
    if %w[sourceVm srcTemplate].include?(vm_key)
      vm_data = event.vm
      if vm_data
        result[:dest_vm_ems_ref]  = vm_data&.vm                 if vm_data&.vm
        result[:dest_vm_name]     = CGI.unescape(vm_data&.name) if vm_data&.name
        result[:dest_vm_location] = vm_data&.path               if vm_data&.path
      end

      has_dest = true
    elsif event.props.key?("destName")
      result[:dest_vm_name] = event.destName
      has_dest = true
    end

    if event.props.key?(:host)
      result[:host_name]    = event.host.name
      result[:host_ems_ref] = event.host.host
    end

    if has_dest
      host_data = event.props["destHost"] || event.props["host"]
      if host_data
        result[:dest_host_ems_ref] = host_data["host"]
        result[:dest_host_name]    = host_data["name"]
      end
    end

    result
  end
end
