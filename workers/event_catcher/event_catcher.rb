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
    @messaging_host = messaging_opts["host"] || "localhost"
    @messaging_port = messaging_opts["port"] || 9092
    @page_size      = page_size
  end

  def run!
    vim                     = connect
    event_history_collector = create_event_history_collector(vim, page_size)
    property_filter         = create_property_filter(vim, event_history_collector)

    notify_started

    puts "Collecting events..."
    wait_for_updates(vim) do |property_change|
      puts property_change.name
      next unless property_change.name.match?(/latestPage.*/)

      events = Array(property_change.val).map { |event| parse_event(event) }
      puts events.to_json
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

  def parse_event(event)
    event_type = event.class.wsdl_name
    is_task    = event_type == "TaskEvent"

    if is_task
      sub_event_type = event.info&.name

      # Handle special cases
      case sub_event_type
      when nil
        # Handle cases wehre event name is missing
        sub_event_type   = "PowerOnVM_Task"    if event.fullFormattedMessage.to_s.downcase == "task: power on virtual machine"
        sub_event_type ||= "DrsMigrateVM_Task" if event.info&.descriptionId == "Drm.ExecuteVMotionLRO"
        if sub_event_type.nil?
          puts "Event Type cannot be determined for TaskEvent.  Using generic eventType [TaskEvent] instead"
          sub_event_type = "TaskEvent"
        end
      when "Rename_Task", "Destroy_Task"
        # Handle case where event name is overloaded
        sub_event_name = event.info.descriptionId.split(".").first
        sub_event_name = "VM"      if sub_event_name == "VirtualMachine"
        sub_event_name = "Cluster" if sub_event_name == "ClusterComputeResource"
        sub_event_type.gsub!(/_/, "#{sub_event_name}_")
      end

      event_type = sub_event_type
    elsif event_type == "EventEx"
      sub_event_type = event.eventTypeId
      event_type     = sub_event_type if sub_event_type.present?
    end

    result = {
      :ems_id     => ems_id,
      :event_type => event_type,
      :chain_id   => event.chainId,
      :is_task    => is_task,
      :source     => "VC",
      :message    => event.fullFormattedMessage,
      :timestamp  => event.createdTime,
      :full_data  => event.props
    }

    result[:username] = event.userName if event.userName.present?

    # Get the vm information
    vm_key = "vm"          if event.props.key?("vm")
    vm_key = "sourceVm"    if event.props.key?("sourceVm")
    vm_key = "srcTemplate" if event.props.key?("srcTemplate")
    if vm_key
      vm_data = event.send(vm_key)

      result[:vm_ems_ref]  = vm_data&.vm                 if vm_data&.vm
      result[:vm_name]     = CGI.unescape(vm_data&.name) if vm_data&.name
      result[:vm_location] = vm_data&.path               if vm_data&.path
      result[:vm_uid_ems]  = vm_data&.uuid               if vm_data&.uuid

      result
    end

    # Get the dest vm information
    has_dest = false
    if %w[sourceVm srcTemplate].include?(vm_key)
      vm_data = event.vm
      if vm_data
        result[:dest_vm_ems_ref]  = vm_data&.vm                 if vm_data&.vm
        result[:dest_vm_name]     = CGI.unescape(vm_data&.name) if vm_data&.name
        result[:dest_vm_location] = vm_data&.path               if vm_data&.path
      end

      has_dest = true
    elsif event.props.key?("destName")
      result[:dest_vm_name] = event.destName
      has_dest = true
    end

    if event.props.key?(:host)
      result[:host_name]    = event.host.name
      result[:host_ems_ref] = event.host.host
    end

    if has_dest
      host_data = event.props["destHost"] || event.props["host"]
      if host_data
        result[:dest_host_ems_ref] = host_data["host"]
        result[:dest_host_name]    = host_data["name"]
      end
    end

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
    @messaging_client ||= ManageIQ::Messaging::Client.open(
      :host       => messaging_host,
      :port       => messaging_port,
      :protocol   => :Kafka,
      :encoding   => "json",
      :client_ref => "vmware-event-catcher-#{ems_id}"
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

def setproctitle
  proc_title = "MIQ: Vmware::InfraManager::EventCatcher guid: #{ENV["GUID"]}"
  Process.setproctitle(proc_title)
end

def main(args)
  setproctitle

  ems = args["ems"].detect { |e| e["type"] == "ManageIQ::Providers::Vmware::InfraManager" }

  default_endpoint       = ems["endpoints"].detect { |ep| ep["role"] == "default" }
  default_authentication = ems["authentications"].detect { |auth| auth["authtype"] == "default" }

  event_catcher = EventCatcher.new(ems["id"], default_endpoint, default_authentication, {}) # TODO: args["messaging_opts"])

  event_catcher.run!
end

def parse_args
  require "json"
  JSON.parse($stdin.read)
end

main(parse_args)
