class ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector
  include PropertyCollector
  include Vmdb::Logging

  def initialize(ems)
    @ems             = ems
    @exit_requested  = false
    @inventory_cache = ems.class::Inventory::Cache.new
  end

  def run
    until exit_requested
      vim = connect

      begin
        wait_for_updates(vim)
      rescue RbVmomi::Fault => err
        _log.error("Caught exception #{err.message}")
        _log.log_backtrace(err)
      ensure
        vim.close unless vim.nil?
        vim = nil
      end
    end

    _log.info("Exiting...")
  ensure
    disconnect(vim)
  end

  def stop
    _log.info("Exit request received...")
    @exit_requested = true
  end

  private

  attr_reader :ems, :exit_requested, :inventory_cache

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

    vim.serviceContent.sessionManager.Logout
  end

  def wait_for_updates(vim, run_once: false)
    property_filter = create_property_filter(vim)

    # Return if we don't receive any updates for 60 seconds break
    # so that we can check if we are supposed to exit
    options = RbVmomi::VIM.WaitOptions(:maxWaitSeconds => 60)

    # Send the "special initial data version" i.e. an empty string
    # so that we get all inventory back in the first update set
    version = ""

    _log.info("Refreshing initial inventory...")

    # Use the full refresh persister for the initial UpdateSet from WaitForUpdates
    # After the initial UpdateSet this will change to a targeted persister
    persister = ems.class::Inventory::Persister.new(ems)

    initial = true
    until exit_requested
      update_set = vim.propertyCollector.WaitForUpdatesEx(:version => version, :options => options)
      next if update_set.nil?

      # Save the new update set version
      version = update_set.version

      property_filter_update_set = update_set.filterSet
      next if property_filter_update_set.blank?

      # After the initial UpdateSet switch to a targeted persister
      persister ||= ems.class::Inventory::Persister::Targeted.new(ems)
      parser    ||= ems.class::Inventory::Parser.new(persister)

      property_filter_update_set.each do |property_filter_update|
        next if property_filter_update.filter != property_filter

        object_update_set = property_filter_update.objectSet
        next if object_update_set.blank?

        _log.info("Processing #{object_update_set.count} updates...")

        process_object_update_set(object_update_set).each do |managed_object, props|
          parser.parse(managed_object, props)
        end

        _log.info("Processing #{object_update_set.count} updates...Complete")
      end

      next if update_set.truncated

      ManagerRefresh::SaveInventory.save_inventory(ems, persister.inventory_collections)
      persister = nil
      parser = nil

      next unless initial

      _log.info("Refreshing initial inventory...Complete")
      initial = false

      break if run_once
    end
  ensure
    destroy_property_filter(property_filter)
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
end
