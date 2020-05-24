class ManageIQ::Providers::Vmware::InfraManager::Vm < ManageIQ::Providers::InfraManager::Vm
  include_concern 'ManageIQ::Providers::Vmware::InfraManager::VmOrTemplateShared'

  include_concern 'Operations'
  include_concern 'RemoteConsole'
  include_concern 'Reconfigure'
  include_concern 'Scanning'

  supports :clone do
    unsupported_reason_add(:clone, _('Clone operation is not supported')) if blank? || orphaned? || archived?
  end

  supports :reconfigure_disks
  supports :reconfigure_network_adapters
  supports :reconfigure_disksize do
    unsupported_reason_add(:reconfigure_disksize, 'Cannot resize disks of a VM with snapshots') unless snapshots.empty?
  end
  supports :reconfigure_cdroms

  supports :rename

  def add_miq_alarm
    raise "VM has no EMS, unable to add alarm" unless ext_management_system
    ext_management_system.vm_add_miq_alarm(self)
  end
  alias_method :addMiqAlarm, :add_miq_alarm

  def scan_on_registered_host_only?
    state == "on"
  end

  # Show certain non-generic charts
  def cpu_ready_available?
    true
  end

  supports :snapshots
  supports :quick_stats

  def self.display_name(number = 1)
    n_('Virtual Machine (VMware)', 'Virtual Machines (VMware)', number)
  end
end
