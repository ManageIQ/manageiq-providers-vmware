class ManageIQ::Providers::Vmware::CloudManager::OrchestrationTemplate < OrchestrationTemplate
  def parameter_groups
    template = ManageIQ::Providers::Vmware::CloudManager::OvfTemplate.new(content)
    vapp_parameter_group + vapp_net_param_groups(template) + vm_param_groups(template)
  end

  def tabs
    template = ManageIQ::Providers::Vmware::CloudManager::OvfTemplate.new(content)

    [
      {
        :title        => "Basic Information",
        :stack_group  => deployment_options,
        :param_groups => vapp_parameter_group
      },
      {
        :title        => "vApp Networks",
        :param_groups => vapp_net_param_groups(template)
      },
      {
        :title        => "Instances",
        :param_groups => vm_param_groups(template)
      }
    ]
  end

  def vapp_parameter_group
    [OrchestrationTemplate::OrchestrationParameterGroup.new(
      :label      => 'vApp Parameters',
      :parameters => [
        OrchestrationTemplate::OrchestrationParameter.new(
          :name          => 'deploy',
          :label         => 'Deploy vApp',
          :data_type     => 'boolean',
          :default_value => true,
          :constraints   => [
            OrchestrationTemplate::OrchestrationParameterBoolean.new
          ]
        ),
        OrchestrationTemplate::OrchestrationParameter.new(
          :name          => 'powerOn',
          :label         => 'Power On vApp',
          :data_type     => 'boolean',
          :default_value => false,
          :constraints   => [
            OrchestrationTemplate::OrchestrationParameterBoolean.new
          ]
        )
      ],
    )]
  end

  def vm_param_groups(template)
    template.vms.each_with_index.map do |vm, vm_idx|
      vm_parameters = [
        OrchestrationTemplate::OrchestrationParameter.new(
          :name          => param_name('instance_name', [vm_idx]),
          :label         => 'Instance name',
          :data_type     => 'string',
          :required      => true,
          :default_value => vm.name
        ),
        OrchestrationTemplate::OrchestrationParameter.new(
          :name          => param_name('hostname', [vm_idx]),
          :label         => 'Instance Hostname',
          :description   => 'Can only contain alphanumeric characters and hypens',
          :data_type     => 'string',
          :required      => true,
          :default_value => vm.hostname,
          :constraints   => [
            OrchestrationTemplate::OrchestrationParameterPattern.new(
              :pattern     => '^\S+$',
              :description => 'No spaces allowed'
            )
          ]
        ),
        OrchestrationTemplate::OrchestrationParameter.new(
          :name          => param_name('num_cores', [vm_idx]),
          :label         => 'Number of virtual CPUs',
          :data_type     => 'integer',
          :required      => true,
          :default_value => vm.num_cores,
          :constraints   => [
            OrchestrationTemplate::OrchestrationParameterRange.new(
              :min_value   => 1,
              :max_value   => 128,
              :description => 'Must be between 1 and 128'
            )
          ]
        ),
        OrchestrationTemplate::OrchestrationParameter.new(
          :name          => param_name('cores_per_socket', [vm_idx]),
          :label         => 'Cores per socket',
          :description   => 'Must be divisor of number of virtual CPUs',
          :data_type     => 'integer',
          :required      => true,
          :default_value => vm.cores_per_socket,
          :constraints   => [
            OrchestrationTemplate::OrchestrationParameterRange.new(
              :min_value   => 1,
              :max_value   => 128,
              :description => 'Must be between 1 and 128'
            )
          ]
        ),
        OrchestrationTemplate::OrchestrationParameter.new(
          :name          => param_name('memory_mb', [vm_idx]),
          :label         => 'Total memory (MB)',
          :description   => 'Must not be less than 4MB',
          :data_type     => 'integer',
          :required      => true,
          :default_value => vm.memory_mb,
          :constraints   => [
            OrchestrationTemplate::OrchestrationParameterRange.new(:min_value => 4)
          ]
        ),
        OrchestrationTemplate::OrchestrationParameter.new(
          :name          => param_name('guest_customization', [vm_idx]),
          :label         => 'Guest customization',
          :description   => 'Check this to apply Hostname and NIC configuration for this VM to its Guest OS when
                            the VM is powered on. Guest OS must support this feature otherwise provisioning
                            will fail.',
          :data_type     => 'boolean',
          :default_value => vm.guest_customization,
          :constraints   => [
            OrchestrationTemplate::OrchestrationParameterBoolean.new
          ]
        ),
        OrchestrationTemplate::OrchestrationParameter.new(
          :name        => param_name('admin_password', [vm_idx]),
          :label       => 'Administrator Password',
          :description => 'Leave empty to auto generate',
          :data_type   => 'string'
        ),
        OrchestrationTemplate::OrchestrationParameter.new(
          :name          => param_name('admin_reset', [vm_idx]),
          :label         => 'Require password change',
          :description   => 'Require administrator to change password on first login',
          :data_type     => 'boolean',
          :default_value => false,
          :constraints   => [
            OrchestrationTemplate::OrchestrationParameterBoolean.new
          ]
        ),
      ]

      # Disks.
      vm.disks.each_with_index do |disk, disk_idx|
        vm_parameters << OrchestrationTemplate::OrchestrationParameter.new(
          :name          => param_name('disk_mb', [vm_idx, disk_idx]),
          :label         => "Disk #{disk.address} (MB)",
          :description   => "Must not be less than original Disk #{disk.address} size (#{disk.capacity_mb}MB)",
          :data_type     => 'integer',
          :required      => true,
          :default_value => disk.capacity_mb,
          :constraints   => [
            OrchestrationTemplate::OrchestrationParameterRange.new(:min_value => disk.capacity_mb)
          ]
        )
      end

      # NICs.
      vm.nics.each_with_index do |nic, nic_idx|
        vm_parameters += [
          OrchestrationTemplate::OrchestrationParameter.new(
            :name          => param_name('nic_network', [vm_idx, nic_idx]),
            :label         => "NIC##{nic.idx} Network",
            :data_type     => 'string',
            :default_value => nic.network,
            :constraints   => [
              OrchestrationTemplate::OrchestrationParameterAllowed.new(:allowed_values => template.vapp_network_names)
            ]
          ),
          OrchestrationTemplate::OrchestrationParameter.new(
            :name          => param_name('nic_mode', [vm_idx, nic_idx]),
            :label         => "NIC##{nic.idx} Mode",
            :data_type     => 'string',
            :default_value => nic.mode,
            :required      => true,
            :constraints   => [
              OrchestrationTemplate::OrchestrationParameterAllowed.new(
                :allowed_values => {
                  'DHCP'   => 'DHCP',
                  'MANUAL' => 'Static - Manual',
                  'POOL'   => 'Static - IP Pool'
                }
              )
            ]
          ),
          OrchestrationTemplate::OrchestrationParameter.new(
            :name          => param_name('nic_ip_address', [vm_idx, nic_idx]),
            :label         => "NIC##{nic.idx} IP Address",
            :description   => "Ignored unless Mode is set to 'Static - Manual'",
            :data_type     => 'string',
            :default_value => nic.ip_address,
            :constraints   => [ip_constraint]
          ),
        ]
      end

      OrchestrationTemplate::OrchestrationParameterGroup.new(
        :label      => vm.name.to_s,
        :parameters => vm_parameters
      )
    end
  end

  def vapp_net_param_groups(template)
    template.vapp_networks.each_with_index.map do |vapp_net, vapp_net_idx|
      vapp_net_parameters = [
        OrchestrationTemplate::OrchestrationParameter.new(
          :name        => param_name('parent', [vapp_net_idx]),
          :label       => 'Parent Network',
          :data_type   => 'string',
          :constraints => [
            OrchestrationTemplate::OrchestrationParameterAllowedDynamic.new(:fqname => '/Cloud/Orchestration/Operations/Methods/Available_Vdc_Networks')
          ]
        ),
        OrchestrationTemplate::OrchestrationParameter.new(
          :name          => param_name('fence_mode', [vapp_net_idx]),
          :label         => 'Fence Mode',
          :data_type     => 'string',
          :default_value => vapp_net.mode,
          :required      => true,
          :constraints   => [
            OrchestrationTemplate::OrchestrationParameterAllowed.new(
              :allowed_values => {
                'isolated'  => 'Isolated',
                'bridged'   => 'Bridged',
                'natRouted' => 'NAT'
              }
            )
          ]
        )
      ]

      vapp_net.subnets.each_with_index do |subnet, subnet_idx|
        vapp_net_parameters += [
          OrchestrationTemplate::OrchestrationParameter.new(
            :name          => param_name('gateway', [vapp_net_idx, subnet_idx]),
            :label         => 'Gateway',
            :data_type     => 'string',
            :default_value => subnet.gateway,
            :constraints   => [ip_constraint]
          ),
          OrchestrationTemplate::OrchestrationParameter.new(
            :name          => param_name('netmask', [vapp_net_idx, subnet_idx]),
            :label         => "Netmask",
            :data_type     => "string",
            :default_value => subnet.netmask,
            :constraints   => [ip_constraint]
          ),
          OrchestrationTemplate::OrchestrationParameter.new(
            :name          => param_name('dns1', [vapp_net_idx, subnet_idx]),
            :label         => 'DNS 1',
            :data_type     => 'string',
            :default_value => subnet.dns1,
            :constraints   => [ip_constraint]
          ),
          OrchestrationTemplate::OrchestrationParameter.new(
            :name          => param_name('dns2', [vapp_net_idx, subnet_idx]),
            :label         => 'DNS 2',
            :data_type     => 'string',
            :default_value => subnet.dns2,
            :constraints   => [ip_constraint]
          )
        ]
      end

      OrchestrationTemplate::OrchestrationParameterGroup.new(
        :label      => vapp_net.name.to_s,
        :parameters => vapp_net_parameters
      )
    end
  end

  def deployment_options(_manager_class = nil)
    stack_name_opt = OrchestrationTemplate::OrchestrationParameter.new(
      :name           => "stack_name",
      :label          => "vApp Name",
      :data_type      => "string",
      :description    => "Desired name of the vApp we're about to create",
      :required       => true,
      :reconfigurable => false
    )

    availability_opt = OrchestrationTemplate::OrchestrationParameter.new(
      :name        => "availability_zone",
      :label       => "Availability zone",
      :data_type   => "string",
      :description => "Availability zone where the stack will be deployed",
      :constraints => [
        OrchestrationTemplate::OrchestrationParameterAllowedDynamic.new(
          :fqname => "/Cloud/Orchestration/Operations/Methods/Available_Availability_Zones"
        )
      ]
    )

    vapp_template = OrchestrationTemplate::OrchestrationParameter.new(
      :name          => 'stack_template',
      :label         => 'vApp Template',
      :description   => 'vApp Template that this Service bases on',
      :data_type     => 'string',
      :required      => true,
      :default_value => id,
      :constraints   => [
        OrchestrationTemplate::OrchestrationParameterAllowed.new(
          :allowed_values => { id => name }
        )
      ]
    )

    [stack_name_opt, availability_opt, vapp_template]
  end

  def self.eligible_manager_types
    [ManageIQ::Providers::Vmware::CloudManager]
  end

  def validate_format
    if content
      ovf_doc = MiqXml.load(content)
      !ovf_doc.root.nil? && nil
    end
  rescue REXML::ParseException => err
    err.message
  end

  def param_name(param, indeces = [])
    "#{param}-#{indeces.join('-')}".chomp('-')
  end

  def ip_constraint
    OrchestrationTemplate::OrchestrationParameterPattern.new(
      :pattern     => '(^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?).){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$)?',
      :description => 'IP address'
    )
  end

  # Override md5 calculation on vapp templates because XML elements ordering is not guaranteed.
  # We observed annoying fact that vCloud returns randomly shuffled XML content for very same
  # vapp template, therefore MD5 content differs. For this reason we need to override md5 calculation
  # to return unique identifier instead actual checksum. Luckily, vapp templates are not modifyable on
  # vCloud dashboard, so we don't really need the checksum like other providers.
  def self.calc_md5(text)
    ManageIQ::Providers::Vmware::CloudManager::OvfTemplate.template_ems_ref(text) if text
  end
end
