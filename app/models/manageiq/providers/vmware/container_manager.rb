ManageIQ::Providers::Kubernetes::ContainerManager.include(ActsAsStiLeafClass)

class ManageIQ::Providers::Vmware::ContainerManager < ManageIQ::Providers::Kubernetes::ContainerManager
  require_nested :Container
  require_nested :ContainerGroup
  require_nested :ContainerNode
  require_nested :EventCatcher
  require_nested :EventParser
  require_nested :Refresher
  require_nested :RefreshWorker

  supports :create

  def self.ems_type
    @ems_type ||= "vmware_tanzu".freeze
  end

  def self.description
    @description ||= "VMware Tanzu".freeze
  end

  def self.display_name(number = 1)
    n_('Container Provider (Vmware)', 'Container Providers (Vmware)', number)
  end

  def self.kubernetes_auth_options(options)
    {:bearer_token => options[:bearer] || wcp_login(options)}
  end

  def self.wcp_login(options = {})
    hostname, username, password = options.values_at(:hostname, :username, :password)
    url = URI::HTTPS.build(:host => hostname, :path => "/wcp/login").to_s

    verify_ssl, certificate_authority = options[:ssl_options].values_at(:verify_ssl, :certificate_authority)
    verify_ssl ||= OpenSSL::SSL::VERIFY_PEER

    require "rest-client"
    result = RestClient::Request.execute(
      :method      => :post,
      :url         => url,
      :user        => username,
      :password    => password,
      :verify_ssl  => verify_ssl,
      :ssl_ca_file => certificate_authority,
      :headers     => {"Accept" => "*/*", "Content-Type" => "application/json"}
    )

    JSON.parse(result.body)["session_id"]
  end
  private_class_method :wcp_login

  def self.verify_credentials(args)
    ext_management_system = find(args["id"]) if args["id"]

    default_endpoint = args.dig("endpoints", "default")
    raise MiqException::MiqInvalidCredentialsError, _("Unsupported endpoint") if default_endpoint.nil?

    hostname, port, verify_ssl, certificate_authority = default_endpoint&.values_at("hostname", "port", "verify_ssl", "certificate_authority")

    default_authentication = args.dig("authentications", "default")
    username, password = default_authentication&.values_at("userid", "password")

    password   = ManageIQ::Password.try_decrypt(password)
    password ||= ext_management_system.authentication_userid("default") if ext_management_system

    options = {
      :username    => username,
      :password    => password,
      :hostname    => hostname,
      :port        => port,
      :ssl_options => {
        :verify_ssl => verify_ssl,
        :ca_file    => certificate_authority
      }
    }

    !!raw_connect(hostname, port, options)
  end

  def self.params_for_create
    @params_for_create ||= {
      :fields => [
        {
          :component => 'sub-form',
          :id        => 'endpoints-subform',
          :name      => 'endpoints-subform',
          :title     => _('Endpoints'),
          :fields    => [
            :component => 'tabs',
            :name      => 'tabs',
            :fields    => [
              {
                :component => 'tab-item',
                :id        => 'default-tab',
                :name      => 'default-tab',
                :title     => _('Default'),
                :fields    => [
                  {
                    :component              => 'validate-provider-credentials',
                    :id                     => 'authentications.default.valid',
                    :name                   => 'authentications.default.valid',
                    :skipSubmit             => true,
                    :isRequired             => true,
                    :validationDependencies => %w[type zone_id provider_region uid_ems],
                    :fields                 => [
                      {
                        :component    => "select",
                        :id           => "endpoints.default.verify_ssl",
                        :name         => "endpoints.default.verify_ssl",
                        :label        => _("SSL verification"),
                        :dataType     => "integer",
                        :isRequired   => true,
                        :initialValue => OpenSSL::SSL::VERIFY_PEER,
                        :options      => [
                          {
                            :label => _('Do not verify'),
                            :value => OpenSSL::SSL::VERIFY_NONE,
                          },
                          {
                            :label => _('Verify'),
                            :value => OpenSSL::SSL::VERIFY_PEER,
                          },
                        ]
                      },
                      {
                        :component  => "text-field",
                        :id         => "endpoints.default.hostname",
                        :name       => "endpoints.default.hostname",
                        :label      => _("Hostname (or IPv4 or IPv6 address)"),
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                      },
                      {
                        :component    => "text-field",
                        :id           => "endpoints.default.port",
                        :name         => "endpoints.default.port",
                        :label        => _("API Port"),
                        :type         => "number",
                        :initialValue => default_port,
                        :isRequired   => true,
                        :validate     => [{:type => "required"}],
                      },
                      {
                        :component  => "textarea",
                        :name       => "endpoints.default.certificate_authority",
                        :id         => "endpoints.default.certificate_authority",
                        :label      => _("Trusted CA Certificates"),
                        :rows       => 10,
                        :isRequired => false,
                        :helperText => _('Paste here the trusted CA certificates, in PEM format.'),
                        :condition  => {
                          :when => 'endpoints.default.verify_ssl',
                          :is   => OpenSSL::SSL::VERIFY_PEER,
                        },
                      },
                      {
                        :component  => "text-field",
                        :id         => "authentications.default.userid",
                        :name       => "authentications.default.userid",
                        :label      => _("Username"),
                        :isRequired => true,
                        :validate   => [{:type => "required"}]
                      },
                      {
                        :component  => "password-field",
                        :id         => "authentications.default.password",
                        :name       => "authentications.default.password",
                        :label      => _("Password"),
                        :type       => "password",
                        :isRequired => true,
                        :validate   => [{:type => "required"}]
                      },
                    ]
                  }
                ]
              }
            ]
          ]
        }
      ]
    }
  end

  def default_authentication_type
    :default
  end

  def required_credential_fields(_type)
    %i[userid password]
  end

  def connect_options(options = {})
    super.merge(
      :hostanme              => hostname,
      :verify_ssl            => verify_ssl,
      :certificate_authority => certificate_authority
    )
  end
end
