class ManageIQ::Providers::Vmware::InfraManager::Operations < ManageIQ::Providers::BaseManager::Operations
  def raw_vm_start(vim, vm_ref, args = {})
    vm = rbvmomi_object('VirtualMachine', vim, vm_ref)
    host = rbvmomi_object('HostSystem', vim, args[:host]) if args[:host]

    task = vm.PowerOnVM_Task(host: host)
    task.wait_for_completion
  end

  def raw_vm_stop(vim, vm_ref, args = {})
    vm = rbvmomi_object('VirtualMachine', vim, vm_ref)

    task = vm.PowerOffVM_Task
    task.wait_for_completion
  end

  def raw_vm_suspend(vim, vm_ref, args = {})
    vm = rbvmomi_object('VirtualMachine', vim, vm_ref)

    task = vm.SuspendVM_Task
    task.wait_for_completion
  end

  def raw_vm_shutdown_guest(vim, vm_ref, args = {})
    vm = rbvmomi_object('VirtualMachine', vim, vm_ref)
    vm.ShutdownGuest
  end

  def raw_vm_reboot_guest(vim, vm_ref, args = {})
    vm = rbvmomi_object('VirtualMachine', vim, vm_ref)
    vm.RebootGuest
  end

  def raw_vm_reset(vim, vm_ref, args = {})
    vm = rbvmomi_object('VirtualMachine', vim, vm_ref)
    task = vm.ResetVM_Task
    task.wait_for_completion
  end

  def raw_vm_unregister(vim, vm_ref, args = {})
    vm = rbvmomi_object('VirtualMachine', vim, vm_ref)
    vm.UnregisterVM
  end

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

  def rbvmomi_object(wsdl_name, connection, ref)
    connection.type(wsdl_name).new(connection, ref)
  end
end
