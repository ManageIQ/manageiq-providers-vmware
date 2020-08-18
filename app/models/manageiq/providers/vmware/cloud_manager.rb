class ManageIQ::Providers::Vmware::CloudManager < ManageIQ::Providers::CloudManager
  require_nested :AvailabilityZone
  require_nested :OrchestrationServiceOptionConverter
  require_nested :OrchestrationStack
  require_nested :OrchestrationTemplate
  require_nested :EventCatcher
  require_nested :EventParser
  require_nested :RefreshWorker
  require_nested :Refresher
  require_nested :Template
  require_nested :Vm

  include ManageIQ::Providers::Vmware::ManagerAuthMixin
  include ManageIQ::Providers::Vmware::CloudManager::ManagerEventsMixin
  include HasNetworkManagerMixin

  has_many :snapshots, :through => :vms_and_templates

  before_create :ensure_managers

  def ensure_network_manager
    build_network_manager(:type => 'ManageIQ::Providers::Vmware::NetworkManager') unless network_manager
  end

  def self.ems_type
    @ems_type ||= "vmware_cloud".freeze
  end

  def self.description
    @description ||= "VMware vCloud".freeze
  end

  def self.params_for_create
    @params_for_create ||= {
      :fields => [
        {
          :component    => "select",
          :name         => "api_version",
          :label        => _("API Version"),
          :initialValue => "9.0",
          :isRequired   => true,
          :validate     => [{:type => "required"}],
          :options      => [
            {
              :label => 'vCloud API 5.1',
              :value => '5.1',
            },
            {
              :label => 'vCloud API 5.5',
              :value => '5.5',
            },
            {
              :label => 'vCloud API 5.6',
              :value => '5.6',
            },
            {
              :label => 'vCloud API 9.0',
              :value => '9.0',
            }
          ]
        },
        {
          :component => 'sub-form',
          :name      => 'endpoints-subform',
          :title     => _("Endpoints"),
          :fields    => [
            :component => 'tabs',
            :name      => 'tabs',
            :fields    => [
              {
                :component => 'tab-item',
                :name      => 'default-tab',
                :title     => _('Default'),
                :fields    => [
                  {
                    :component              => 'validate-provider-credentials',
                    :name                   => 'endpoints.default.valid',
                    :skipSubmit             => true,
                    :validationDependencies => %w[type zone_id api_version],
                    :fields                 => [
                      {
                        :component  => "text-field",
                        :name       => "endpoints.default.hostname",
                        :label      => _("Hostname (or IPv4 or IPv6 address)"),
                        :isRequired => true,
                        :validate   => [{:type => "required"}]
                      },
                      {
                        :component    => "text-field",
                        :name         => "endpoints.default.port",
                        :label        => _("API Port"),
                        :type         => "number",
                        :isRequired   => true,
                        :validate     => [{:type => "required"}],
                        :initialValue => 443,
                      },
                      {
                        :component  => "text-field",
                        :name       => "authentications.default.userid",
                        :label      => _("Username"),
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                      },
                      {
                        :component  => "password-field",
                        :name       => "authentications.default.password",
                        :label      => _("Password"),
                        :type       => "password",
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                      },
                    ],
                  },
                ],
              },
              {
                :component => 'tab-item',
                :name      => 'events-tab',
                :title     => _('Events'),
                :fields    => [
                  {
                    :component    => 'protocol-selector',
                    :name         => 'event_stream_selection',
                    :skipSubmit   => true,
                    :label        => _('Type'),
                    :initialValue => 'none',
                    :options      => [
                      {
                        :label => _("None"),
                        :value => 'none',
                      },
                      {
                        :label => _("AMQP"),
                        :value => "amqp",
                        :pivot => 'endpoints.amqp.hostname',
                      },
                    ],
                  },
                  {
                    :component              => 'validate-provider-credentials',
                    :name                   => 'endpoints.amqp.valid',
                    :skipSubmit             => true,
                    :validationDependencies => %w[type event_stream_selection],
                    :condition              => {
                      :when => 'event_stream_selection',
                      :is   => 'amqp',
                    },
                    :fields                 => [
                      {
                        :component  => "select",
                        :name       => "endpoints.amqp.security_protocol",
                        :label      => _("Security Protocol"),
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                        :options    => [
                          {
                            :label => _("SSL without validation"),
                            :value => "ssl-no-validation"
                          },
                          {
                            :label => _("SSL"),
                            :value => "ssl-with-validation"
                          },
                          {
                            :label => _("Non-SSL"),
                            :value => "non-ssl"
                          }
                        ]
                      },
                      {
                        :component  => "text-field",
                        :name       => "endpoints.amqp.hostname",
                        :label      => _("Hostname (or IPv4 or IPv6 address)"),
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                      },
                      {
                        :component    => "text-field",
                        :name         => "endpoints.amqp.port",
                        :label        => _("API Port"),
                        :type         => "number",
                        :isRequired   => true,
                        :initialValue => 5672,
                        :validate     => [{:type => "required"}],
                      },
                      {
                        :component  => "text-field",
                        :name       => "authentications.amqp.userid",
                        :label      => "Username",
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                      },
                      {
                        :component  => "password-field",
                        :name       => "authentications.amqp.password",
                        :label      => "Password",
                        :type       => "password",
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                      },
                    ],
                  },
                ],
              },
            ]
          ]
        },
      ]
    }.freeze
  end

  # Verify Credentials
  # args:
  # {
  #   "api_version" => nil,
  #   "endpoints" => {
  #     "default" => {
  #       "hostname"          => nil,
  #       "port"              => nil,
  #       "security_protocol" => nil,
  #     },
  #     "amqp"  => {
  #       "hostname"          => nil,
  #       "port"              => nil,
  #       "security_protocol" => nil,
  #     }
  #   },
  #   "authentications" => {
  #     "default" => {
  #       "username" => nil,
  #       "password" => nil,
  #     },
  #     "amqp"    => {
  #       "username" => nil,
  #       "password" => nil,
  #     }
  #   }
  # }
  def self.verify_credentials(args)
    endpoint_name = args.dig("endpoints").keys.first
    endpoint = args.dig("endpoints", endpoint_name)
    authentication = args.dig("authentications", endpoint_name)

    hostname, port, security_protocol = endpoint&.values_at('hostname', 'port', 'security_protocol')
    api_version = args['api_version']

    userid, password = authentication&.values_at('userid', 'password')
    password = MiqPassword.try_decrypt(password)
    password ||= find(args["id"]).authentication_password(endpoint_name)

    if args['event_stream_selection'] == 'amqp'
      ManageIQ::Providers::Vmware::CloudManager::EventCatcher::Stream.test_amqp_connection(
        :hostname          => hostname,
        :port              => port,
        :security_protocol => security_protocol,
        :username          => userid,
        :password          => password
      )
    else
      !!raw_connect(hostname, port, userid, password, api_version, true)
    end
  end

  def self.default_blacklisted_event_names
    []
  end

  def self.hostname_required?
    true
  end

  def supports_port?
    true
  end

  def supported_auth_types
    %w(default amqp)
  end

  def supports_authentication?(authtype)
    supported_auth_types.include?(authtype.to_s)
  end

  def self.catalog_types
    {"vmware" => N_("VMware")}
  end

  def self.display_name(number = 1)
    n_('Cloud Provider (VMware vCloud)', 'Cloud Providers (VMware vCloud)', number)
  end

  #
  # Operations
  #

  def vm_create_snapshot(vm, options = {})
    defaults = {
      :memory  => false,
      :quiesce => false
    }
    options = defaults.merge(options)
    with_provider_connection do |service|
      response = service.post_create_snapshot(vm.ems_ref, options)
      service.process_task(response.body)
    end
  end

  def vm_revert_to_snapshot(vm, _options = {})
    with_provider_connection do |service|
      response = service.post_revert_snapshot(vm.ems_ref)
      service.process_task(response.body)
    end
  end

  def vm_remove_all_snapshots(vm, _options = {})
    with_provider_connection do |service|
      response = service.post_remove_all_snapshots(vm.ems_ref)
      service.process_task(response.body)
    end
  end

  def vm_reconfigure(vm, options = {})
    with_provider_connection do |service|
      xml = service.get_vapp(vm.ems_ref, :parser => 'xml').body
      response = service.post_reconfigure_vm(vm.ems_ref, xml, options[:spec])
      service.process_task(response.body)
    end
  end
end
