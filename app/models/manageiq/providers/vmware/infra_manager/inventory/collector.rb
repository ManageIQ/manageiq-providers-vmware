class ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector
  include InventoryCache
  include PropertyCollector
  include Vmdb::Logging

  attr_reader :ems, :exit_requested
  private     :ems, :exit_requested

  def initialize(ems)
    @ems             = ems
    @exit_requested  = false
  end

  def run
    until exit_requested
      vim = connect(ems.address, ems.authentication_userid, ems.authentication_password)

      begin
        wait_for_updates(vim)
      rescue RbVmomi::Fault => err
        _log.err("Caught exception #{err.message}")
        _log.log_backtrace(err)
      ensure
        vim.close unless vim.nil?
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

  private

  def connect(host, username, password)
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

        process_object_update_set(object_update_set) { |obj, props| parser.parse(obj, props) }
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
    property_filter.DestroyPropertyFilter unless property_filter.nil?
  end

  def process_object_update_set(object_update_set, &block)
    _log.info("Processing #{object_update_set.count} updates...")

    object_update_set.each do |object_update|
      process_object_update(object_update, &block)
    end

    _log.info("Processing #{object_update_set.count} updates...Complete")
  end

  def process_object_update(object_update)
    managed_object = object_update.obj
    props =
      case object_update.kind
      when "enter", "modify"
        process_object_update_modify(managed_object, object_update.changeSet)
      when "leave"
        process_object_update_leave(managed_object)
      end

    yield managed_object, props if block_given?

    return managed_object, props
  end

  def process_object_update_modify(obj, change_set, _missing_set = [])
    obj_type = obj.class.wsdl_name
    obj_ref  = obj._ref

    props = inventory_cache[obj_type][obj_ref].dup
    remove_props = []

    change_set.each do |property_change|
      next if property_change.nil?

      case property_change.op
      when 'add'
        process_property_change_add(props, property_change)
      when 'remove', 'indirectRemove'
        process_property_change_remove(props, remove_props, property_change)
      when 'assign'
        process_property_change_assign(props, property_change)
      end
    end

    change_props = {
      :update => props,
      :remove => remove_props,
    }

    update_inventory_cache(obj_type, obj_ref, props)
    change_props
  end

  def process_object_update_leave(obj)
    obj_type = obj.class.wsdl_name
    obj_ref  = obj._ref

    inventory_cache[obj_type].delete(obj_ref)

    nil
  end

  def process_property_change_add(props, property_change)
    name = property_change.name

    props[name] ||= []
    props[name] << property_change.val
  end

  def process_property_change_remove(props, remove_props, property_change)
    props.delete(property_change.name)
    remove_props.push(property_change.name)
  end

  def process_property_change_assign(props, property_change)
    props[property_change.name] = property_change.val
  end
end
