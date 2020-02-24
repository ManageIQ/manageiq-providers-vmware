#!/usr/bin/env ruby

class EventCatcher
  def initialize(ems_id, hostname, username, password, port, page_size = 20)
    @ems_id    = ems_id
    @hostname  = hostname
    @username  = username
    @password  = password
    @port      = port
    @page_size = page_size
  end

  def run!
    vim                     = connect
    event_history_collector = create_event_history_collector(vim, page_size)
    property_filter         = create_property_filter(vim, event_history_collector)

    wait_for_updates(vim) do |property_change|
      next unless property_change.name =~ /latestPage.*/

      events = Array(property_change.val).map { |event| parse_event(event) }
      puts events
    end
  ensure
    property_filter&.DestroyPropertyFilter
    event_history_collector&.DestroyCollector
    vim&.close
  end

  private

  attr_reader :ems_id, :hostname, :username, :password, :port, :page_size

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
end

def main(args)
  event_catcher = EventCatcher.new(*args.values_at(:ems_id, :hostname, :username, :password, :port))
  event_catcher.run!
end

def parse_args
  require "optimist"

  Optimist.options do
    opt :ems_id,   "EMS ID",   :type => :int,    :default => ENV["EMS_ID"],   :required => ENV["EMS_ID"].nil?
    opt :hostname, "Hostname", :type => :string, :default => ENV["HOSTNAME"], :required => ENV["HOSTNAME"].nil?
    opt :username, "Username", :type => :string, :default => ENV["USERNAME"], :required => ENV["USERNAME"].nil?
    opt :password, "Password", :type => :string, :default => ENV["PASSWORD"], :required => ENV["PASSWORD"].nil?
    opt :port,     "Port",     :type => :int,    :default => (ENV["PORT"] || 443).to_i
  end
end

main(parse_args)
