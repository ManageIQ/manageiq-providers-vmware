class ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector
  include PropertyCollector
  include Vmdb::Logging

  def initialize(ems, threaded: true)
    @ems             = ems
    @exit_requested  = false
    @inventory_cache = ems.class::Inventory::Cache.new
    @saver           = ems.class::Inventory::Saver.new(:threaded => threaded)
    @vim_thread      = nil
  end

  def start
    saver.start_thread
    self.vim_thread = Thread.new { vim_collector }
  end

  def running?
    vim_thread&.alive?
  end

  def stop(join_timeout = nil)
    _log.info("#{log_header} Monitor updates thread exiting...")
    self.exit_requested = true
    return if join_timeout.nil?

    # The WaitOptions for WaitForUpdatesEx call sets maxWaitSeconds to 60 seconds
    vim_thread&.join(join_timeout)
    saver.stop_thread
  end

  private

  attr_reader   :ems, :inventory_cache, :saver
  attr_accessor :exit_requested, :vim_thread, :last_full_refresh

  def vim_collector
    _log.info("#{log_header} Monitor updates thread started")

    vim = connect
    property_filter = create_property_filter(vim)

    _log.info("#{log_header} Refreshing initial inventory")
    version = full_refresh(vim, property_filter)
    _log.info("#{log_header} Refreshing initial inventory...Complete")

    until exit_requested
      version = full_refresh_needed? ? full_refresh(vim, property_filter) : targeted_refresh(vim, property_filter, version)
    end

    _log.info("#{log_header} Monitor updates thread exited")
  rescue => err
    _log.error("#{log_header} Refresh failed")
    _log.log_backtrace(err)

    ems.update_attributes(:last_refresh_error => err.to_s, :last_refresh_date => Time.now.utc)
  ensure
    destroy_property_filter(property_filter)
    disconnect(vim)
  end

  def full_refresh(vim, property_filter)
    persister = full_persister_klass.new(ems)
    parser    = parser_klass.new(inventory_cache, persister)

    version, updated_objects = monitor_updates(vim, property_filter, "")

    parse_updates(vim, parser, updated_objects)
    parse_storage_profiles(vim, parser)
    save_inventory(persister)

    self.last_full_refresh = Time.now.utc

    version
  end

  def targeted_refresh(vim, property_filter, version)
    persister = targeted_persister_klass.new(ems)
    parser    = parser_klass.new(inventory_cache, persister)

    version, updated_objects = monitor_updates(vim, property_filter, version)

    parse_updates(vim, parser, updated_objects)
    save_inventory(persister)

    version
  end

  def monitor_updates(vim, property_filter, version)
    updated_objects = []

    begin
      update_set = wait_for_updates(vim, version)
      return version if update_set.nil?

      version = update_set.version
      updated_objects.concat(process_update_set(property_filter, update_set))
    end while update_set.truncated

    return version, updated_objects
  end

  def connect
    host = ems.hostname
    username, password = ems.auth_user_pwd

    _log.info("#{log_header} Connecting to #{username}@#{host}...")

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

    _log.info("#{log_header} Connected")
    conn
  end

  def pbm_connect(vim)
    require "rbvmomi/pbm"
    RbVmomi::PBM.connect(vim, :insecure => true)
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

  def process_update_set(property_filter, update_set)
    property_filter_update = update_set.filterSet.to_a.detect { |update| update.filter == property_filter }
    return if property_filter_update.nil?

    object_update_set = property_filter_update.objectSet
    return if object_update_set.blank?

    _log.info("#{log_header} Processing #{object_update_set.count} updates...")

    updates = process_object_update_set(object_update_set)

    _log.info("#{log_header} Processing #{object_update_set.count} updates...Complete")

    updates
  end

  def parse_updates(vim, parser, updated_objects)
    parser.parse_ext_management_system(ems, vim.serviceContent.about)

    updated_objects.each do |managed_object, update_kind, cached_props|
      uncached_props = retrieve_uncached_props(managed_object)
      props          = uncached_props.present? ? cached_props.deep_merge(uncached_props) : cached_props

      parser.parse(managed_object, update_kind, props)
    end
  end

  def process_object_update_set(object_update_set)
    object_update_set.map do |object_update|
      process_object_update(object_update)
    end
  end

  def process_object_update(object_update)
    managed_object = object_update.obj

    log_object_update(object_update)

    props =
      case object_update.kind
      when "enter"
        process_object_update_enter(managed_object, object_update.changeSet, object_update.missingSet)
      when "modify"
        process_object_update_modify(managed_object, object_update.changeSet, object_update.missingSet)
      when "leave"
        process_object_update_leave(managed_object)
      end

    return managed_object, object_update.kind, props
  end

  def process_object_update_enter(obj, change_set, _missing_set = [])
    inventory_cache.insert(obj, process_change_set(change_set))
  end

  def process_object_update_modify(obj, change_set, _missing_set = [])
    inventory_cache.update(obj) do |props|
      process_change_set(change_set, props)
    end
  end

  def process_object_update_leave(obj)
    inventory_cache.delete(obj)
  end

  def retrieve_uncached_props(obj)
    prop_set = uncached_prop_set(obj)
    return if prop_set.nil?

    props = obj.collect!(*prop_set)
    return if props.nil?

    props.each_with_object({}) do |(name, val), result|
      h, prop_str = hash_target(result, name)
      tag, _key   = tag_and_key(prop_str)

      h[tag] = val
    end
  end

  def uncached_prop_set(obj)
    @uncached_prop_set ||= {
      "HostSystem" => [
        "config.storageDevice.hostBusAdapter",
        "config.storageDevice.scsiLun",
        "config.storageDevice.scsiTopology.adapter",
      ]
    }.freeze

    return if obj.nil?

    @uncached_prop_set[obj.class.wsdl_name]
  end

  def parse_storage_profiles(vim, parser)
    pbm = pbm_connect(vim)

    profile_manager = pbm.serviceContent.profileManager
    profile_ids = profile_manager.PbmQueryProfile(
      :resourceType => RbVmomi::PBM::PbmProfileResourceType(:resourceType => "STORAGE")
    )

    storage_profiles = profile_manager.PbmRetrieveContent(:profileIds => profile_ids) unless profile_ids.empty?
    storage_profiles.each do |profile|
      parser.parse(profile, "enter", profile.props)
    end
  end

  def save_inventory(persister)
    saver.queue_save_inventory(persister)
  end

  def log_header
    "EMS: [#{ems.name}], id: [#{ems.id}]"
  end

  def log_object_update(object_update)
    _log.debug do
      object_str = "#{object_update.obj.class.wsdl_name}:#{object_update.obj._ref}"

      prop_changes = object_update.changeSet.map(&:name).take(5).join(", ")
      prop_changes << ", ..." if object_update.changeSet.length > 5

      s =  "#{log_header} Object: [#{object_str}] Kind: [#{object_update.kind}]"
      s << " Props: [#{prop_changes}]" if object_update.kind == "modify"
    end
  end

  def full_refresh_needed?
    (Time.now.utc - last_full_refresh) > full_refresh_interval
  end

  def full_refresh_interval
    (Settings.ems_refresh["vmwarews"].try(:refresh_interval) || Settings.ems_refresh.refresh_interval).to_i_with_method
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
