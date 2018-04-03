require 'fog/vcloud_director'

module ManageIQ::Providers::Vmware::ManagerAuthMixin
  extend ActiveSupport::Concern

  def verify_credentials(auth_type = nil, options = {})
    auth_type ||= 'default'
    raise MiqException::MiqHostError, "No credentials defined" if missing_credentials?(auth_type)

    options[:auth_type] = auth_type

    self.class.connection_rescue_block do
      case auth_type.to_s
      when 'default' then
        with_provider_connection(options) do |vcd|
          self.class.validate_connection(vcd)
        end
      when 'amqp' then
        verify_amqp_credentials(options)
      else
        raise "Invalid Vmware vCloud Authentication Type: #{auth_type.inspect}"
      end
    end

    true
  end

  def connect(options = {})
    raise "no credentials defined" if missing_credentials?(options[:auth_type])

    server      = options[:ip] || address
    port        = options[:port] || self.port
    api_version = options[:api_version] || self.api_version
    username    = options[:user] || authentication_userid(options[:auth_type])
    password    = options[:pass] || authentication_password(options[:auth_type])

    self.class.raw_connect(server, port, username, password, api_version)
  end

  module ClassMethods
    def raw_connect(server, port, username, password, api_version = '5.5', validate = false)
      params = {
        :vcloud_director_username      => username,
        :vcloud_director_password      => MiqPassword.try_decrypt(password),
        :vcloud_director_host          => server,
        :vcloud_director_show_progress => false,
        :vcloud_director_api_version   => api_version,
        :port                          => port,
        :connection_options            => {
          :ssl_verify_peer => false # for development
        }
      }

      connect = Fog::Compute::VcloudDirector.new(params)
      connection_rescue_block { validate_connection(connect) } if validate
      connect
    end

    def validate_connection(connection)
      connection.organizations.all
    end

    def connection_rescue_block
      yield
    rescue => err
      miq_exception = translate_exception(err)
      $vcloud_log.error("Error Class=#{err.class.name}, Message=#{err.message}")
      raise miq_exception
    end

    def translate_exception(err)
      case err
      when Fog::Compute::VcloudDirector::Unauthorized
        MiqException::MiqInvalidCredentialsError.new "Login failed due to a bad username or password."
      when Excon::Errors::Timeout
        MiqException::MiqUnreachableError.new "Login attempt timed out"
      when Excon::Errors::SocketError
        MiqException::MiqHostError.new "Socket error: #{err.message}"
      when MiqException::MiqInvalidCredentialsError, MiqException::MiqHostError
        err
      else
        MiqException::MiqHostError.new "Unexpected response returned from system: #{err.message}"
      end
    end
  end
end
