class ManageIQ::Providers::Vmware::InfraManager::Operations < ManageIQ::Providers::BaseManager::Operations
  private

  def connection_key(connect_params)
    server = connect_params[:server]
    user   = connect_params[:user]

    "#{server}__#{user}"
  end

  def connect(connect_params)
    host     = connect_params[:server]
    username = connect_params[:username]
    password = connect_params[:password]

    opts = {
      :ns       => "urn:vim25",
      :host     => host,
      :ssl      => true,
      :insecure => true,
      :path     => "/sdk",
      :port     => 443,
      :rev      => "6.5",
    }

    require 'rbvmomi/vim'

    _log.info("Connecting to #{host}...")

    conn = RbVmomi::VIM.new(opts).tap do |vim|
      vim.rev = vim.serviceContent.about.apiVersion

      _log.info("Logging in to #{username}@#{host}...")
      vim.serviceContent.sessionManager.Login(
        :userName => username,
        :password => password,
      )
      _log.info("Logging in to #{username}@#{host}...Complete")
    end
    _log.info("Connecting to #{host}...Complete")

    conn
  end
end
