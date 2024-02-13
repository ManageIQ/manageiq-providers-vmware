module ManageIQ::Providers::Vmware::InfraManager::VimConnectMixin
  extend ActiveSupport::Concern

  def vim_connect(options = {})
    raise _("no console credentials defined") if options[:auth_type] == :console && !authentication_type(options[:auth_type])
    raise _("no credentials defined") if missing_credentials?(options[:auth_type])

    options[:ip]   ||= hostname
    options[:port] ||= try(:port) || 443
    options[:user] ||= authentication_userid(options[:auth_type])
    options[:pass] ||= authentication_password(options[:auth_type])

    options[:verify_ssl]            = try(:verify_ssl)            unless options.key?(:verify_ssl)
    options[:certificate_authority] = try(:certificate_authority) unless options.key?(:certificate_authority)

    conn_key = connection_key(options)

    Thread.current[:miq_vim] ||= {}

    # Reconnect if the connection is stale
    Thread.current[:miq_vim][conn_key] = nil unless Thread.current[:miq_vim][conn_key]&.isAlive?

    Thread.current[:miq_vim][conn_key] ||= begin
      require 'VMwareWebService/MiqVim'
      MiqVim.new(
        :server          => options[:ip],
        :port            => options[:port],
        :username        => options[:user],
        :password        => options[:pass],
        :cache_scope     => options[:cache_scope],
        :monitor_updates => options[:monitor_updates],
        :pre_load        => options[:pre_load],
        :ssl_options     => {
          :verify_ssl => options[:verify_ssl],
          :ca_file    => options[:certificate_authority]
        }
      )
    end
  end

  def with_provider_connection(options = {})
    raise _("no block given") unless block_given?
    _log.info("Connecting through #{self.class.name}: [#{name}]")
    begin
      vim = connect(options)
      yield vim
    end
  end

  private

  def connection_key(options)
    server   = options[:ip]
    username = options[:user]

    "#{server}__#{username}"
  end

  module ClassMethods
    def raw_connect(options)
      require 'handsoap'
      require 'VMwareWebService/MiqVim'

      ip, user, port, verify_ssl, certificate_authority = options.values_at(:ip, :user, :port, :verify_ssl, :certificate_authority)

      pass = ManageIQ::Password.try_decrypt(options[:pass])

      validate_connection do
        vim = MiqVim.new(
          :server      => ip,
          :port        => port,
          :username    => user,
          :password    => pass,
          :ssl_options => {
            :verify_ssl => verify_ssl,
            :ca_file    => certificate_authority
          }
        )

        raise MiqException::Error, _("Adding ESX/ESXi Hosts is not supported") if !vim.isVirtualCenter && !Settings.prototype.ems_vmware.allow_direct_hosts
        raise MiqException::Error, _("vCenter version %{version} is unsupported") % {:version => vim.apiVersion} if !version_supported?(vim.apiVersion)

        # If the time on the vCenter is very far off from MIQ system time then
        # any comparison of last_refresh_on and VMware TaskInfo.completeTime can be
        # unreliable.
        vc_time_diff = Time.parse(vim.currentTime).utc - Time.now.utc
        raise MiqException::Error, _("vCenter time is too far out of sync with the system time") if vc_time_diff.abs > 10.minutes

        true
      ensure
        vim&.disconnect rescue nil
      end
    end

    def version_supported?(api_version)
      Gem::Version.new(api_version) >= Gem::Version.new('6.0')
    end

    def validate_connection
      yield
    rescue SocketError, Errno::EHOSTUNREACH, Errno::ENETUNREACH
      _log.warn($!.inspect)
      raise MiqException::MiqUnreachableError, $!.message
    rescue Handsoap::Fault
      _log.warn($!.inspect)
      if $!.respond_to?(:reason)
        raise MiqException::MiqInvalidCredentialsError, $!.reason if $!.reason =~ /Authorize Exception|incorrect user name or password/
        raise $!.reason
      end
      raise $!.message
    rescue MiqException::Error
      _log.warn($!.inspect)
      raise
    rescue Exception
      _log.warn($!.inspect)
      raise "Unexpected response returned from Provider, see log for details"
    end

    def disconnect_all
      Thread.current[:miq_vim]&.each_value do |vim|
        begin
          vim.disconnect
        rescue
        end
      end
    end
  end
end
