module ManageIQ::Providers::Vmware::InfraManager::VmOrTemplateShared::Operations
  extend ActiveSupport::Concern

  include_concern "Configuration"
  include_concern "Power"
  include_concern "Relocation"

  def raw_set_custom_field(attribute, value)
    run_command_via_parent(:vm_set_custom_field, :attribute => attribute, :value => value)
  end

  included do
    supports :terminate do
      unsupported_reason_add(:terminate, unsupported_reason(:control)) unless supports?(:control)
    end
  end

  def raw_clone(name, folder, pool = nil, host = nil, datastore = nil, powerOn = false, template_flag = false, transform = nil, config = nil, customization = nil, disk = nil)
    folder_mor    = folder.ems_ref_obj    if folder.respond_to?(:ems_ref_obj)
    pool_mor      = pool.ems_ref_obj      if pool.respond_to?(:ems_ref_obj)
    host_mor      = host.ems_ref_obj      if host.respond_to?(:ems_ref_obj)
    datastore_mor = datastore.ems_ref_obj if datastore.respond_to?(:ems_ref_obj)
    run_command_via_parent(:vm_clone, :name => name, :folder => folder_mor, :pool => pool_mor, :host => host_mor, :datastore => datastore_mor, :powerOn => powerOn, :template => template_flag, :transform => transform, :config => config, :customization => customization, :disk => disk)
  end

  def raw_mark_as_template
    run_command_via_parent(:vm_mark_as_template)
  end

  def raw_mark_as_vm(pool, host = nil)
    pool_mor = pool.ems_ref_obj if pool.respond_to?(:ems_ref_obj)
    host_mor = host.ems_ref_obj if host.respond_to?(:ems_ref_obj)
    run_command_via_parent(:vm_mark_as_vm, :pool => pool_mor, :host => host_mor)
  end

  def raw_unregister
    run_command_via_parent(:vm_unregister)
  end

  def raw_destroy
    run_command_via_parent(:vm_destroy)
  end

  def raw_rename(new_name)
    run_command_via_parent(:vm_rename, :new_name => new_name)
  end

  def log_user_event(event_message)
    with_provider_object do |vim_vm|
      vim_vm.logUserEvent(event_message)
    end
    nil
  end
end
