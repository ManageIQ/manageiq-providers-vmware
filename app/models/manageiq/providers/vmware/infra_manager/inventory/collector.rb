class ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector
  include PropertyCollector
  include Vmdb::Logging

  def initialize(ems)
    @ems            = ems
    @exit_requested = false
    @cache          = cache_klass.new
    @saver          = saver_klass.new
    @vim_thread     = nil
  end

  def refresh
    self.exit_requested = true
    vim_collector
  end

  def start
    self.vim_thread = vim_collector_thread
  end

  def running?
    vim_thread&.alive?
  end

  def stop(join_timeout = 2.minutes)
    _log.info("#{log_header} Monitor updates thread exiting...")

    # The WaitOptions for WaitForUpdatesEx call sets maxWaitSeconds to 60 seconds
    self.exit_requested = true
    vim_thread&.join(join_timeout)
    self.exit_requested = false
  end

  def restart(join_timeout = 2.minutes)
    stop(join_timeout)
    start
  end

  attr_accessor :cache, :categories_by_id, :ca_file, :tags_by_id, :tag_ids_by_attached_object

  private

  attr_reader   :ems, :saver
  attr_accessor :exit_requested, :vim_thread, :last_full_refresh

  def vim_collector_thread
    Thread.new { vim_collector }
  end

  def vim_collector
    _log.info("#{log_header} Monitor updates thread started")

    vim = vim_connect
    property_filter = create_property_filter(vim, ems_inventory_filter_spec(vim))

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

    ems.update(:last_refresh_error => err.to_s, :last_refresh_date => Time.now.utc)
  ensure
    destroy_property_filter(property_filter)
    disconnect(vim)
  end

  def full_refresh(vim, property_filter)
    persister = full_persister_klass.new(ems)
    parser    = parser_klass.new(self, persister)

    version, updated_objects = monitor_updates(vim, property_filter, "")

    cis = cis_connect(vim)

    collect_cis_taggings(cis) if cis.present?

    parse_updates(vim, parser, updated_objects)
    parse_storage_profiles(vim, parser)
    parse_content_libraries(cis, parser) if cis.present?

    save_inventory(persister)

    self.last_full_refresh = Time.now.utc
    clear_cis_taggings

    version
  end

  def targeted_refresh(vim, property_filter, version)
    version, updated_objects = monitor_updates(vim, property_filter, version)
    if updated_objects.any?
      persister = targeted_persister_klass.new(ems)
      parser    = parser_klass.new(self, persister)

      parse_updates(vim, parser, updated_objects)
      save_inventory(persister)

      # Prevent WaitForUpdatesEx from "spinning" in a tight loop if updates are
      # constantly available.  This allows for more updates to be batched together
      # making for more efficient saving and reducing the API call load on the VC.
      sleep(refresh_settings.update_poll_interval)
    end

    version
  end

  def monitor_updates(vim, property_filter, version)
    updated_objects = []

    loop do
      update_set = wait_for_updates(vim, version)
      break if update_set.nil?

      version = update_set.version
      updated_objects.concat(process_update_set(property_filter, update_set))
      break unless update_set.truncated
    end

    return version, updated_objects
  end

  def vim_connect
    host = ems.hostname
    port = ems.port || 443
    username, password = ems.auth_user_pwd

    insecure = ems.verify_ssl == OpenSSL::SSL::VERIFY_NONE

    _log.info("#{log_header} Connecting to #{username}@#{host}...")

    self.ca_file = build_ca_file

    vim_opts = {
      :ns       => 'urn:vim25',
      :host     => host,
      :ssl      => true,
      :insecure => insecure,
      :ca_file  => ca_file&.path,
      :path     => '/sdk',
      :port     => port,
      :rev      => '6.5',
    }

    require 'rbvmomi'
    conn = RbVmomi::VIM.new(vim_opts).tap do |vim|
      vim.rev = vim.serviceContent.about.apiVersion
      vim.serviceContent.sessionManager.Login(:userName => username, :password => password)
    end

    _log.info("#{log_header} Connected")
    conn
  end

  def build_ca_file
    return if ems.certificate_authority.blank?

    Tempfile.new.tap do |f|
      f.write(ems.certificate_authority)
      f.close
    end
  end

  def pbm_connect(vim)
    require "rbvmomi/pbm"
    RbVmomi::PBM.connect(vim, :port => vim.http.port, :insecure => true)
  end

  def cis_connect(vim)
    return if vim.rev < '6.0' || vim.serviceContent.about.apiType != 'VirtualCenter'

    ems.connect(:service => :cis)
  end

  def disconnect(vim)
    return if vim.nil?

    # sessionManager.Logout and close the http connection
    vim.close

    # Cleanup the certificate authority file if it exists
    if ca_file
      ca_file.close
      ca_file.unlink
      self.ca_file = nil
    end
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
      props = cached_props

      uncached_props = retrieve_uncached_props(managed_object) unless update_kind == "leave"
      props          = props.deep_merge(uncached_props) if uncached_props.present?

      retrieve_extra_props(managed_object, props)

      parser.parse(managed_object, update_kind, props)
    rescue => err
      _log.warn("Failed to parse #{managed_object.class.wsdl_name}:#{managed_object._ref}: #{err}")
      _log.log_backtrace(err)
      raise
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
    cache.insert(obj, process_change_set(change_set))
  end

  def process_object_update_modify(obj, change_set, _missing_set = [])
    cache.update(obj) do |props|
      process_change_set(change_set, props)
    end
  end

  def process_object_update_leave(obj)
    cache.delete(obj)
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
  rescue RbVmomi::Fault => err
    _log.warn("Unable to retrieve uncached properties for #{obj.class.wsdl_name}:#{obj._ref}: #{err}")
    _log.log_backtrace
    nil
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

  def retrieve_extra_props(obj, cached_props)
    case obj.class.wsdl_name
    when "CustomizationSpecManager"
      retrieve_customization_spec(obj, cached_props)
    end
  end

  def retrieve_customization_spec(spec_manager, cached_props)
    cached_props[:info].to_a.each do |spec_info|
      spec_info.props[:spec] = spec_manager.GetCustomizationSpec(:name => spec_info.name)&.spec
    rescue RbVmomi::Fault => err
      # Don't fail the refresh for issues with specific items
      _log.warn("Failed to get customization spec for [#{spec_info.name}]: #{err}")
    end
  end

  def parse_content_libraries(api_client, parser)
    require 'vsphere-automation-content'

    library_api      = VSphereAutomation::Content::LibraryApi.new(api_client)
    library_item_api = VSphereAutomation::Content::LibraryItemApi.new(api_client)

    library_ids = library_api.list&.value.to_a
    library_ids.each do |lib_id|
      library_item_ids = library_item_api.list(lib_id)&.value.to_a
      library_item_ids.to_a.each do |item_id|
        library_item = library_item_api.get(item_id)&.value
        parser.parse_content_library_item(library_item) if library_item
      end
    end
  rescue VSphereAutomation::ApiError, Timeout::Error => err
    _log.warn("Failed to collect Content Libraries: #{err}")
  end

  def collect_cis_taggings(api_client)
    tagging_category_api        = VSphereAutomation::CIS::TaggingCategoryApi.new(api_client)
    tagging_tag_api             = VSphereAutomation::CIS::TaggingTagApi.new(api_client)
    tagging_tag_association_api = VSphereAutomation::CIS::TaggingTagAssociationApi.new(api_client)

    category_ids     = tagging_category_api.list&.value
    tag_ids          = tagging_tag_api.list&.value

    categories       = category_ids.to_a.map { |category_id| tagging_category_api.get(category_id)&.value }.compact
    tags             = tag_ids.to_a.map { |tag_id| tagging_tag_api.get(tag_id)&.value }.compact

    self.categories_by_id = categories.index_by(&:id)
    self.tags_by_id       = tags.index_by(&:id)

    self.tag_ids_by_attached_object = Hash.new { |h, k| h[k] = Hash.new { |h1, k1| h1[k1] = [] } }

    tags.each do |tag|
      tagging_tag_association_api.list_attached_objects(tag.id)&.value.to_a.each do |obj|
        tag_ids_by_attached_object[obj.type][obj.id] << tag.id
      end
    end
  rescue VSphereAutomation::ApiError, Timeout::Error => err
    _log.warn("Failed to collect Taggings: #{err}")
  end

  # These are only collected for full refreshes, after a full they can be cleared
  # to free up memory and prevent targeted refreshes from trying to map labels
  def clear_cis_taggings
    self.categories_by_id = self.tags_by_id = self.tag_ids_by_attached_object = nil
  end

  def parse_storage_profiles(vim, parser)
    pbm = pbm_connect(vim)

    profile_ids = pbm.serviceContent.profileManager.PbmQueryProfile(
      :resourceType => RbVmomi::PBM::PbmProfileResourceType(:resourceType => "STORAGE")
    )

    return if profile_ids.empty?

    storage_profiles = pbm.serviceContent.profileManager.PbmRetrieveContent(:profileIds => profile_ids)
    storage_profiles.to_a.each do |profile|
      persister_storage_profile = parser.parse(profile, "enter", profile.props)

      matching_hubs = pbm.serviceContent.placementSolver.PbmQueryMatchingHub(:profile => profile.profileId)
      matching_hubs.to_a.each do |placement_hub|
        next unless placement_hub.hubType == "Datastore"

        parser.parse_pbm_placement_hub(persister_storage_profile, placement_hub, "enter", placement_hub.props)
      end
    end
  rescue RbVmomi::Fault, Nokogiri::SyntaxError => err
    _log.warn("#{log_header} Unable to collect storage profiles: #{err}")
  end

  def save_inventory(persister)
    saver.save_inventory(persister)
  end

  def log_header
    "EMS: [#{ems.name}], id: [#{ems.id}]"
  end

  def log_object_update(object_update)
    _log.debug do
      object_str = "#{object_update.obj.class.wsdl_name}:#{object_update.obj._ref}"

      s = "#{log_header} Object: [#{object_str}] Kind: [#{object_update.kind}]"
      if object_update.kind == "modify"
        prop_changes = object_update.changeSet.map(&:name).take(5).join(", ")
        prop_changes << ", ..." if object_update.changeSet.length > 5

        s << " Props: [#{prop_changes}]"
      end

      s
    end
  end

  def full_refresh_needed?
    (Time.now.utc - last_full_refresh) > full_refresh_interval
  end

  def full_refresh_interval
    (refresh_settings.refresh_interval || Settings.ems_refresh.refresh_interval).to_i_with_method
  end

  def refresh_settings
    Settings.ems_refresh.vmwarews
  end

  def cache_klass
    ManageIQ::Providers::Vmware::InfraManager::Inventory::Cache
  end

  def full_persister_klass
    ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister::Full
  end

  def targeted_persister_klass
    ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister::Targeted
  end

  def parser_klass
    ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  end

  def saver_klass
    ManageIQ::Providers::Vmware::InfraManager::Inventory::Saver
  end
end
