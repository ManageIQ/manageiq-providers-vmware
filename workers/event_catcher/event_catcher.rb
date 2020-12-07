#!/usr/bin/env ruby

require "manageiq-messaging"
require "pathname"
require "sd_notify"

class EventCatcher
  def initialize(ems_id, hostname, username, password, port, messaging_host, messaging_port, page_size = 20)
    @ems_id         = ems_id
    @hostname       = hostname
    @username       = username
    @password       = password
    @port           = port
    @messaging_host = messaging_host
    @messaging_port = messaging_port
    @page_size      = page_size
  end

  def run!
    vim                     = connect
    event_history_collector = create_event_history_collector(vim, page_size)
    property_filter         = create_property_filter(vim, event_history_collector)

    notify_started

    wait_for_updates(vim) do |property_change|
      next unless property_change.name =~ /latestPage.*/

      events = Array(property_change.val).map { |event| parse_event(event) }
      publish_events(events)
    end
  ensure
    notify_stopping
    property_filter&.DestroyPropertyFilter
    event_history_collector&.DestroyCollector
    vim&.close
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
      :port     => 443,
      :rev      => '6.5',
    }

    require 'rbvmomi'
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
      :spec => RbVmomi::VIM.PropertyFilterSpec(
        :objectSet    => [
          RbVmomi::VIM.ObjectSpec(
            :obj => event_history_collector
          )
        ],
        :propSet      => [
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
        :service => "manageiq.ems-events",
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
    if ENV["NOTIFY_SOCKET"]
      SdNotify.watchdog
    else
      heartbeat_file = File.join(ENV["APP_ROOT"], "tmp", "#{ENV["GUID"]}.hb")
      timeout = 120
      File.write(heartbeat_file, (Time.now.utc + timeout).to_s)
    end
  end

  def notify_stopping
    SdNotify.stopping if ENV["NOTIFY_SOCKET"]
  end
end

def decrypt_env_vars
  require "open3"
  output, status = Open3.capture2("tools/decrypt_env_vars", :chdir => ENV["APP_ROOT"])

  # Skip the ** ManageIQ master, codename: Lasker comment
  output = output.split("\n")[1..-1].join("\n")

  YAML.load(output)
end

def setproctitle
  proc_title = "MIQ: Vmware::InfraManager::EventCatcher guid: #{ENV["GUID"]}"
  Process.setproctitle(proc_title)
end

def main(args)
  setproctitle

  event_catcher = EventCatcher.new(*args.values_at(:ems_id, :hostname, :username, :password, :port, :messaging_host, :messaging_port))
  event_catcher.run!
end

def parse_args
  require "optimist"

  env_vars = decrypt_env_vars

  Optimist.options do
    opt :ems_id,         "EMS ID",   :type => :int,          :default => env_vars["EMS_ID"]&.to_i,         :required => env_vars["EMS_ID"].nil?
    opt :hostname,       "Hostname", :type => :string,       :default => env_vars["HOSTNAME"],             :required => env_vars["HOSTNAME"].nil?
    opt :username,       "Username", :type => :string,       :default => env_vars["USERNAME"],             :required => env_vars["USERNAME"].nil?
    opt :password,       "Password", :type => :string,       :default => env_vars["PASSWORD"],             :required => env_vars["PASSWORD"].nil?
    opt :messaging_host, "Messaging Host", :type => :string, :default => env_vars["MESSAGING_HOST"],       :required => env_vars["MESSAGING_HOST"].nil?
    opt :messaging_port, "Messaging Port", :type => :int,    :default => env_vars["MESSAGING_PORT"]&.to_i, :required => env_vars["MESSAGING_PORT"].nil?
    opt :port,           "Port",     :type => :int,          :default => (env_vars["PORT"] || 443).to_i
  end
end

main(parse_args)
