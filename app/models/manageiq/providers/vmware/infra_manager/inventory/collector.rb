require 'rbvmomi/vim'

class ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector
  include PropertyCollector
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
    property_filter = create_property_filter(vim)

    # Return if we don't receive any updates for 10 seconds break
    # so that we can check if we are supposed to exit
    options = RbVmomi::VIM.WaitOptions(:maxWaitSeconds => 10)

    # Send the "special initial data version" i.e. an empty string
    # so that we get all inventory back in the first update set
    version = ""

    _log.info("Refreshing initial inventory...")

    initial = true
    until exit_requested
      update_set = vim.propertyCollector.WaitForUpdatesEx(:version => version, :options => options)
      next if update_set.nil?

      # Save the new update set version
      version = update_set.version

      property_filter_update_set = update_set.filterSet
      next if property_filter_update_set.blank?

      property_filter_update_set.each do |property_filter_update|
        next if property_filter_update.filter != property_filter

        object_update_set = property_filter_update.objectSet
        next if object_update_set.blank?

        process_object_update_set(object_update_set)
      end

      next if update_set.truncated

      next unless initial

      _log.info("Refreshing initial inventory...Complete")
      initial = false
    end
  ensure
    property_filter.DestroyPropertyFilter unless property_filter.nil?
  end

  def process_object_update_set(object_update_set)
    _log.info("Processing #{object_update_set.count} updates...")

    object_update_set.each do |object_update|
      process_object_update(object_update)
    end

    _log.info("Processing #{object_update_set.count} updates...Complete")
  end

  def process_object_update(object_update)
    managed_object = object_update.obj

    case object_update.kind
    when "enter"
      process_object_update_enter(managed_object, object_update.changeSet)
    when "modify"
      process_object_update_modify(managed_object, object_update.changeSet)
    when "leave"
      process_object_update_leave(managed_object)
    end
  end

  def process_object_update_enter(obj, change_set, missing_set = [])
    process_object_update_modify(obj, change_set, missing_set)
  end

  def process_object_update_modify(_obj, change_set, _missing_set = [])
    props = {}

    change_set.each do |property_change|
      next if property_change.nil?

      case property_change.op
      when 'add'
        process_property_change_add(props, property_change)
      when 'remove', 'indirectRemove'
        process_property_change_remove(props, property_change)
      when 'assign'
        process_property_change_assign(props, property_change)
      end
    end
  end

  def process_object_update_leave(_obj)
  end

  def process_property_change_add(props, property_change)
    name = property_change.name

    props[name] = [] if props[name].nil?
    props[name] << property_change.val
  end

  def process_property_change_remove(props, property_change)
    props.delete(property_change.name)
  end

  def process_property_change_assign(props, property_change)
    props[property_change.name] = property_change.val
  end
end
