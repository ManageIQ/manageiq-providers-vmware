class ManageIQ::Providers::Vmware::InfraManager::Vm < ManageIQ::Providers::InfraManager::Vm
  include_concern 'ManageIQ::Providers::Vmware::InfraManager::VmOrTemplateShared'

  include_concern 'Operations'
  include_concern 'RemoteConsole'
  include_concern 'Reconfigure'
  include_concern 'Scanning'

  supports :clone do
    unsupported_reason_add(:clone, _('Clone operation is not supported')) if blank? || orphaned? || archived?
  end
  supports :publish do
    unsupported_reason_add(:publish, _('Publish operation is not supported')) if blank? || orphaned? || archived?
  end

  supports :reconfigure_disks
  supports :reconfigure_network_adapters
  supports :reconfigure_disksize do
    unsupported_reason_add(:reconfigure_disksize, 'Cannot resize disks of a VM with snapshots') unless snapshots.empty?
  end
  supports :reconfigure_cdroms
  supports :set_description
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

  def params_for_create_snapshot
    {
      :fields => [
        {
          :component  => 'text-field',
          :name       => 'name',
          :id         => 'name',
          :label      => _('Name'),
          :isRequired => true,
          :validate   => [{:type => 'required'}],
        },
        {
          :component => 'textarea',
          :name      => 'description',
          :id        => 'description',
          :label     => _('Description'),
        },
        {
          :component  => 'switch',
          :name       => 'memory',
          :id         => 'memory',
          :label      => _('Snapshot VM memory'),
          :onText     => _('Yes'),
          :offText    => _('No'),
          :isDisabled => current_state != 'on',
          :helperText => _('Snapshotting the memory is only available if the VM is powered on.'),
        },
      ],
    }
  end

  def self.display_name(number = 1)
    n_('Virtual Machine (VMware)', 'Virtual Machines (VMware)', number)
  end
end
