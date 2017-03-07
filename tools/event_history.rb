require 'rbvmomi'

#TODO parse command line args
ems = ManageIQ::Providers::Vmware::InfraManager.first
host = ems.hostname
user = ems.authentication_userid(:default)
password = ems.authentication_password(:default)
filter_events = ['TaskEvent', 'VmBeingDeployedEvent', 'VmDeployedEvent']

connect_opts = {
  :host => host,
  :user => user,
  :password => password,
  :insecure => true
}

vim = RbVmomi::VIM.connect connect_opts

eventCollector = vim.serviceContent.eventManager.CreateCollectorForEvents(
  :filter => RbVmomi::VIM::EventFilterSpec.new(:eventTypeId => filter_events)
)

eventCollector.RewindCollector()
until (events = eventCollector.ReadNextEvents(:maxCount => 100)).empty?
  events.each do |event|
    next if event.kind_of?(RbVmomi::VIM::TaskEvent) && event.info.name != 'CloneVM_Task'
    puts "#{event.class.name} ID: #{event.key} Chain ID: #{event.chainId} Time: #{event.createdTime} VM: #{event.vm.vm}: #{event.fullFormattedMessage}"
  end
end

eventCollector.DestroyCollector()
