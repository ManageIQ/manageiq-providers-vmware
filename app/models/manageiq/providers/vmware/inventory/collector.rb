class ManageIQ::Providers::Vmware::Inventory::Collector < ManageIQ::Providers::Inventory::Collector
  require_nested :CloudManager
  require_nested :NetworkManager

  def initialize(_manager, _target)
    super

    initialize_inventory_sources
  end

  def initialize_inventory_sources
    @orgs                 = []
    @vdcs                 = []
    @vapps                = []
    @vms                  = []
    @vapp_templates       = []
    @images               = []
    @vdc_networks         = []
    @vdc_networks_idx     = {}
    @vapp_networks        = []
    @network_ports        = []
    @routers              = []
    @network_name_mapping = {}
  end

  def connection
    @connection ||= manager.connect
  end

  def public_images?
    options.try(:get_public_images)
  end

  VAPP_TEMPLATE_STATUS_READY = "8".freeze
  VappNetwork = Struct.new(:id, :name, :type, :is_shared, :gateway, :dns1, :dns2, :netmask, :enabled, :dhcp_enabled, :orchestration_stack)

  def orgs
    return @orgs if @orgs.any?

    @orgs = connection.organizations
  end

  def org
    orgs.first
  end

  def vdcs
    return @vdcs if @vdcs.any?

    @vdcs = orgs.each_with_object([]) do |org, res|
      res.concat(org.vdcs.all)
    end
  end

  def vapps
    return @vapps if @vapps.any?

    @vapps = vdcs.each_with_object([]) do |vdc, res|
      res.concat(vdc.vapps.all)
    end
  end

  def vms
    return @vms if @vms.any?

    @vms = vapps.each_with_object([]) do |vapp, res|
      # Remove this each loop, once fog api will be updated to send hostname and snapshot together with vms
      vapp.vms.each do |vm|
        res << {
          :vm       => vm,
          :hostname => vm.customization.try(:computer_name),
          :snapshot => connection.get_snapshot_section(vm.id).try(:data)
        }
      end
    end
  end

  def vapp_templates
    return @vapp_templates if @vapp_templates.any?

    @vapp_templates = orgs.each_with_object([]) do |org, res|
      org.catalogs.each do |catalog|
        next if !public_images? && catalog.is_published

        catalog.catalog_items.each do |item|
          # Skip all Catalog Items which are not vApp Templates (e.g. Media & Other)
          next unless item.vapp_template_id.starts_with?('vappTemplate-')
          next unless (t = item.vapp_template) && t.status == VAPP_TEMPLATE_STATUS_READY

          res << {
            :vapp_template => t,
            :is_published  => catalog.is_published,
            :content       => connection.get_vapp_template_ovf_descriptor(t.id).try(:body)
          }
        end
      end
    end
  end

  def images
    return @images if @images.any?

    @images = vapp_templates.each_with_object([]) do |template_obj, res|
      res.concat(template_obj[:vapp_template].vms.map { |image| {:image => image, :is_published => template_obj[:is_published]} })
    end
  end

  def vdc_networks
    return @vdc_networks if @vdc_networks.any?

    @vdc_networks = org.networks || []
    @vdc_networks_idx = @vdc_networks.index_by(&:id)

    @vdc_networks
  end

  def routers
    return @routers if @routers.any?

    # Routers can't be independently collected, we have to get vapp_networks first
    vapp_networks

    @routers
  end

  def vapp_networks
    return @vapp_networks if @vapp_networks.any?

    @vapp_networks = manager.orchestration_stacks.each_with_object([]) do |stack, res|
      fetch_network_configurations_for_vapp(stack.ems_ref).map do |net_conf|
        # 'none' is special network placeholder that we must ignore
        next if net_conf[:networkName] == 'none'

        network_id = network_id_from_links(net_conf)
        if (vdc_net = corresponding_vdc_network(net_conf, @vdc_networks_idx))
          memorize_network_name_mapping(stack.ems_ref, vdc_net.name, vdc_net.id)
        else
          memorize_network_name_mapping(stack.ems_ref, net_conf[:networkName], network_id)
          res << build_vapp_network(stack, network_id, net_conf)

          # routers connecting vApp networks to VDC networks
          if (parent_net = parent_vdc_network(net_conf, @vdc_networks_idx))
            @routers << {
              :net_conf   => net_conf,
              :network_id => network_id,
              :parent_net => parent_net
            }
          end
        end
      end
    end
  end

  def network_ports
    return @network_ports if @network_ports.any?

    @network_ports = manager.vms.each_with_object([]) do |vm, res|
      fetch_nic_configurations_for_vm(vm.ems_ref).each do |nic|
        next unless nic[:IsConnected]

        nic[:vm] = vm
        res << nic
      end
    end
  end

  def read_network_name_mapping(vapp_id, network_name)
    @network_name_mapping.dig(vapp_id, network_name)
  end

  private

  # Utility

  def build_vapp_network(vapp, network_id, net_conf)
    n = VappNetwork.new(network_id)
    n.name = vapp_network_name(net_conf[:networkName], vapp)
    n.orchestration_stack = vapp
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

  def vapp_network_name(name, vapp)
    "#{name} (#{vapp.name})"
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

  # Fetch vapp network configuration via vCD API. This call is implemented in Fog, but it's not
  # managed, therefore we must handle errors by ourselves.
  def fetch_network_configurations_for_vapp(vapp_id)
    require 'fog/vcloud_director'
    begin
      # fog-vcloud-director now uses a more user-friendly parser that yields vApp instance. However, vapp networking
      # is not parsed there yet so we need to fallback to basic ToHashDocument parser that only converts XML to hash.
      # TODO(miha-plesko): update default parser to do the XML parsing for us.
      data = connection.get_vapp(vapp_id, :parser => Fog::ToHashDocument).body
    rescue Fog::VcloudDirector::Errors::ServiceError => e
      $vcloud_log.error("#{log_header} could not fetch network configuration for vapp #{vapp_id}: #{e}")
      return []
    end
    Array.wrap(data.dig(:NetworkConfigSection, :NetworkConfig))
  end

  def fetch_nic_configurations_for_vm(vm_id)
    require 'fog/vcloud_director'
    begin
      data = connection.get_network_connection_system_section_vapp(vm_id).body
    rescue Fog::VcloudDirector::Errors::ServiceError => e
      $vcloud_log.error("#{log_header} could not fetch NIC configuration for vm #{vm_id}: #{e}")
      return []
    end
    Array.wrap(data[:NetworkConnection])
  end
end
