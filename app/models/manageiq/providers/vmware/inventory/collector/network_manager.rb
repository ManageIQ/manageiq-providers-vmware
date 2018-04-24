class ManageIQ::Providers::Vmware::Inventory::Collector::NetworkManager < ManageIQ::Providers::Vmware::Inventory::Collector
  attr_reader :network_name_mapping
  VappNetwork = Struct.new(:id, :name, :type, :is_shared, :gateway, :dns1, :dns2, :netmask, :enabled, :dhcp_enabled)

  def orgs
    return @orgs if @orgs.any?
    @orgs = connection.organizations
  end

  def vdc_networks
    return @vdc_networks if @vdc_networks.any?
    @vdc_networks = orgs.each_with_object([]) do |org, res|
      res.concat(org.networks.all)
    end
  end

  def vapp_networks
    return @vapp_networks if @vapp_networks.any?
    @vapp_networks = manager.orchestration_stacks.each_with_object([]) do |stack, res|
      fetch_network_configurations_for_vapp(stack.ems_ref).map do |net_conf|
        # 'none' is special network placeholder that we must ignore
        next if net_conf[:networkName] == 'none'

        $vcloud_log.debug("#{log_header} processing net_conf for vapp #{stack.ems_ref}: #{net_conf}")
        network_id = network_id_from_links(net_conf)
        $vcloud_log.debug("#{log_header} calculated vApp network id: #{network_id}")
        if (vdc_net = corresponding_vdc_network(net_conf, vdc_networks_idx))
          $vcloud_log.debug("#{log_header} skipping VDC network duplicate")
          memorize_network_name_mapping(stack.ems_ref, vdc_net.name, vdc_net.id)
        else
          memorize_network_name_mapping(stack.ems_ref, net_conf[:networkName], network_id)
          res << build_vapp_network(stack, network_id, net_conf)

          # routers connecting vApp networks to VDC networks
          if (parent_net = parent_vdc_network(net_conf, vdc_networks_idx))
            $vcloud_log.debug("#{log_header} connecting router to parent: #{parent_net}")
            @network_routers << {
              :net_conf   => net_conf,
              :network_id => network_id,
              :parent_net => parent_net
            }
          end
        end
      end
    end
  end

  def nics
    return @nics if @nics.any?
    @nics = manager.vms.each_with_object([]) do |vm, res|
      fetch_nic_configurations_for_vm(vm.ems_ref).each do |nic|
        next unless nic[:IsConnected]
        $vcloud_log.debug("#{log_header} processing NIC configuration for vm #{vm.ems_ref}: #{nic}")
        nic[:vm] = vm
        res << nic
      end
    end
  end

  def network_routers
    return @network_routers if @network_routers.any?
    vapp_networks
    @network_routers
  end

  def vdc_networks_idx
    return @vdc_networks_idx if @vdc_networks_idx.any?
    vdc_networks.index_by(&:id)
  end

  private

  def fetch_network_configurations_for_vapp(vapp_id)
    begin
      data = @connection.get_vapp(vapp_id).body
    rescue Fog::VcloudDirector::Errors::ServiceError => e
      $vcloud_log.error("#{log_header} could not fetch network configuration for vapp #{vapp_id}: #{e}")
      return []
    end
    Array.wrap(data.dig(:NetworkConfigSection, :NetworkConfig))
  end

  def fetch_nic_configurations_for_vm(vm_id)
    begin
      data = connection.get_network_connection_system_section_vapp(vm_id).body
    rescue Fog::VcloudDirector::Errors::ServiceError => e
      $vcloud_log.error("#{log_header} could not fetch NIC configuration for vm #{vm_id}: #{e}")
      return []
    end
    Array.wrap(data[:NetworkConnection])
  end

  # vCD API does not provide us with vApp network IDs for some reason. Luckily it provides
  # "Links" section whith API link to edit network page and network ID is part of this link.
  def network_id_from_links(data)
    return unless data[:Link]
    links = Array.wrap(data[:Link])
    links.each do |link|
      m = /.*\/network\/(?<id>[^\/]+)\/.*/.match(link[:href])
      return m[:id] unless m.nil? || m[:id].nil?
    end
    nil
  end

  # Detect when network configuration as reported by vapp is actually a VDC network.
  # In such cases vCD reports duplicate of VDC networks (all the same, only ID is different)
  # instead the original one, which would result in duplicate entries in the VMDB. When the
  # function above returns not nil, such network was detected. The returned value is then the
  # actual VDC network specification.
  def corresponding_vdc_network(net_conf, vdc_network_ids)
    if net_conf.dig(:networkName) == net_conf.dig(:Configuration, :ParentNetwork, :name)
      parent_vdc_network(net_conf, vdc_network_ids)
    end
  end

  def parent_vdc_network(net_conf, vdc_network_ids)
    vdc_network_ids[net_conf.dig(:Configuration, :ParentNetwork, :id)]
  end

  def memorize_network_name_mapping(vapp_id, network_name, network_id)
    @network_name_mapping[vapp_id] ||= {}
    @network_name_mapping[vapp_id][network_name] = network_id
  end

  def build_vapp_network(vapp, network_id, net_conf)
    n = VappNetwork.new(network_id)
    n.name = vapp_network_name(net_conf[:networkName], vapp)
    n.is_shared = false
    n.type = 'application/vnd.vmware.vcloud.vAppNetwork+xml'
    Array.wrap(net_conf.dig(:Configuration, :IpScopes)).each do |ip_scope|
      n.gateway = ip_scope.dig(:IpScope, :Gateway)
      n.netmask = ip_scope.dig(:IpScope, :Netmask)
      n.enabled = ip_scope.dig(:IpScope, :IsEnabled)
    end
    Array.wrap(net_conf.dig(:Configuration, :Features)).each do |feature|
      if feature[:DhcpService]
        n.dhcp_enabled = feature.dig(:DhcpService, :IsEnabled)
      end
    end
    n
  end

  def log_header
    location = caller_locations(1, 1)
    location = location.first if location.kind_of?(Array)
    "MIQ(#{self.class.name}.#{location.base_label})"
  end

  def vapp_network_name(name, vapp)
    "#{name} (#{vapp.name})"
  end
end
