require "manageiq-messaging"
require "sd_notify"
require "rbvmomi"

class EventCatcher
  def initialize(ems_id, default_endpoint, default_authentication, messaging_opts, page_size = 20)
    @ems_id         = ems_id
    @hostname       = default_endpoint["hostname"]
    @username       = default_authentication["userid"]
    @password       = default_authentication["password"]
    @port           = default_endpoint["port"]
    @messaging_host = messaging_opts["host"]
    @messaging_port = messaging_opts["port"]
    @page_size      = page_size
  end

  def run!
    vim                     = connect
    event_history_collector = create_event_history_collector(vim, page_size)
    property_filter         = create_property_filter(vim, event_history_collector)

    notify_started

    wait_for_updates(vim) do |property_change|
      next unless property_change.name.match?(/latestPage.*/)

      events = Array(property_change.val).map { |event| parse_event(event) }
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

  attr_reader :ems_id, :hostname, :messaging_host, :messaging_port, :password, :port, :page_size, :username

  def connect
    vim_opts = {
      :ns       => 'urn:vim25',
      :host     => hostname,
      :ssl      => true,
      :insecure => true,
      :path     => '/sdk',
      :port     => port,
      :rev      => '6.5',
    }

    RbVmomi::VIM.new(vim_opts).tap do |vim|
      vim.rev = vim.serviceContent.about.apiVersion
      vim.serviceContent.sessionManager.Login(:userName => username, :password => password)
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

  def wait_for_updates(vim)
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

          Array(object_update.changeSet).each do |property_change|
            yield property_change
          end
        end
      end
    end
  end

  def parse_event(event)
    event_type = event.class.wsdl_name

    result = {
      :ems_id     => ems_id,
      :event_type => event_type,
      :chain_id   => event.chainId,
      :is_task    => event_type == "TaskEvent",
      :source     => "VC",
      :message    => event.fullFormattedMessage,
      :timestamp  => event.createdTime,
      :full_data  => event.props
    }

    result
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
    @messaging_client ||= begin
      ManageIQ::Messaging::Client.open(
        :host       => messaging_host,
        :port       => messaging_port,
        :protocol   => :Kafka,
        :encoding   => "json",
        :client_ref => "vmware-event-catcher-#{ems_id}"
      )
    end
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

def setproctitle
  proc_title = "MIQ: Vmware::InfraManager::EventCatcher guid: #{ENV["GUID"]}"
  Process.setproctitle(proc_title)
end

def main(args)
  setproctitle

  default_endpoint = args["endpoints"]&.detect { |ep| ep["role"] == "default" }
  default_authentication = args["authentications"]&.detect { |auth| auth["authtype"] == "default" }

  event_catcher = EventCatcher.new(args["ems_id"], default_endpoint, default_authentication, args["messaging_opts"])

  event_catcher.run!
end

def parse_args
  require "json"
  JSON.parse($stdin.read)
end

main(parse_args)
