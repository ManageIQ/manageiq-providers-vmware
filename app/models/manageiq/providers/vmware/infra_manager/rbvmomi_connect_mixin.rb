module ManageIQ::Providers::Vmware::InfraManager::RbvmomiConnectMixin
  def connect(options = {})
    options[:ssl]      ||= true
    options[:insecure] ||= true

    opts = rbvmomi_vim_connect_opts(options)

    RbVmomi::VIM.new(opts).tap do |vim|
      vim.rev = vim.serviceContent.about.apiVersion
      vim.serviceContent.sessionManager.Login(
        :userName => options[:user],
        :password => options[:password],
      )
    end
  end

  private

  def rbvmomi_vim_connect_opts(options)
    {
      :ns       => "urn:vim25",
      :host     => options[:host],
      :ssl      => options[:ssl],
      :insecure => options[:insecure],
      :path     => "/sdk",
      :port     => 443,
      :rev      => "6.5",
    }
  end
end
