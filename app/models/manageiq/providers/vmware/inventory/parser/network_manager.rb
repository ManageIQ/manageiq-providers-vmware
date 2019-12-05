class ManageIQ::Providers::Vmware::Inventory::Parser::NetworkManager < ManageIQ::Providers::Vmware::Inventory::Parser
  def parse
    networks
    network_subnets
    network_routers
    network_ports
    floating_ips
  end

  private

  def networks
    collector.vdc_networks.each { |n| parse_network(n) }
    collector.vapp_networks.each { |n| parse_network(n) }
  end

  def parse_network(network)
    uid = network.id
    network_type = if network.type.include?("vcloud.orgNetwork")
      "ManageIQ::Providers::Vmware::NetworkManager::CloudNetwork::OrgVdcNet"
    else
      "ManageIQ::Providers::Vmware::NetworkManager::CloudNetwork::VappNet"
    end

    new_result = {
      :name                   => network.name,
      :ems_ref                => uid,
      :shared                 => network.is_shared,
      :type                   => network_type,
      :orchestration_stack_id => network.try(:orchestration_stack).try(:id)
    }
    new_result[:cidr] = to_cidr(network.gateway, network.netmask)
    new_result[:enabled] = network.enabled if network.respond_to?(:enabled)

    persister.cloud_networks.build(new_result)
  end

  def network_subnets
    collector.vdc_networks.each { |n| parse_network_subnet(n) }
    collector.vapp_networks.each { |n| parse_network_subnet(n) }
  end

  def parse_network_subnet(network)
    uid = subnet_id(network)
    router     = collector.routers.detect { |r| r[:network_id] == network.id }
    network_router = persister.network_routers.lazy_find("#{router[:network_id]}---#{router[:parent_net].id}") if router

    new_result = {
      :name            => network.name,
      :ems_ref         => uid,
      :gateway         => network.gateway,
      :dns_nameservers => [network.dns1, network.dns2].compact,
      :type            => "ManageIQ::Providers::Vmware::NetworkManager::CloudSubnet",
      :cloud_network   => persister.cloud_networks.lazy_find(network.id),
      :network_router  => network_router
    }
    new_result[:cidr] = to_cidr(network.gateway, network.netmask)
    new_result[:dhcp_enabled] = network.dhcp_enabled if network.respond_to?(:dhcp_enabled)

    persister.cloud_subnets.build(new_result)
  end

  def network_routers
    collector.routers.each { |r| parse_network_router(r) }
  end

  def parse_network_router(router)
    parent_id  = router[:parent_net].id
    uid        = "#{router[:network_id]}---#{parent_id}"
    new_result = {
      :type          => "ManageIQ::Providers::Vmware::NetworkManager::NetworkRouter",
      :name          => "Router #{router[:parent_net].name} -> #{router.dig(:net_conf, :networkName)}",
      :ems_ref       => uid,
      :cloud_network => persister.cloud_networks.lazy_find(parent_id)
    }
    router = persister.network_routers.build(new_result)

    network_subnet = persister.cloud_subnets.find("subnet-#{router[:network_id]}")
    network_subnet.network_router = router unless network_subnet.nil?
  end

  def network_ports
    collector.network_ports.each { |n| parse_network_port(n) }
  end

  def parse_network_port(nic_data)
    uid = port_id(nic_data)
    vm_uid = nic_data[:vm].id

    new_result = {
      :type        => "ManageIQ::Providers::Vmware::NetworkManager::NetworkPort",
      :name        => "NIC##{nic_data[:NetworkConnectionIndex]}",
      :ems_ref     => uid,
      :device_ref  => vm_uid,
      :device_type => "VmOrTemplate",
      :device_id   => vm_uid,
      :mac_address => nic_data.dig(:MACAddress),
      :source      => "refresh"
    }

    network_port = persister.network_ports.build(new_result)

    network_id = collector.read_network_name_mapping(nic_data[:vm].orchestration_stack.ems_ref, nic_data.dig(:network))
    unless network_id.nil?
      persister.cloud_subnet_network_ports.build(
        :address      => nic_data[:IpAddress],
        :cloud_subnet => persister.cloud_subnets.lazy_find("subnet-#{network_id}"),
        :network_port => network_port
      )
    end
  end

  def floating_ips
    collector.network_ports.each { |n| parse_floating_ip(n) }
  end

  def parse_floating_ip(nic_data)
    floating_ip = nic_data[:ExternalIpAddress]
    return unless floating_ip

    uid = floating_ip_id(nic_data)
    network_id = collector.read_network_name_mapping(nic_data[:vm].orchestration_stack.ems_ref, nic_data[:network])
    #network = @data_index.fetch_path(:cloud_networks, network_id)

    new_result = {
      :type             => "ManageIQ::Providers::Vmware::NetworkManager::FloatingIp",
      :ems_ref          => uid,
      :address          => floating_ip,
      :fixed_ip_address => floating_ip,
      :cloud_network    => persister.cloud_networks.lazy_find(network_id),
      :network_port     => persister.network_ports.lazy_find(port_id(nic_data)),
      :vm               => persister.vms.lazy_find(nic_data[:vm].ems_ref)
    }

    persister.floating_ips.build(new_result)
  end

  def subnet_id(network)
    "subnet-#{network.id}"
  end

  def port_id(nic_data)
    "#{nic_data[:vm].ems_ref}#NIC##{nic_data[:NetworkConnectionIndex]}"
  end

  def floating_ip_id(nic_data)
    "floating_ip-#{port_id(nic_data)}"
  end

  def to_cidr(address, netmask)
    return unless address.to_s =~ Resolv::IPv4::Regex && netmask.to_s =~ Resolv::IPv4::Regex
    address + '/' + netmask.to_s.split(".").map { |e| e.to_i.to_s(2).rjust(8, "0") }.join.count("1").to_s
  end
end
