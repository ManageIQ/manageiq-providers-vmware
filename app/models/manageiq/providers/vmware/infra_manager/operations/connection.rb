require "rbvmomi/vim"

class ManageIQ::Providers::Vmware::InfraManager::Operations::Connection
  def initialize(server, username, password)
    @server     = server
    @username   = username
    @password   = password
    @lock       = Mutex.new
    @connection = nil
  end

  def with
    lock.synchronize { yield connection }
  end

  def close
    lock.synchronize { disconnect }
  end

  private

  attr_reader :server, :username, :password, :lock

  def connection
    @connection ||= connect
  end

  def disconnect
    unless @connection.nil?
      @connection.close
      @connection = nil
    end
  end

  def connect
    RbVmomi::VIM.new(connect_opts).tap do |vim|
      vim.rev = vim.serviceContent.about.apiVersion
      vim.serviceContent.sessionManager.Login(:userName => username, :password => password)
    end
  end

  def connect_opts
    {
      :ns       => "urn:vim25",
      :host     => server,
      :ssl      => true,
      :insecure => true,
      :path     => "/sdk",
      :port     => 443,
      :rev      => "6.5",
    }
  end
end
