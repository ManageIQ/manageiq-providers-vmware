require "sinatra/base"

# Beat rails autoload to ResourcePool
RbVmomi
RbVmomi::VIM
RbVmomi::VIM::ResourcePool

class ManageIQ::Providers::Vmware::InfraManager::Operations < Sinatra::Base
  require_nested :Connection

  disable :traps

  def initialize
    super

    @connections      = Concurrent::Map.new
    @connection_class = self.class::Connection
  end

  def shutdown
    connections.each_value(&:close)
  end

  get "/vm/:ref" do
    with_provider_connection do |vim|
      vm       = RbVmomi::VIM.VirtualMachine(vim, ref)
      path_set = params[:prop_set] || %w(name)

      YAML.dump(vm.collect!(*path_set))
    end
  end

  post "/vm/:ref/start" do
    host_ref = params["host"]

    with_provider_connection do |vim|
      vm   = RbVmomi::VIM.VirtualMachine(vim, ref)
      host = RbVmomi::VIM.HostSystem(vim, host_ref) if host_ref

      task = vm.PowerOnVM_Task(:host => host)
      task._ref
    end
  end

  post "/vm/:ref/stop" do
    with_provider_connection do |vim|
      vm = RbVmomi::VIM.VirtualMachine(vim, ref)

      task = vm.PowerOffVM_Task
      task._ref
    end
  end

  post "/vm/:ref/suspend" do
    with_provider_connection do |vim|
      vm = RbVmomi::VIM.VirtualMachine(vim, ref)

      task = vm.SuspendVM_Task
      task._ref
    end
  end

  post "/vm/:ref/shutdown" do
    with_provider_connection do |vim|
      vm = RbVmomi::VIM.VirtualMachine(vim, ref)
      vm.ShutdownGuest
    end
  end

  post "/vm/:ref/reboot" do
    with_provider_connection do |vim|
      vm = RbVmomi::VIM.VirtualMachine(vim, ref)
      vm.RebootGuest
    end
  end

  post "/vm/:ref/reset" do
    with_provider_connection do |vim|
      vm = RbVmomi::VIM.VirtualMachine(vim, ref)

      task = vm.ResetVM_Task
      task._ref
    end
  end

  post "/vm/:ref/standby" do
    with_provider_connection do |vim|
      vm = RbVmomi::VIM.VirtualMachine(vim, ref)
      vm.StandbyGuest
    end
  end

  post "/vm/:ref/unregister" do
    with_provider_connection do |vim|
      vm = RbVmomi::VIM.VirtualMachine(vim, ref)
      vm.UnregisterVM
    end
  end

  post "/vm/:ref/mark-as-template" do
    with_provider_connection do |vim|
      vm = RbVmomi::VIM.VirtualMachine(vim, ref)
      vm.MarkAsTemplate
    end
  end

  post "/vm/:ref/mark-as-vm" do
    pool_ref, host_ref = params.values_at("pool", "host")

    with_provider_connection do |vim|
      vm   = RbVmomi::VIM.VirtualMachine(vim, ref)
      pool = RbVmomi::VIM.ResourcePool(vim, pool_ref) if pool_ref
      host = RbVmomi::VIM.HostSystem(vim, host_ref)   if host_ref

      vm.MarkAsVirtualMachine(:pool => pool, :host => host)
    end
  end

  post "/vm/:ref/clone" do
    folder_ref, name, spec = params.values_at("folder", "name", "spec")

    with_provider_connection do |vim|
      vm     = RbVmomi::VIM.VirtualMachine(vim, ref)
      folder = RbVmomi::VIM.Folder(vim, folder_ref) if folder_ref
      spec   = YAML.safe_load(spec)

      task = vm.CloneVM_Task(:folder => folder, :name => name, :spec => spec)
      task._ref
    end
  end

  get "/task/:ref" do
    path_set = params[:prop_set] || %w(info.state info.error info.result)

    with_provider_connection do |vim|
      task = RbVmomi::VIM.Task(vim, ref)
      YAML.dump(task.collect!(*path_set))
    end
  end

  private

  attr_reader :connections, :connection_class

  def with_provider_connection
    raise "Invalid connection parameters" unless validate_connection_params

    connections.compute_if_absent(connection_key) { connection_class.new(*connection_params) }.with { |conn| yield conn }
  end

  def connection_param_keys
    %i(server username password)
  end

  def connection_params
    params.values_at(*connection_param_keys)
  end

  def ref
    params[:ref]
  end

  def connection_key
    server, username, _ = connection_params
    "#{server}__#{username}"
  end

  def validate_connection_params
    server, user, password = connection_params
    server && user && password
  end
end
