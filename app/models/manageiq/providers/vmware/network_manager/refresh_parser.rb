module ManageIQ::Providers
  class Vmware::NetworkManager::RefreshParser
    include ManageIQ::Providers::Vmware::RefreshHelperMethods
    VappNetwork = Struct.new(:id, :name, :type, :is_shared, :gateway, :dns1, :dns2, :netmask, :enabled, :dhcp_enabled)

    def initialize(ems, options = nil)
      @ems                  = ems
      @options              = options || {}
      @data                 = {}
      @data_index           = {}
      @inv                  = Hash.new { |h, k| h[k] = [] }
      @network_name_mapping = {}
    end

    def ems_inv_to_hashes
      $vcloud_log.info("#{log_header} Collecting data for EMS name: [#{@ems.name}] id: [#{@ems.id}]...")

      connect

      get_org
      get_vdc_networks
      get_vapp_networks
      get_network_ports

      $vcloud_log.info("#{log_header}...Complete")

      @data
    end

    private

    def connect
      @connection ||= @ems.connect
    end

    def get_org
      @org = @connection.organizations.first
    end

    def get_vdc_networks
      @inv[:vdc_networks] = @org.networks || []
      @inv[:vdc_networks_idx] = @inv[:vdc_networks].index_by(&:id)

      process_collection(@inv[:vdc_networks], :cloud_networks) { |n| parse_network(n) }
      process_collection(@inv[:vdc_networks], :cloud_subnets, false) { |n| parse_network_subnet(n) }

      $vcloud_log.info("#{log_header} Fetched #{@inv[:vdc_networks].count} VDC networks")
    end

    def get_vapp_networks
      @inv[:vapp_networks] = []
      @inv[:routers] = []

      @ems.orchestration_stacks.each do |stack|
        fetch_network_configurations_for_vapp(stack.ems_ref).map do |net_conf|
          # 'none' is special network placeholder that we must ignore
          next if net_conf[:networkName] == 'none'

          $vcloud_log.debug("#{log_header} processing net_conf for vapp #{stack.ems_ref}: #{net_conf}")
          network_id = network_id_from_links(net_conf)
          $vcloud_log.debug("#{log_header} calculated vApp network id: #{network_id}")
          if (vdc_net = corresponding_vdc_network(net_conf, @inv[:vdc_networks_idx]))
            $vcloud_log.debug("#{log_header} skipping VDC network duplicate")
            memorize_network_name_mapping(stack.ems_ref, vdc_net.name, vdc_net.id)
          else
            memorize_network_name_mapping(stack.ems_ref, net_conf[:networkName], network_id)
            @inv[:vapp_networks] << build_vapp_network(stack, network_id, net_conf)

            # routers connecting vApp networks to VDC networks
            if (parent_net = parent_vdc_network(net_conf, @inv[:vdc_networks_idx]))
              $vcloud_log.debug("#{log_header} connecting router to parent: #{parent_net}")
              @inv[:routers] << {
                :net_conf   => net_conf,
                :network_id => network_id,
                :parent_net => parent_net
              }
            end
          end
        end
      end

      process_collection(@inv[:vapp_networks], :cloud_networks) { |n| parse_network(n) }
      process_collection(@inv[:vapp_networks], :cloud_subnets, false) { |n| parse_network_subnet(n) }
      process_collection(@inv[:routers], :network_routers) { |r| parse_network_router(r) }

      $vcloud_log.info("#{log_header} Fetched #{@inv[:vapp_networks].count} vApp networks")
      $vcloud_log.info("#{log_header} Fetched #{@inv[:routers].count} network routers")
    end

    def get_network_ports
      @inv[:nics] = []
      @ems.vms.each do |vm|
        fetch_nic_configurations_for_vm(vm.ems_ref).each do |nic|
          next unless nic[:IsConnected]
          $vcloud_log.debug("#{log_header} processing NIC configuration for vm #{vm.ems_ref}: #{nic}")
          nic[:vm] = vm
          @inv[:nics] << nic
        end
      end

      process_collection(@inv[:nics], :network_ports) { |n| parse_network_port(n) }
      process_collection(@inv[:nics], :floating_ips) { |n| parse_floating_ip(n) }

      $vcloud_log.info("#{log_header} Fetched #{@inv[:nics].count} network ports")
      $vcloud_log.info("#{log_header} Fetched #{@data[:floating_ips].count} floating ips")
    end

    # Parsing

    def parse_network(network)
      uid = network.id
      network_type = network.type.include?("vcloud.orgNetwork") ?
          self.class.cloud_network_vdc_type : self.class.cloud_network_vapp_type

      new_result = {
        :name          => network.name,
        :ems_ref       => uid,
        :shared        => network.is_shared,
        :type          => network_type,
        :cloud_subnets => []
      }
      new_result[:cidr] = to_cidr(network.gateway, network.netmask)
      new_result[:enabled] = network.enabled if network.respond_to?(:enabled)

      return uid, new_result
    end

    def parse_network_subnet(network)
      uid = subnet_id(network)
      new_result = {
        :name            => subnet_name(network),
        :ems_ref         => uid,
        :gateway         => network.gateway,
        :dns_nameservers => [network.dns1, network.dns2].compact,
        :type            => self.class.cloud_subnet_type,
        :network_ports   => []
      }
      new_result[:cidr] = to_cidr(network.gateway, network.netmask)
      new_result[:dhcp_enabled] = network.dhcp_enabled if network.respond_to?(:dhcp_enabled)

      # assign myself to the network
      @data_index.fetch_path(:cloud_networks, network.id)[:cloud_subnets] << new_result

      return uid, new_result
    end

    def parse_network_router(router)
      parent_id  = router[:parent_net].id
      uid        = "#{router[:network_id]}---#{parent_id}"
      new_result = {
        :type          => self.class.network_router_type,
        :name          => "Router #{router[:parent_net].name} -> #{router.dig(:net_conf, :networkName)}",
        :ems_ref       => uid,
        :cloud_network => @data_index.fetch_path(:cloud_networks, parent_id),
        :cloud_subnets => []
      }

      # assign myself to the vapp network
      @data_index.store_path(:cloud_subnets, "subnet-#{router[:network_id]}", :network_router, new_result)

      return uid, new_result
    end

    def parse_network_port(nic_data)
      uid = port_id(nic_data)
      vm_uid = nic_data[:vm].id

      new_result = {
        :type        => self.class.network_port_type,
        :name        => port_name(nic_data),
        :ems_ref     => uid,
        :device_ref  => vm_uid,
        :device      => nic_data[:vm],
        :mac_address => nic_data.dig(:MACAddress)
      }

      network_id = read_network_name_mapping(nic_data[:vm].orchestration_stack.ems_ref, nic_data.dig(:network))
      network = @data_index.fetch_path(:cloud_networks, network_id)

      unless network.nil?
        subnet = network[:cloud_subnets].first
        cloud_subnet_network_port = {
          :address      => nic_data[:IpAddress],
          :cloud_subnet => subnet
        }
        new_result[:cloud_subnet_network_ports] = [cloud_subnet_network_port]
      end

      return uid, new_result
    end

    def parse_floating_ip(nic_data)
      floating_ip = nic_data[:ExternalIpAddress]
      return unless floating_ip

      uid = floating_ip_id(nic_data)
      network_id = read_network_name_mapping(nic_data[:vm].orchestration_stack.ems_ref, nic_data[:network])
      network = @data_index.fetch_path(:cloud_networks, network_id)

      new_result = {
        :type             => self.class.floating_ip_type,
        :ems_ref          => uid,
        :address          => floating_ip,
        :fixed_ip_address => floating_ip,
        :cloud_network    => network,
        :network_port     => @data_index.fetch_path(:network_ports, port_id(nic_data)),
        :vm               => nic_data[:vm]
      }

      return uid, new_result
    end

    # Utility

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

    def subnet_id(network)
      "subnet-#{network.id}"
    end

    def subnet_name(network)
      "subnet-#{network.name}"
    end

    def vapp_network_name(name, vapp)
      "#{name} (#{vapp.name})"
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
    def corresponding_vdc_network(net_conf, vdc_networks)
      if net_conf.dig(:networkName) == net_conf.dig(:Configuration, :ParentNetwork, :name)
        parent_vdc_network(net_conf, vdc_networks)
      end
    end

    def parent_vdc_network(net_conf, vdc_networks)
      vdc_networks[net_conf.dig(:Configuration, :ParentNetwork, :id)]
    end

    # Remember network id for given network name. Generally network names are not unique,
    # but inside vapp network specification they are. Therefore we must remember what network
    # id was listed for given network name in corresponding vapp in order to be able to later
    # hook VM to the appropriate network (VM only reports network name, without network ID...).
    def memorize_network_name_mapping(vapp_id, network_name, network_id)
      @network_name_mapping[vapp_id] ||= {}
      @network_name_mapping[vapp_id][network_name] = network_id
    end

    def read_network_name_mapping(vapp_id, network_name)
      @network_name_mapping.dig(vapp_id, network_name)
    end

    def to_cidr(address, netmask)
      return unless address.to_s =~ Resolv::IPv4::Regex && netmask.to_s =~ Resolv::IPv4::Regex
      address + '/' + netmask.to_s.split(".").map { |e| e.to_i.to_s(2).rjust(8, "0") }.join.count("1").to_s
    end

    def log_header
      location = caller_locations(1, 1)
      location = location.first if location.kind_of?(Array)
      "MIQ(#{self.class.name}.#{location.base_label})"
    end

    # Additional API calls

    # Fetch vapp network configuration via vCD API. This call is implemented in Fog, but it's not
    # managed, therefore we must handle errors by ourselves.
    def fetch_network_configurations_for_vapp(vapp_id)
      begin
        # fog-vcloud-director now uses a more user-friendly parser that yields vApp instance. However, vapp networking
        # is not parsed there yet so we need to fallback to basic ToHashDocument parser that only converts XML to hash.
        # TODO(miha-plesko): update default parser to do the XML parsing for us.
        data = @connection.get_vapp(vapp_id, :parser => Fog::ToHashDocument).body
      rescue Fog::VcloudDirector::Errors::ServiceError => e
        $vcloud_log.error("#{log_header} could not fetch network configuration for vapp #{vapp_id}: #{e}")
        return []
      end
      Array.wrap(data.dig(:NetworkConfigSection, :NetworkConfig))
    end

    def fetch_nic_configurations_for_vm(vm_id)
      begin
        data = @connection.get_network_connection_system_section_vapp(vm_id).body
      rescue Fog::VcloudDirector::Errors::ServiceError => e
        $vcloud_log.error("#{log_header} could not fetch NIC configuration for vm #{vm_id}: #{e}")
        return []
      end
      Array.wrap(data[:NetworkConnection])
    end

    class << self
      def cloud_network_vdc_type
        "ManageIQ::Providers::Vmware::NetworkManager::CloudNetwork::OrgVdcNet"
      end

      def cloud_network_vapp_type
        "ManageIQ::Providers::Vmware::NetworkManager::CloudNetwork::VappNet"
      end

      def cloud_subnet_type
        "ManageIQ::Providers::Vmware::NetworkManager::CloudSubnet"
      end

      def network_router_type
        "ManageIQ::Providers::Vmware::NetworkManager::NetworkRouter"
      end

      def network_port_type
        "ManageIQ::Providers::Vmware::NetworkManager::NetworkPort"
      end

      def floating_ip_type
        "ManageIQ::Providers::Vmware::NetworkManager::FloatingIp"
      end
    end
  end
end
