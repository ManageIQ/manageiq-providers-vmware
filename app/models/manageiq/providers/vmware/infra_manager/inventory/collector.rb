class ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector
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
        _log.error("Caught exception #{err.message}")
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
      parser    ||= ems.class::Inventory::Parser.new(ems, persister)

      property_filter_update_set.each do |property_filter_update|
        next if property_filter_update.filter != property_filter

        object_update_set = property_filter_update.objectSet
        next if object_update_set.blank?

        _log.info("Processing #{object_update_set.count} updates...")
        object_update_set.compact.each { |object_update| parser.parse(object_update) }
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
    property_filter.DestroyPropertyFilter unless property_filter.nil?
  end
end
