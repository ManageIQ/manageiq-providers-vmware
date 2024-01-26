class ManageIQ::Providers::Vmware::Inventory::Parser < ManageIQ::Providers::Inventory::Parser
  def parse
    vdcs
    vapps
    vms
    vapp_templates
    images
    networks
    network_subnets
    network_routers
    network_ports
    floating_ips
  end

  private

  def vdcs
    collector.vdcs.each do |vdc|
      persister.availability_zones.find_or_build(vdc.id).assign_attributes(
        :name => vdc.name
      )
    end
  end

  def vapps
    collector.vapps.each do |vapp|
      persister.orchestration_stacks.find_or_build(vapp.id).assign_attributes(
        :name        => vapp.name,
        :description => vapp.name,
        :status      => vapp.human_status,
      )
    end
  end

  def vms
    collector.vms.each do |vm|
      parsed_vm = persister.vms.find_or_build(vm[:vm].id).assign_attributes(
        :uid_ems                => vm[:vm].id,
        :name                   => vm[:vm].name,
        :hostname               => vm[:hostname],
        :location               => vm[:vm].id,
        :vendor                 => 'vmware',
        :connection_state       => "connected",
        :raw_power_state        => vm[:vm].status,
        :orchestration_stack    => persister.orchestration_stacks.lazy_find(vm[:vm].vapp_id),
        :snapshots              => [],
        :cpu_hot_add_enabled    => vm[:vm].cpu_hot_add,
        :memory_hot_add_enabled => vm[:vm].memory_hot_add,
      )

      if (resp = vm[:snapshot]) && (snapshot = resp.fetch_path(:body, :Snapshot))
        uid = "#{vm[:vm].id}_#{snapshot[:created]}"
        persister.snapshots.find_or_build_by(:vm_or_template => parsed_vm, :uid => uid).assign_attributes(
          :name        => "#{vm[:vm].name} (snapshot)",
          :uid         => uid,
          :ems_ref     => uid,
          :parent_uid  => vm[:vm].id,
          :create_time => Time.zone.parse(snapshot[:created]),
          :total_size  => snapshot[:size]
        )
      end

      hardware = persister.hardwares.find_or_build(parsed_vm).assign_attributes(
        :guest_os             => vm[:vm].operating_system,
        :guest_os_full_name   => vm[:vm].operating_system,
        :bitness              => vm[:vm].operating_system =~ /64-bit/ ? 64 : 32,
        :cpu_sockets          => vm[:vm].cpu / vm[:vm].cores_per_socket,
        :cpu_cores_per_socket => vm[:vm].cores_per_socket,
        :cpu_total_cores      => vm[:vm].cpu,
        :memory_mb            => vm[:vm].memory,
        :disk_capacity        => vm[:vm].hard_disks.inject(0) { |sum, x| sum + x.values[0] } * 1.megabyte,
      )

      vm[:vm].disks.all.select { |d| hdd? d.bus_type }.each_with_index do |disk, i|
        device_name = "Disk #{i}"
        persister.disks.find_or_build_by(:hardware => hardware, :device_name => device_name).assign_attributes(
          :device_name     => device_name,
          :device_type     => "disk",
          :disk_type       => controller_description(disk.bus_sub_type).sub(' controller', ''),
          :controller_type => controller_description(disk.bus_sub_type),
          :size            => disk.capacity * 1.megabyte,
          :location        => "#{vm[:vm].id}/#{disk.address}/#{disk.address_on_parent}/#{disk.id}",
          :filename        => "Disk #{i}"
        )
      end

      persister.operating_systems.find_or_build(parsed_vm).assign_attributes(
        :product_name => vm[:vm].operating_system,
      )
    end
  end

  def vapp_templates
    collector.vapp_templates.each do |vapp_template|
      persister.orchestration_templates.find_or_build(vapp_template[:vapp_template].id).assign_attributes(
        :name        => vapp_template[:vapp_template].name,
        :description => vapp_template[:vapp_template].description,
        :orderable   => true,
        :content     => "<!-- #{vapp_template[:vapp_template].id} -->\n#{vapp_template[:content]}",
      )
    end
  end

  def images
    collector.images.each do |image|
      persister.miq_templates.find_or_build(image[:image].id).assign_attributes(
        :uid_ems            => image[:image].id,
        :name               => image[:image].name,
        :location           => image[:image].id,
        :vendor             => 'vmware',
        :connection_state   => "connected",
        :raw_power_state    => 'never',
        :publicly_available => image[:is_published]
      )
    end
  end

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

    network_id = collector.read_network_name_mapping(nic_data[:vm].vapp_id, nic_data.dig(:network))
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
    network_id = collector.read_network_name_mapping(nic_data[:vm].vapp_id, nic_data[:network])

    new_result = {
      :type             => "ManageIQ::Providers::Vmware::NetworkManager::FloatingIp",
      :ems_ref          => uid,
      :address          => floating_ip,
      :fixed_ip_address => floating_ip,
      :cloud_network    => persister.cloud_networks.lazy_find(network_id),
      :network_port     => persister.network_ports.lazy_find(port_id(nic_data)),
      :vm               => persister.vms.lazy_find(nic_data[:vm].id)
    }

    persister.floating_ips.build(new_result)
  end

  def subnet_id(network)
    "subnet-#{network.id}"
  end

  def port_id(nic_data)
    "#{nic_data[:vm].id}#NIC##{nic_data[:NetworkConnectionIndex]}"
  end

  def floating_ip_id(nic_data)
    "floating_ip-#{port_id(nic_data)}"
  end

  def to_cidr(address, netmask)
    return unless address.to_s =~ Resolv::IPv4::Regex && netmask.to_s =~ Resolv::IPv4::Regex
    address + '/' + netmask.to_s.split(".").map { |e| e.to_i.to_s(2).rjust(8, "0") }.join.count("1").to_s
  end

  # See https://pubs.vmware.com/vcd-80/index.jsp#com.vmware.vcloud.api.sp.doc_90/GUID-E1BA999D-87FA-4E2C-B638-24A211AB8160.html
  def controller_description(bus_subtype)
    case bus_subtype
    when 'buslogic'
      'BusLogic Parallel SCSI controller'
    when 'lsilogic'
      'LSI Logic Parallel SCSI controller'
    when 'lsilogicsas'
      'LSI Logic SAS SCSI controller'
    when 'VirtualSCSI'
      'Paravirtual SCSI controller'
    when 'vmware.sata.ahci'
      'SATA controller'
    else
      'IDE controller'
    end
  end

  # See https://pubs.vmware.com/vcd-80/index.jsp#com.vmware.vcloud.api.sp.doc_90/GUID-E1BA999D-87FA-4E2C-B638-24A211AB8160.html
  def hdd?(bus_type)
    [5, 6, 20].include?(bus_type)
  end
end
