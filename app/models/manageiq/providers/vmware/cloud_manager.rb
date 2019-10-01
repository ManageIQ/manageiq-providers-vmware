class ManageIQ::Providers::Vmware::CloudManager < ManageIQ::Providers::CloudManager
  require_nested :AvailabilityZone
  require_nested :OrchestrationServiceOptionConverter
  require_nested :OrchestrationStack
  require_nested :OrchestrationTemplate
  require_nested :EventCatcher
  require_nested :EventParser
  require_nested :RefreshParser
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
      :title  => "Configure #{description}",
      :fields => [
        {
          :component  => "text-field",
          :name       => "endpoints.default.server",
          :label      => "Server Hostname/IP Address",
          :isRequired => true,
          :validate   => [{:type => "required-validator"}]
        },
        {
          :component => "text-field",
          :name      => "endpoints.default.port",
          :label     => "Port",
          :type      => "number",
        },
        {
          :component  => "text-field",
          :name       => "endpoints.default.username",
          :label      => "Username",
          :isRequired => true,
          :validate   => [{:type => "required-validator"}]
        },
        {
          :component  => "text-field",
          :name       => "endpoints.default.password",
          :label      => "Password",
          :type       => "password",
          :isRequired => true,
          :validate   => [{:type => "required-validator"}]
        },
        {
          :component    => "text-field",
          :name         => "endpoints.default.api_version",
          :label        => "API Version",
          :initialValue => "5.5",
          :isRequired   => true,
          :validate     => [{:type => "required-validator"}]
        },
        {
          :component => "text-field",
          :name      => "endpoints.events.server",
          :label     => "AMQP Hostname",
        },
        {
          :component => "text-field",
          :name      => "endpoints.events.port",
          :label     => "AMQP Port",
          :type      => "number"
        },
        {
          :component => "text-field",
          :name      => "endpoints.events.username",
          :label     => "AMQP Username"
        },
        {
          :component => "text-field",
          :name      => "endpoints.events.password",
          :label     => "Password",
          :type      => "AMQP password"
        }
      ]
    }.freeze
  end

  # Verify Credentials
  # args:
  # {
  #   "endpoints" => {
  #     "default" => {
  #       "server"      => nil,
  #       "port"        => nil,
  #       "username"    => nil,
  #       "password"    => nil,
  #       "api_version" => nil
  #     },
  #     "events"  => {
  #       "server"   => nil,
  #       "port"     => nil,
  #       "username" => nil,
  #       "password" => nil,
  #     }
  #   }
  # }
  def self.verify_credentials(args)
    default_endpoint = args.dig("endpoints", "default")
    server, port, username, password, api_version = default_endpoint&.values_at(
      "server", "port", "username", "password", "api_version")

    !!raw_connect(server, port, username, password, api_version, true)
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

  def supported_catalog_types
    %w(vmware)
  end

  #
  # Operations
  #

  def vm_start(vm, _options = {})
    vm.start
  rescue => err
    $vcloud_log.error("vm=[#{vm.name}, error: #{err}")
  end

  def vm_stop(vm, _options = {})
    vm.stop
  rescue => err
    $vcloud_log.error("vm=[#{vm.name}, error: #{err}")
  end

  def vm_suspend(vm, _options = {})
    vm.suspend
  rescue => err
    $vcloud_log.error("vm=[#{vm.name}], error: #{err}")
  end

  def vm_restart(vm, _options = {})
    vm.restart
  rescue => err
    $vcloud_log.error("vm=[#{vm.name}], error: #{err}")
  end

  def vm_destroy(vm, _options = {})
    vm.vm_destroy
  rescue => err
    $vcloud_log.error("vm=[#{vm.name}], error: #{err}")
  end

  def self.display_name(number = 1)
    n_('Cloud Provider (VMware vCloud)', 'Cloud Providers (VMware vCloud)', number)
  end

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
