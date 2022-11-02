require_relative "event_parser"
require "active_support/core_ext/numeric/time"
require "more_core_extensions/core_ext/string/to_i_with_method"

class EventCatcher
  def initialize(ems, endpoint, authentication, settings, messaging, logger, page_size = 20)
    @ems            = ems
    @endpoint       = endpoint
    @authentication = authentication
    @logger         = logger
    @messaging      = messaging
    @page_size      = page_size
    @settings       = settings
  end

  def run!
    vim                     = connect
    event_history_collector = create_event_history_collector(vim, page_size)
    property_filter         = create_property_filter(vim, event_history_collector)

    notify_started

    logger.info("Collecting events...")

    wait_for_updates(vim) do |property_change|
      logger.info(property_change.name)
      next unless property_change.name.match?(/latestPage.*/)

      events = Array(property_change.val).map do |event|
        EventParser.parse_event(event).merge(:ems_id => ems["id"])
      end

      logger.info(events.to_json)

      publish_events(events)
    end
  rescue Interrupt
    # Catch SIGINT
  ensure
    notify_stopping
    property_filter&.DestroyPropertyFilter
    event_history_collector&.DestroyCollector
    vim&.close
  end

  def stop!
  end

  private

  attr_reader :ems, :endpoint, :authentication, :logger, :messaging, :page_size, :settings

  def connect
    vim_opts = {
      :ns       => 'urn:vim25',
      :ssl      => true,
      :host     => endpoint["hostname"],
      :port     => endpoint["port"] || 443,
      :insecure => endpoint["verify_ssl"] == OpenSSL::SSL::VERIFY_NONE,
      :path     => '/sdk',
      :rev      => '7.0',
    }

    RbVmomi::VIM.new(vim_opts).tap do |vim|
      vim.rev = vim.serviceContent.about.apiVersion
      vim.serviceContent.sessionManager.Login(
        :userName => authentication["userid"],
        :password => authentication["password"]
      )
    end
  end

  def create_event_history_collector(vim, page_size)
    filter = RbVmomi::VIM.EventFilterSpec()

    event_manager = vim.serviceContent.eventManager
    event_manager.CreateCollectorForEvents(:filter => filter).tap do |c|
      c.SetCollectorPageSize(:maxCount => page_size)
    end
  end

  def create_property_filter(vim, event_history_collector)
    vim.propertyCollector.CreateFilter(
      :spec           => RbVmomi::VIM.PropertyFilterSpec(
        :objectSet => [
          RbVmomi::VIM.ObjectSpec(
            :obj => event_history_collector
          )
        ],
        :propSet   => [
          RbVmomi::VIM.PropertySpec(
            :type    => event_history_collector.class.wsdl_name,
            :all     => false,
            :pathSet => ["latestPage"]
          )
        ]
      ),
      :partialUpdates => true
    )
  end

  def wait_for_updates(vim, &block)
    version = nil
    options = RbVmomi::VIM.WaitOptions(:maxWaitSeconds => 60)

    loop do
      update_set = vim.propertyCollector.WaitForUpdatesEx(:version => version, :options => options)
      heartbeat
      next if update_set.nil?

      version = update_set.version

      Array(update_set.filterSet).each do |property_filter_update|
        Array(property_filter_update.objectSet).each do |object_update|
          next unless object_update.kind == "modify"

          Array(object_update.changeSet).each(&block)
        end
      end
    end
  end

  def publish_events(events)
    events.each do |event|
      messaging_client.publish_topic(
        :service => "manageiq.ems",
        :sender  => ems["id"],
        :event   => event[:event_type],
        :payload => event
      )
    end
  end

  def messaging_client
    @messaging_client ||= ManageIQ::Messaging::Client.open(
      messaging.merge(:client_ref => "vmware-event-catcher-#{ems["id"]}")
    )
  end

  def notify_started
    if ENV.fetch("NOTIFY_SOCKET", nil)
      SdNotify.ready
    elsif ENV.fetch("WORKER_HEARTBEAT_FILE", nil)
      heartbeat_to_file
    end
  end

  def heartbeat
    if ENV.fetch("NOTIFY_SOCKET", nil)
      SdNotify.watchdog
    elsif ENV.fetch("WORKER_HEARTBEAT_FILE", nil)
      heartbeat_to_file
    end
  end

  def notify_stopping
    SdNotify.stopping if ENV.fetch("NOTIFY_SOCKET", nil)
  end

  def heartbeat_to_file
    heartbeat_file = ENV.fetch("WORKER_HEARTBEAT_FILE")

    File.write(heartbeat_file, heartbeat_timeout)
  end

  def heartbeat_timeout
    timeout   = settings.dig(:workers, :worker_base, :event_catcher, :event_catcher_vmware, :heartbeat_timeout)
    timeout ||= settings.dig(:workers, :worker_base, :defaults, :heartbeat_timeout)
    timeout ||= "2.minutes"

    Time.now.to_i + timeout.to_i_with_method
  end
end
