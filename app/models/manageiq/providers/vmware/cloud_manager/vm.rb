class ManageIQ::Providers::Vmware::CloudManager::Vm < ManageIQ::Providers::CloudManager::Vm
  include_concern 'Operations'
  include_concern 'RemoteConsole'
  include_concern 'Reconfigure'

  supports :snapshots
  supports :remove_all_snapshots
  supports_not :remove_snapshot
  supports :snapshot_create
  supports :revert_to_snapshot
  supports :reconfigure_disks
  supports :reconfigure_disksize do
    unsupported_reason_add(:reconfigure_disksize, 'Cannot resize disks of a VM with snapshots') unless snapshots.empty?
  end
  supports :reconfigure_network_adapters

  def provider_object(connection = nil)
    connection ||= ext_management_system.connect
    connection.vms.get_single_vm(uid_ems)
  end

  POWER_STATES = {
    "creating"  => "powering_up",
    "off"       => "off",
    "on"        => "on",
    "unknown"   => "terminated",
    "suspended" => "suspended"
  }.freeze

  def self.params_for_create_snapshot
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
      ],
    }
  end

  def self.calculate_power_state(raw_power_state)
    # https://github.com/xlab-si/fog-vcloud-director/blob/master/lib/fog/vcloud_director/parsers/compute/vm.rb#L70
    POWER_STATES[raw_power_state.to_s] || "terminated"
  end

  def self.display_name(number = 1)
    n_('Instance (VMware vCloud)', 'Instances (VMware vCloud)', number)
  end
end
