class ManageIQ::Providers::Vmware::Inventory::Parser::NetworkManager < ManageIQ::Providers::Vmware::Inventory::Parser
  def parse
    cloud_networks
    cloud_subnets
    network_routers
    network_ports
    floating_ips
  end

  def cloud_networks
    collector.vdc_networks.each do |vdc_network|
      parse_network(vdc_network, cloud_network_vdc_type)
    end
    collector.vapp_networks.each do |vapp_network|
      parse_network(vapp_network, cloud_network_vapp_type)
    end
  end

  def cloud_subnets
    collector.vdc_networks.each do |vdc_subnet|
      parse_network_subnet(vdc_subnet)
    end
    collector.vapp_networks.each do |vapp_subnet|
      parse_network_subnet(vapp_subnet)
    end
  end

  def network_routers
    collector.network_routers.each do |router|
      network_router = persister.network_routers.find_or_build("#{router[:network_id]}---#{router[:parent_net].id}").assign_attributes(
        :name          => "Router #{router[:parent_net].name} -> #{router.dig(:net_conf, :networkName)}",
        :cloud_network => persister.cloud_networks.lazy_find(router[:parent_net].id),
      )

      cloud_subnet = persister.cloud_subnets.find("subnet-#{router[:network_id]}")
      cloud_subnet.network_router = network_router
    end
  end

  def network_ports
    collector.nics.each do |port|
      network_port = persister.network_ports.find_or_build(port_id(port)).assign_attributes(
        :name        => port_name(port),
        :device_ref  => port[:vm].id,
        :device      => port[:vm],
        :mac_address => port.dig(:MACAddress)
      )

      network_id = read_network_name_mapping(port[:vm].orchestration_stack.ems_ref, port.dig(:network))
      network = persister.cloud_networks.find(network_id)

      next if network.nil?
      network_port.cloud_subnet_network_ports = [
        persister.cloud_subnet_network_ports.find_or_build_by(
          :network_port => network_port,
          :address      => port[:IpAddress],
          :cloud_subnet => persister.cloud_subnets.lazy_find("subnet-#{read_network_name_mapping(port[:vm].orchestration_stack.ems_ref, port.dig(:network))}")
        )
      ]
    end
  end

  def floating_ips
    collector.nics.each do |nic_data|
      next unless nic_data[:ExternalIpAddress]

      persister.floating_ips.find_or_build(floating_ip_id(nic_data)).assign_attributes(
        :address          => nic_data[:ExternalIpAddress],
        :fixed_ip_address => nic_data[:ExternalIpAddress],
        :cloud_network    => persister.cloud_networks.lazy_find(read_network_name_mapping(nic_data[:vm].orchestration_stack.ems_ref, nic_data[:network])),
        :network_port     => persister.network_ports.lazy_find(port_id(nic_data)),
        :vm               => nic_data[:vm],
        :type             => 'ManageIQ::Providers::Vmware::NetworkManager::FloatingIp'
      )
    end
  end

  private

  def parse_network(network, type)
    enabled = network.enabled if network.respond_to?(:enabled)
    cloud_network = persister.cloud_networks.find_or_build(network.id).assign_attributes(
      :name    => network.name,
      :shared  => network.is_shared,
      :type    => type,
      :cidr    => to_cidr(network.gateway, network.netmask),
      :enabled => enabled
    )

    cloud_network
  end

  def parse_network_subnet(network)
    dhcp_enabled = network.dhcp_enabled if network.respond_to?(:dhcp_enabled)
    cloud_subnet = persister.cloud_subnets.find_or_build(subnet_id(network)).assign_attributes(
      :name            => subnet_name(network),
      :gateway         => network.gateway,
      :dns_nameservers => [network.dns1, network.dns2].compact,
      :cloud_network   => persister.cloud_networks.lazy_find(network.id),
      :cidr            => to_cidr(network.gateway, network.netmask),
      :dhcp_enabled    => dhcp_enabled
    )

    cloud_subnet
  end

  def read_network_name_mapping(vapp_id, network_name)
    collector.network_name_mapping.dig(vapp_id, network_name)
  end

  def to_cidr(address, netmask)
    return unless address.to_s =~ Resolv::IPv4::Regex && netmask.to_s =~ Resolv::IPv4::Regex
    address + '/' + netmask.to_s.split(".").map { |e| e.to_i.to_s(2).rjust(8, "0") }.join.count("1").to_s
  end

  def subnet_id(network)
    "subnet-#{network.id}"
  end

  def subnet_name(network)
    "subnet-#{network.name}"
  end

  def port_id(nic_data)
    "#{nic_data[:vm].ems_ref}#NIC##{nic_data[:NetworkConnectionIndex]}"
  end

  def port_name(nic_data)
    "#{nic_data[:vm].name}#NIC##{nic_data[:NetworkConnectionIndex]}"
  end

  def floating_ip_id(nic_data)
    "floating_ip-#{port_id(nic_data)}"
  end

  def cloud_network_vdc_type
    "ManageIQ::Providers::Vmware::NetworkManager::CloudNetwork::OrgVdcNet"
  end

  def cloud_network_vapp_type
    "ManageIQ::Providers::Vmware::NetworkManager::CloudNetwork::VappNet"
  end
end
