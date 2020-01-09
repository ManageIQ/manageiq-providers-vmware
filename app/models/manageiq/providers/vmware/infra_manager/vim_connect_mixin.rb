module ManageIQ::Providers::Vmware::InfraManager::VimConnectMixin
  extend ActiveSupport::Concern

  def connect(options = {})
    options[:auth_type] ||= :ws

    raise _("no console credentials defined") if options[:auth_type] == :console && !authentication_type(options[:auth_type])
    raise _("no credentials defined") if missing_credentials?(options[:auth_type])

    Thread.current[:miq_vim] ||= {}

    options[:ip] ||= hostname
    options[:user] ||= authentication_userid(options[:auth_type])
    options[:pass] ||= authentication_password(options[:auth_type])

    # Reconnect if the connection is stale
    Thread.current[:miq_vim][connection_key(options)] = nil unless Thread.current[:miq_vim][connection_key(options)]&.isAlive?

    Thread.current[:miq_vim][connection_key(options)] ||= begin
      require 'VMwareWebService/MiqVim'
      MiqVim.new(options[:ip], options[:user], options[:pass], options[:cache_scope], options[:monitor_updates])
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
      require 'VMwareWebService/miq_fault_tolerant_vim'

      options[:pass] = ManageIQ::Password.try_decrypt(options[:pass])
      options[:use_broker] = false

      validate_connection do
        vim = MiqFaultTolerantVim.new(options)
        raise MiqException::Error, _("Adding ESX/ESXi Hosts is not supported") unless vim.isVirtualCenter
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
  end
end
