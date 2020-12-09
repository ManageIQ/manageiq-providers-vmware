class ManageIQ::Providers::Vmware::InfraManager::OvfService < ServiceGeneric
  delegate :ovf_template, :manager, :to => :service_template, :allow_nil => true

  CONFIG_OPTIONS_WHITELIST = %i[
    accept_all_eula
    datacenter_id
    disk_format
    ems_folder_id
    host_id
    network_id
    resource_pool_id
    storage_id
    vm_name
  ].freeze

  # A chance for taking options from automate script to override options from a service dialog
  def preprocess(action, new_options = {})
    return unless action == ResourceAction::PROVISION

    if new_options.present?
      _log.info("Override with new options:\n#{new_options}")
    end

    save_action_options(action, new_options)
  end

  def execute(action)
    return unless action == ResourceAction::PROVISION

    deploy_library_item_queue
  end

  def deploy_library_item_queue
    task_options = {:action => "Deploying VMware Content Library Item", :userid => "system"}
    queue_options = {
      :class_name  => self.class.name,
      :instance_id => id,
      :method_name => "deploy_library_item",
      :args        => {},
      :role        => "ems_operations",
      :queue_name  => manager.queue_name_for_ems_operations,
      :zone        => manager.my_zone
    }

    task_id = MiqTask.generic_action_with_callback(task_options, queue_options)
    update(:options => options.merge(:deploy_task_id => task_id))
  end

  def deploy_library_item(_options)
    _log.info("OVF template provisioning with template ID: [#{ovf_template.id}] name:[#{ovf_template.name}] was initiated.")
    opts = provision_options
    _log.info("VMware Content Library OVF Tempalte provisioning with options:\n#{opts}")

    @deploy_response = ovf_template.deploy(opts).to_hash
    _log.info("Content Library request response: #{@deploy_response}")
    update(:options => options.merge(:deploy_response => @deploy_response))
  rescue VSphereAutomation::ApiError => e
    _log.error("Failed to deploy content library template(#{ovf_template.name}), error: #{e}")
    raise MiqException::MiqOrchestrationProvisionError, "Content library OVF template deployment failed: #{e}"
  end

  def check_completed(action)
    return [true, 'not supported'] unless action == ResourceAction::PROVISION
    return [false, nil] if deploy_task.state != "Finished"

    message = deploy_response&.dig(:value, :succeeded) ? nil : deploy_response&.dig(:value, :error).to_json || deploy_response&.to_json || deploy_task.message
    [true, message]
  end

  def refresh(_action)
  end

  def check_refreshed(action)
    return [true, nil] unless deploy_response&.dig(:value, :succeeded)

    dest = find_destination_in_vmdb
    if dest
      add_resource!(dest, :name => action)

      if dest.kind_of?(ResourcePool)
        dest.vms.each { |vm| add_resource!(vm, :name => action) }
      end

      [true, nil]
    else
      [false, nil]
    end
  end

  private

  def deploy_response
    @deploy_response ||= options[:deploy_response]
  end

  def deploy_task
    @deploy_task ||= MiqTask.find_by(:id => options[:deploy_task_id])
  end

  def find_destination_in_vmdb
    target_model_class.find_by(:ems_id => manager.id, :ems_ref => deploy_response.dig(:value, :resource_id, :id))
  end

  def target_model_class
    case deploy_response.dig(:value, :resource_id, :type)
    when "VirtualMachine"
      manager.class::Vm
    when "VirtualApp"
      manager.class::ResourcePool
    end
  end

  def get_action_options(action)
    options[action_option_key(action)]
  end

  def provision_options
    @provision_options ||= get_action_options(ResourceAction::PROVISION)
  end

  def save_action_options(action, overrides)
    return unless action == ResourceAction::PROVISION

    action_options = options.fetch_path(:config_info, action.downcase.to_sym).slice(*CONFIG_OPTIONS_WHITELIST).with_indifferent_access
    action_options.deep_merge!(parse_dialog_options)
    action_options.deep_merge!(overrides)
    validate_target_name(action_options)

    options[action_option_key(action)] = action_options
    save!
  end

  def validate_target_name(options)
    unless ovf_template.target_name_valid?(options[:vm_name], options[:ems_folder_id])
      _log.warn("A target with name [#{options[:vm_name]}] already exists.")
      options[:vm_name] = "#{options[:vm_name]}_#{Time.zone.now.iso8601(6)}"
      _log.warn("Target name has been changed to [#{options[:vm_name]}]")
    end
  end

  def parse_dialog_options
    dialog_options = options[:dialog] || {}
    options = {}

    CONFIG_OPTIONS_WHITELIST.each do |r|
      options[r] = dialog_options["dialog_#{r}"] if dialog_options["dialog_#{r}"].present?
    end
    options
  end

  def action_option_key(action)
    "#{action.downcase}_options".to_sym
  end
end
