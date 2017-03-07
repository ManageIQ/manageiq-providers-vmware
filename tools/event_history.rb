require 'rbvmomi'
require 'trollop'

def parse_args(argv)
  opts = Trollop.options do
    banner <<-EOS
Print all event history from the VC specified by the ems parameter

Usage:
  rails r event_history.rb --ems=NAME_OF_EMS --events=[LIST,OF,EVENT,TYPES]
EOS

    opt :ems, 'EMS name', :type => :string
    opt :events, 'List of event types to include, e.g.: TaskEvent', :type => :string
  end

  opts
end

options = parse_args(ARGV)

ems = if options[:ems]
        ManageIQ::Providers::Vmware::InfraManager.find_by(:name => options[:ems])
      else
        ManageIQ::Providers::Vmware::InfraManager.first
      end

raise "EMS not found" if ems.nil?

host = ems.hostname
user = ems.authentication_userid(:default)
password = ems.authentication_password(:default)
filter_events = options[:events].try(:split, ',') || []

connect_opts = {
  :host => host,
  :user => user,
  :password => password,
  :insecure => true
}

vim = RbVmomi::VIM.connect connect_opts

begin
  eventCollector = vim.serviceContent.eventManager.CreateCollectorForEvents(
    :filter => RbVmomi::VIM::EventFilterSpec.new(:eventTypeId => filter_events)
  )

  eventCollector.RewindCollector()
  until (events = eventCollector.ReadNextEvents(:maxCount => 100)).empty?
    events.each do |event|
      puts "#{event.class.name} ID: #{event.key} Chain ID: #{event.chainId} Time: #{event.createdTime} #{event.fullFormattedMessage}"
    end
  end
ensure
  eventCollector.DestroyCollector() if eventCollector
end
