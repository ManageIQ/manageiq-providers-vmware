module ManageIQ::Providers::Vmware::InfraManager::Provision::Cloning
  def do_clone_task_check(clone_task_mor)
    source.with_provider_connection do |vim|
      begin
        task_props = ["info.state", "info.error", "info.result", "info.progress", "info.completeTime"]
        task = vim.getMoProp(clone_task_mor, task_props)

        task_info  = task&.info
        task_state = task_info&.state

        case task_state
        when TaskInfoState::Success
          phase_context[:new_vm_ems_ref] = task_info&.result&.to_s
          phase_context[:clone_vm_task_completion_time] = task_info&.completeTime&.to_s
          return true
        when TaskInfoState::Error
          raise "VM Clone Failed: #{task_info&.error&.localizedMessage}"
        when TaskInfoState::Running
          progress = task_info&.progress
          return false, progress.nil? ? "beginning" : "#{progress}% complete"
        else
          return false, task_state
        end
      end
    end
  end

  def find_destination_in_vmdb
    # Check that the EMS inventory is as up to date as the CloneVM_Task completeTime
    # to prevent issues with post-provision depending on data that isn't in VMDB yet
    return if source.ext_management_system.last_inventory_date < phase_context[:clone_vm_task_completion_time]

    source.ext_management_system&.vms_and_templates&.find_by(:ems_ref => phase_context[:new_vm_ems_ref])
  end

  def prepare_for_clone_task
    raise MiqException::MiqProvisionError, "Provision Request's Destination VM Name=[#{dest_name}] cannot be blank" if dest_name.blank?
    raise MiqException::MiqProvisionError, "A VM with name: [#{dest_name}] already exists" if source.ext_management_system.vms.where(:name => dest_name).any?

    clone_options = {
      :name            => dest_name,
      :cluster         => dest_cluster,
      :host            => dest_host,
      :datastore       => dest_datastore,
      :folder          => dest_folder,
      :pool            => dest_resource_pool,
      :storage_profile => dest_storage_profile,
      :config          => build_config_spec,
      :customization   => build_customization_spec
    }

    # Determine if we are doing a linked-clone provision
    clone_options[:linked_clone] = get_option(:linked_clone).to_s == 'true'
    clone_options[:snapshot]     = get_selected_snapshot if clone_options[:linked_clone]

    validate_customization_spec(clone_options[:customization])

    clone_options
  end

  def dest_resource_pool
    resource_pool = ResourcePool.find_by(:id => get_option(:placement_rp_name))
    return resource_pool if resource_pool

    dest_cluster.try(:default_resource_pool) || dest_host.default_resource_pool
  end

  def dest_storage_profile
    storage_profile_id = get_option(:placement_storage_profile)
    StorageProfile.find_by(:id => storage_profile_id) unless storage_profile_id.nil?
  end

  def dest_folder
    ems_folder = EmsFolder.find_by(:id => get_option(:placement_folder_name))
    return ems_folder if ems_folder

    dc = dest_cluster.try(:parent_datacenter) || dest_host.parent_datacenter

    # Pick the parent folder in the destination datacenter
    find_folder("#{dc.folder_path}/vm", dc)
  end

  def find_folder(folder_path, datacenter)
    EmsFolder.where(:name => File.basename(folder_path), :ems_id => source.ems_id).detect do |f|
      f.folder_path == folder_path && f.parent_datacenter == datacenter
    end
  end

  def log_clone_options(clone_options)
    _log.info("Provisioning [#{source.name}] to [#{clone_options[:name]}]")
    _log.info("Source Template:            [#{source.name}]")
    _log.info("Destination VM Name:        [#{clone_options[:name]}]")
    _log.info("Destination Cluster:        [#{clone_options[:cluster].name} (#{clone_options[:cluster].ems_ref})]")   if clone_options[:cluster]
    _log.info("Destination Host:           [#{clone_options[:host].name} (#{clone_options[:host].ems_ref})]")         if clone_options[:host]
    _log.info("Destination Datastore:      [#{clone_options[:datastore].name} (#{clone_options[:datastore].ems_ref})]")
    _log.info("Destination Folder:         [#{clone_options[:folder].name}] (#{clone_options[:folder].ems_ref})")
    _log.info("Destination Resource Pool:  [#{clone_options[:pool].name} (#{clone_options[:pool].ems_ref})]")
    _log.info("Power on after cloning:     [#{clone_options[:power_on].inspect}]")
    _log.info("Create Linked Clone:        [#{clone_options[:linked_clone].inspect}]")
    _log.info("Selected Source Snapshot:   [#{clone_options[:snapshot].name} (#{clone_options[:snapshot].ems_ref})]") if clone_options[:linked_clone]

    cust_dump = clone_options[:customization].try(:dup)
    cust_dump.try(:delete, 'encryptionKey')

    dump_obj(clone_options[:transform], "#{_log.prefix} Transform: ",          $log, :info)
    dump_obj(clone_options[:config],    "#{_log.prefix} Config spec: ",        $log, :info)
    dump_obj(cust_dump,                 "#{_log.prefix} Customization spec: ", $log, :info, :protected => {:path => /[Pp]assword\]\[value\]/})
    dump_obj(options,                   "#{_log.prefix} Prov Options: ",       $log, :info, :protected => {:path => workflow_class.encrypted_options_field_regs})
  end

  def start_clone(clone_options)
    vim_clone_options = {
      :name     => clone_options[:name],
      :wait     => MiqProvision::CLONE_SYNCHRONOUS,
      :template => self.create_template?
    }

    [:config, :customization, :linked_clone].each { |key| vim_clone_options[key] = clone_options[key] }

    [:folder, :host, :pool].each do |key|
      ci = clone_options[key]
      next if ci.nil?

      vim_clone_options[key] = ci.ems_ref_obj
    end

    if clone_options[:snapshot]
      ci = clone_options[:snapshot]
      vim_clone_options[:snapshot] = VimString.new(ci.ems_ref, ci.ems_ref_type, :ManagedObjectReference) if ci.ems_ref.present? && ci.ems_ref_type.present?
    end

    vim_clone_options[:datastore]       = datastore_ems_ref(clone_options)
    vim_clone_options[:disk]            = build_disk_relocate_spec(vim_clone_options[:datastore])
    vim_clone_options[:storage_profile] = build_storage_profile(clone_options[:storage_profile]) unless clone_options[:storage_profile].nil?

    task_mor = clone_vm(vim_clone_options)
    _log.info("Provisioning completed for [#{vim_clone_options[:name]}] from source [#{source.name}]") if MiqProvision::CLONE_SYNCHRONOUS
    task_mor
  end

  def clone_vm(vim_clone_options)
    vim_clone_options = {:power_on => false, :template => false, :wait => true}.merge(vim_clone_options)

    cspec = VimHash.new('VirtualMachineCloneSpec') do |cs|
      cs.powerOn       = vim_clone_options[:power_on].to_s
      cs.template      = vim_clone_options[:template].to_s
      cs.config        = vim_clone_options[:config]        if vim_clone_options[:config]
      cs.customization = vim_clone_options[:customization] if vim_clone_options[:customization]
      cs.snapshot      = vim_clone_options[:snapshot]      if vim_clone_options[:snapshot]
      cs.location = VimHash.new('VirtualMachineRelocateSpec') do |csl|
        csl.datastore    = vim_clone_options[:datastore]  if vim_clone_options[:datastore]
        csl.host         = vim_clone_options[:host]       if vim_clone_options[:host]
        csl.pool         = vim_clone_options[:pool]       if vim_clone_options[:pool]
        csl.disk         = vim_clone_options[:disk]       if vim_clone_options[:disk]
        csl.transform    = vim_clone_options[:transform]  if vim_clone_options[:transform]
        csl.diskMoveType = VimString.new('createNewChildDiskBacking', "VirtualMachineRelocateDiskMoveOptions") if vim_clone_options[:linked_clone] == true
        csl.profile      = vim_clone_options[:storage_profile] if vim_clone_options[:storage_profile]
      end
    end

    task_mor = nil

    source.with_provider_object do |vim_vm|
      task_mor = vim_vm.cloneVM_raw(vim_clone_options[:folder], vim_clone_options[:name], cspec, vim_clone_options[:wait])

      # task_mor is a VimString xsiType: ManagedObjectReference vimType: Task but
      # we have to serialize just the String to the phase_context
      task_mor = task_mor.to_s if task_mor
    end

    task_mor
  end

  def datastore_ems_ref(clone_opts)
    datastore = Storage.find_by(:id => clone_opts[:datastore].id)
    datastore.try(:ems_ref)
  end

  def get_selected_snapshot
    selected_snapshot = get_option(:snapshot).to_s.downcase
    if selected_snapshot.to_i > 0
      ss = Snapshot.find_by_id(selected_snapshot)
      raise MiqException::MiqProvisionError, "Unable to load requested snapshot <#{selected_snapshot}:#{get_option_last(:snapshot)}> for linked-clone processing." if ss.nil?
    else
      first = source.snapshots.first
      ss = first.get_current_snapshot unless first.blank?
    end

    ss
  end

  def build_storage_profile(storage_profile)
    VimArray.new('ArrayOfVirtualMachineProfileSpec') do |vm_profile_spec_array|
      vm_profile_spec_array << VimHash.new('VirtualMachineDefinedProfileSpec') do |vm_profile_spec|
        vm_profile_spec.profileId = storage_profile.ems_ref
      end
    end
  end
end
