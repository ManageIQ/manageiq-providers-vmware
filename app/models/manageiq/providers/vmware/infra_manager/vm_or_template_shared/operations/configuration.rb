module ManageIQ::Providers::Vmware::InfraManager::VmOrTemplateShared::Operations::Configuration
  extend ActiveSupport::Concern

  def raw_set_memory(mb)
    run_command_via_parent(:vm_set_memory, :value => mb)
  end

  def raw_set_number_of_cpus(num)
    run_command_via_parent(:vm_set_num_cpus, :value => num)
  end

  def raw_connect_all_devices
    run_command_via_parent(:vm_connect_all)
  end

  def raw_disconnect_all_devices
    run_command_via_parent(:vm_disconnect_all)
  end

  def raw_connect_cdroms
    run_command_via_parent(:vm_connect_cdrom)
  end

  def raw_disconnect_cdroms
    run_command_via_parent(:vm_disconnect_cdrom)
  end

  def raw_connect_floppies
    run_command_via_parent(:vm_connect_floppy)
  end

  def raw_disconnect_floppies
    run_command_via_parent(:vm_disconnect_floppy)
  end

  def raw_add_disk(disk_name, disk_size_mb, options = {})
    if options[:datastore]
      datastore = ext_management_system.hosts.collect do |h|
        h.writable_accessible_storages.find_by(:name => options[:datastore])
      end.uniq.compact.first
      raise _("Datastore does not exist or cannot be accessed, unable to add disk") unless datastore
    end

    run_command_via_parent(:vm_add_disk, :diskName => disk_name, :diskSize => disk_size_mb,
        :thinProvisioned => options[:thin_provisioned], :dependent => options[:dependent],
        :persistent => options[:persistent], :bootable => options[:bootable], :datastore => datastore,
        :interface => options[:interface])
  end

  def raw_remove_disk(disk_name, options = {})
    options[:delete_backing] = true if options[:delete_backing].nil?
    run_command_via_parent(:vm_remove_disk, :diskName => disk_name, :delete_backing => options[:delete_backing])
  end

  def raw_resize_disk(disk_name, disk_size_mb, _options = {})
    run_command_via_parent(:vm_resize_disk, :diskName => disk_name, :newSizeInKb => disk_size_mb * 1024)
  end

  def raw_reconfigure(spec)
    run_command_via_parent(:vm_reconfigure, :spec => spec)
  end
end
