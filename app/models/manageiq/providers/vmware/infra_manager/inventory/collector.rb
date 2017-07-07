require 'rbvmomi/vim'

class ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector
  include Vmdb::Logging

  attr_reader :ems, :exit_requested
  private     :ems, :exit_requested

  def initialize(ems)
    @ems            = ems
    @exit_requested = false
  end

  def run
    until exit_requested
      vim = connect(ems.address, ems.authentication_userid, ems.authentication_password)

      begin
        wait_for_updates(vim)
      rescue RbVmomi::Fault
        vim.serviceContent.sessionManager.Logout
        vim = nil
      end
    end

    _log.info("Exiting...")
  ensure
    vim.serviceContent.sessionManager.Logout unless vim.nil?
  end

  def stop
    _log.info("Exit request received...")
    @exit_requested = true
  end

  def connect(host, username, password)
    _log.info("Connecting to #{username}@#{host}...")

    vim_opts = {
      :ns       => 'urn:vim25',
      :host     => host,
      :ssl      => true,
      :insecure => true,
      :path     => '/sdk',
      :port     => 443,
      :user     => username,
      :password => password,
    }

    vim = RbVmomi::VIM.connect(vim_opts)

    _log.info("Connected")
    vim
  end

  def wait_for_updates(vim)
  end
end
