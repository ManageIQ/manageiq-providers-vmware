module ManageIQ::Providers
  class Vmware::CloudManager::OrchestrationServiceOptionConverter < ::ServiceOrchestration::OptionConverter
    include Vmdb::Logging

    def stack_create_options
      template = ManageIQ::Providers::Vmware::CloudManager::OvfTemplate.new(self.class.get_template(@dialog_options).content)
      options = {
        :deploy  => stack_parameters['deploy'] == 't',
        :powerOn => stack_parameters['powerOn'] == 't'
      }
      options[:vdc_id] = @dialog_options['dialog_availability_zone'] unless @dialog_options['dialog_availability_zone'].blank?
      options.merge!(customize_vapp_template(collect_vm_params(template), collect_vapp_net_params(template)))
    end

    private

    # customize_vapp_template will prepare the options in a format suitable for the fog-vcloud-director.
    # See https://github.com/xlab-si/fog-vcloud-director/blob/master/docs/examples-vapp-instantiate.md
    def customize_vapp_template(vm_params, vapp_net_params)
      source_vms = vm_params.map do |_, vm_opts|
        src_vm = {
          :vm_id    => "vm-#{vm_opts[:vm_id]}",
          :networks => parse_nics(vm_opts),
          :hardware => {
            :cpu    => { :num_cores => vm_opts['num_cores'], :cores_per_socket => vm_opts['cores_per_socket'] },
            :memory => { :quantity_mb => vm_opts['memory_mb'] },
            :disk   => parse_disks(vm_opts)
          }
        }
        src_vm[:name]                = vm_opts["instance_name"] if vm_opts.key?("instance_name")
        src_vm[:guest_customization] = { :ComputerName => vm_opts['hostname'] } if vm_opts.key?("hostname")
        src_vm
      end

      vapp_networks = vapp_net_params.map do |_, opts|
        {
          :name       => opts[:vapp_net_name],
          :parent     => opts['parent'],
          :fence_mode => opts['fence_mode'],
          :subnet     => parse_subnets(opts)
        }
      end

      {
        :source_vms    => source_vms,
        :vapp_networks => vapp_networks
      }
    end

    def collect_vm_params(template)
      vm_params = collect_stack_parameters(
        %w(instance_name vdc_network num_cores cores_per_socket memory_mb disk_mb hostname nic_network nic_mode nic_ip_address)
      )
      # Reverse lookup by indeces.
      vm_params.each do |vm_idx, obj|
        obj[:vm_id] = template.vm_id_from_idx(vm_idx)
        obj['disk_mb'].each do |disk|
          disk[:disk_id] = template.disk_id_from_idx(vm_idx, *disk[:subkeys])
        end
      end
      vm_params
    end

    def collect_vapp_net_params(template)
      vapp_net_params = collect_stack_parameters(%w(gateway netmask dns1 dns2 parent fence_mode))
      # Reverse lookup by indeces.
      vapp_net_params.each do |vapp_net_idx, obj|
        obj[:vapp_net_name] = template.vapp_net_name_from_idx(vapp_net_idx)
      end
      vapp_net_params
    end

    def collect_stack_parameters(allowed)
      stack_parameters.each_with_object({}) do |(k, value), params|
        allowed.each do |param|
          param_match = k.match(/#{param}(-[0-9]+)?(-[0-9]+)?(-[0-9]+)?/)
          next if param_match.nil?

          keys = param_match.captures.compact.map { |c| Integer(c.sub(/^-/, '')) }
          params[keys.first] ||= {}

          if keys.count > 1
            params[keys.first][param] ||= []
            params[keys.first][param] << { :subkeys => keys[1..-1], :value => value }
            params[keys.first][param].sort_by! { |el| el[:subkeys] }
          else
            params[keys.first][param] = value
          end
        end
      end
    end

    def parse_disks(opts)
      return if opts['disk_mb'].blank?
      opts['disk_mb'].map { |disk| { :id => disk[:disk_id], :capacity_mb => disk[:value] } }
    end

    def parse_subnets(opts)
      return unless opts['gateway']
      Array.new(opts['gateway'].size) do |idx|
        {
          :gateway => option_value(opts['gateway'], [idx]),
          :netmask => option_value(opts['netmask'], [idx]),
          :dns1    => option_value(opts['dns1'], [idx]),
          :dns2    => option_value(opts['dns2'], [idx]),
        }
      end
    end

    def parse_nics(opts)
      return unless opts['nic_network']
      Array.new(opts['nic_network'].size) do |idx|
        {
          :networkName             => option_value(opts['nic_network'], [idx]).presence || 'none',
          :IpAddressAllocationMode => option_value(opts['nic_mode'], [idx]),
          :IpAddress               => option_value(opts['nic_ip_address'], [idx]),
          :IsConnected             => true
        }
      end
    end

    def option_value(opts_group, subkeys)
      opt = opts_group.detect { |o| o[:subkeys] == subkeys }
      opt[:value] unless opt.nil?
    end
  end
end
