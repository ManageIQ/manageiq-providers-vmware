class ManageIQ::Providers::Vmware::InfraManager::OvfServiceTemplate < ServiceTemplateGeneric
  def self.default_provisioning_entry_point(_service_type)
    '/Service/Generic/StateMachines/GenericLifecycle/provision'
  end

  # create ServiceTemplate and supporting ServiceResources and ResourceActions
  # options
  #   :name
  #   :description
  #   :service_template_catalog_id
  #   :config_info
  #     :provision
  #       :dialog_id or :dialog
  #       :ovf_template_id or :ovf_template
  #
  def self.create_catalog_item(options, _auth_user)
    options = options.merge(:service_type => 'atomic', :prov_type => 'generic_ovf_template')
    config_info = validate_config_info(options[:config_info])
    enhanced_config = config_info.deep_merge(
      :provision => {
        :configuration_template => ovf_template_from_config_info(config_info)
      }
    )

    transaction do
      create_from_options(options).tap do |service_template|
        service_template.create_resource_actions(enhanced_config)
      end
    end
  end

  def self.validate_config_info(info)
    raise ArgumentError, _(":provision section is missing from :config_info in options hash.") if info[:provision].blank?
    raise ArgumentError, _("Resource pool is required for content library item deployment.") if info.dig(:provision, :resource_pool_id).blank?

    info[:provision][:fqname] ||= default_provisioning_entry_point(SERVICE_TYPE_ATOMIC)
    info[:provision][:accept_all_eula] ||= false

    # TODO: Add more validation for required fields
    info
  end
  private_class_method :validate_config_info

  def self.ovf_template_from_config_info(info)
    ovf_template_id = info[:provision][:ovf_template_id]
    ovf_template_id ? OrchestrationTemplate.find(ovf_template_id) : info[:provision][:ovf_template]
  end
  private_class_method :ovf_template_from_config_info

  def ovf_template
    @ovf_template ||= resource_actions.find_by(:action => "Provision").try(:configuration_template)
  end

  def manager
    @manager ||= ovf_template.try(:ext_management_system)
  end

  def update_catalog_item(options, _auth_user = nil)
    config_info = validate_update_config_info(options)
    config_info[:provision][:configuration_template] ||= ovf_template_from_config_info(config_info) if config_info.key?(:provision)
    options[:config_info] = config_info

    super
  end

  private

  def ovf_template_from_config_info(info)
    self.class.send(:ovf_template_from_config_info, info)
  end

  def validate_update_config_info(options)
    opts = super
    self.class.send(:validate_config_info, opts)
  end

  def update_service_resources(_config_info, _auth_user = nil)
    # do nothing since no service resources for this template
  end

  def update_from_options(params)
    options[:config_info] = Hash[params[:config_info].collect { |k, v| [k, v.except(:configuration_template)] }]
    update!(params.except(:config_info))
  end
end
