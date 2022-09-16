require_relative "event_parser"

class EventCatcher
  def initialize(ems, default_endpoint, default_authentication, messaging, logger, page_size = 20)
    @ems_id                 = ems["id"]
    @default_endpoint       = default_endpoint
    @default_authentication = default_authentication
    @logger                 = logger
    @messaging              = messaging
    @page_size              = page_size
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

      events = Array(property_change.val).map { |event| EventParser.parse_event(event).merge(:ems_id => ems_id) }
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

  attr_reader :ems_id, :default_endpoint, :default_authentication, :logger, :messaging, :page_size

  def connect
    vim_opts = {
      :ns       => 'urn:vim25',
      :ssl      => true,
      :host     => default_endpoint["hostname"],
      :port     => default_endpoint["port"] || 443,
      :insecure => default_endpoint["verify_ssl"] == OpenSSL::SSL::VERIFY_NONE,
      :path     => '/sdk',
      :rev      => '7.0',
    }

    RbVmomi::VIM.new(vim_opts).tap do |vim|
      vim.rev = vim.serviceContent.about.apiVersion
      vim.serviceContent.sessionManager.Login(
        :userName => default_authentication["userid"],
        :password => default_authentication["password"]
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
        :sender  => ems_id,
        :event   => event[:event_type],
        :payload => event
      )
    end
  end

  def messaging_client
    @messaging_client ||= ManageIQ::Messaging::Client.open(
      messaging.merge(:client_ref => "vmware-event-catcher-#{ems_id}")
    )
  end

  def notify_started
    SdNotify.ready if ENV["NOTIFY_SOCKET"]
  end

  def heartbeat
    SdNotify.watchdog if ENV["NOTIFY_SOCKET"]
  end

  def notify_stopping
    SdNotify.stopping if ENV["NOTIFY_SOCKET"]
  end
end
