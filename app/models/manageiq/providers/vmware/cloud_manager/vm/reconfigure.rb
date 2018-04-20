module ManageIQ::Providers::Vmware::CloudManager::Vm::Reconfigure
  # Show Reconfigure VM task
  def reconfigurable?
    true
  end

  def max_cpu_cores_per_socket(_total_vcpus = nil)
    128
  end

  def max_total_vcpus
    128
  end

  def max_vcpus
    128
  end

  def max_memory_mb
    4.terabyte / 1.megabyte
  end

  def disk_types
    ['LSI Logic Parallel SCSI']
  end

  def disk_default_type
    'LSI Logic Parallel SCSI'
  end

  def validate_config_spec(options)
    if vm_powered_on?
      if options[:number_of_cpus]
        number_of_cpus   = options[:number_of_cpus].to_i
        cores_per_socket = options[:cores_per_socket].to_i
        raise MiqException::MiqVmError, 'CPU Hot-Add not enabled' if number_of_cpus != cpu_total_cores && !cpu_hot_add_enabled
        raise MiqException::MiqVmError, 'CPU Hot-Remove not enabled' if number_of_cpus < cpu_total_cores && !cpu_hot_remove_enabled
        raise MiqException::MiqVmError, 'Cannot change CPU cores per socket on a running VM' if cores_per_socket != cpu_cores_per_socket
      end

      if options[:vm_memory]
        vm_memory = options[:vm_memory].to_i
        raise MiqException::MiqVmError, 'Memory Hot-Add not enabled'             if vm_memory > ram_size && !memory_hot_add_enabled
        raise MiqException::MiqVmError, 'Cannot remove memory from a running VM' if vm_memory < ram_size
      end
    end

    raise MiqException::MiqVmError, 'Cannot resize disk of VM with shapshots' if options[:disk_resize] && !snapshots.empty?
  end

  def build_config_spec(options)
    validate_config_spec(options)

    # Virtual hardware modifications.
    new_hw          = {}
    new_hw[:memory] = { :quantity_mb => options[:vm_memory] } if options[:vm_memory]
    new_hw[:cpu]    = { :num_cores => options[:number_of_cpus], :cores_per_socket => options[:cores_per_socket] } if options[:number_of_cpus]
    if (%i(disk_add disk_resize disk_remove) & options.keys).any?
      new_hw[:disk] = []
      Array(options[:disk_add])   .each_with_object(new_hw[:disk]) { |d, res| res << { :capacity_mb => d[:disk_size_in_mb].to_i } }
      Array(options[:disk_resize]).each_with_object(new_hw[:disk]) { |d, res| res << { :id => disk_id(d[:disk_name]), :capacity_mb => d[:disk_size_in_mb].to_i } }
      Array(options[:disk_remove]).each_with_object(new_hw[:disk]) { |d, res| res << { :id => disk_id(d[:disk_name]), :capacity_mb => -1 } }
    end

    new_hw.empty? ? {} : { :hardware => new_hw }
  end

  def disk_id(disk_name)
    disk = disks.detect { |d| d.filename == disk_name }
    # Disk location is stored as "{addr}/{parent_addr}/{disk_id}" e.g. "0/3/2000"
    disk.location.to_s.split('/').last
  end
end
