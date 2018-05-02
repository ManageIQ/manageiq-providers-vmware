class ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector
  include PropertyCollector
  include Vmdb::Logging

  attr_reader   :ems, :inventory_cache, :run_once, :saver
  attr_accessor :exit_requested

  def initialize(ems, run_once: false, threaded: true)
    @ems             = ems
    @inventory_cache = ems.class::Inventory::Cache.new
    @run_once        = run_once
    @saver           = ems.class::Inventory::Saver.new(:threaded => threaded)

    self.exit_requested = false
  end

  def run
    _log.info("Monitor updates thread started")

    saver.start_thread

    vim = connect
    property_filter = create_property_filter(vim)

    _log.info("Refreshing initial inventory")
    version = initial_refresh(vim, property_filter)
    _log.info("Refreshing initial inventory...Complete")

    return if run_once

    until exit_requested
      persister = targeted_persister_klass.new(ems)
      version = monitor_updates(vim, property_filter, version, persister)
    end

    _log.info("Monitor updates thread exited")
  ensure
    saver.stop_thread
    destroy_property_filter(property_filter)
    disconnect(vim)
  end

  def stop
    _log.info("Monitor updates thread exiting...")
    self.exit_requested = true
  end

  def initial_refresh(vim, property_filter)
    monitor_updates(vim, property_filter, "", full_persister_klass.new(ems))
  end

  def monitor_updates(vim, property_filter, version, persister)
    parser = parser_klass.new(persister)

    begin
      update_set = wait_for_updates(vim, version)
      break if update_set.nil?

      version = update_set.version
      process_update_set(property_filter, update_set, parser)
    end while update_set.truncated

    save_inventory(persister)

    version
  end

  private

  def connect
    host = ems.hostname
    username, password = ems.auth_user_pwd

    _log.info("Connecting to #{username}@#{host}...")

    vim_opts = {
      :ns       => 'urn:vim25',
      :host     => host,
      :ssl      => true,
      :insecure => true,
      :path     => '/sdk',
      :port     => 443,
      :rev      => '6.5',
    }

    require 'rbvmomi/vim'
    conn = RbVmomi::VIM.new(vim_opts).tap do |vim|
      vim.rev = vim.serviceContent.about.apiVersion
      vim.serviceContent.sessionManager.Login(:userName => username, :password => password)
    end

    _log.info("Connected")
    conn
  end

  def disconnect(vim)
    return if vim.nil?

    vim.close
  end

  def wait_for_updates(vim, version)
    # Return if we don't receive any updates for 60 seconds break
    # so that we can check if we are supposed to exit
    options = RbVmomi::VIM.WaitOptions(:maxWaitSeconds => 60)

    vim.propertyCollector.WaitForUpdatesEx(:version => version, :options => options)
  end

  def process_update_set(property_filter, update_set, parser)
    property_filter_update = update_set.filterSet.to_a.detect { |update| update.filter == property_filter }
    return if property_filter_update.nil?

    object_update_set = property_filter_update.objectSet
    return if object_update_set.blank?

    _log.info("Processing #{object_update_set.count} updates...")

    process_object_update_set(object_update_set).each do |managed_object, props|
      parser.parse(managed_object, props)
    end

    _log.info("Processing #{object_update_set.count} updates...Complete")
  end

  def process_object_update_set(object_update_set)
    object_update_set.map do |object_update|
      process_object_update(object_update)
    end
  end

  def process_object_update(object_update)
    managed_object = object_update.obj

    props =
      case object_update.kind
      when "enter"
        process_object_update_enter(managed_object, object_update.changeSet, object_update.missingSet)
      when "modify"
        process_object_update_modify(managed_object, object_update.changeSet, object_update.missingSet)
      when "leave"
        process_object_update_leave(managed_object)
      end

    return managed_object, props
  end

  def process_object_update_enter(obj, change_set, _missing_set = [])
    inventory_cache.insert(obj, change_set)
  end

  def process_object_update_modify(obj, change_set, _missing_set = [])
    inventory_cache.update(obj, change_set)
  end

  def process_object_update_leave(obj)
    inventory_cache.delete_object(obj.class.wsdl_name, obj._ref)
  end

  def save_inventory(persister)
    saver.queue_save_inventory(persister)
  end

  def full_persister_klass
    @full_persister_klass ||= ems.class::Inventory::Persister
  end

  def targeted_persister_klass
    @targeted_persister_klass ||= ems.class::Inventory::Persister::Targeted
  end

  def parser_klass
    @parser_klass ||= ems.class::Inventory::Parser
  end
end
