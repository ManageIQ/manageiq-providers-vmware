module ManageIQ::Providers::Vmware::InfraManager::VimConnectMixin
  extend ActiveSupport::Concern

  def vim_connect(options = {})
    options[:auth_type] ||= :ws

    raise _("no console credentials defined") if options[:auth_type] == :console && !authentication_type(options[:auth_type])
    raise _("no credentials defined") if missing_credentials?(options[:auth_type])

    options[:ip] ||= hostname
    options[:user] ||= authentication_userid(options[:auth_type])
    options[:pass] ||= authentication_password(options[:auth_type])

    conn_key = connection_key(options)

    Thread.current[:miq_vim] ||= {}

    # Reconnect if the connection is stale
    Thread.current[:miq_vim][conn_key] = nil unless Thread.current[:miq_vim][conn_key]&.isAlive?

    Thread.current[:miq_vim][conn_key] ||= begin
      require 'VMwareWebService/MiqVim'
      MiqVim.new(*options.values_at(:ip, :user, :pass, :cache_scope, :monitor_updates, :pre_load))
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

      ip, user = options.values_at(:ip, :user)
      pass = ManageIQ::Password.try_decrypt(options[:pass])

      validate_connection do
        vim = MiqVim.new(ip, user, pass)
        raise MiqException::Error, _("Adding ESX/ESXi Hosts is not supported") unless vim.isVirtualCenter

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
