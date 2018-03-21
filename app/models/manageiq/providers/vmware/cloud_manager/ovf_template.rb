class ManageIQ::Providers::Vmware::CloudManager::OvfTemplate
  attr_accessor :vms, :vapp_networks
  class OvfParseError < StandardError; end
  OvfVM          = Struct.new(:id, :name, :num_cores, :cores_per_socket, :memory_mb, :hostname, :disks, :nics, :guest_customization)
  OvfDisk        = Struct.new(:id, :address, :capacity_mb)
  OvfNIC         = Struct.new(:idx, :network, :mode, :ip_address)
  OvfVappNetwork = Struct.new(:name, :mode, :subnets)
  OvfSubnet      = Struct.new(:gateway, :netmask, :dns1, :dns2)

  RESERVED_LINE_REGEX = /<!-- (vappTemplate-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}) -->/

  def initialize(ovf_string)
    @vms           = []
    @vapp_networks = []
    parse(ovf_string)
  end

  def vapp_network_names
    @vapp_networks.map(&:name)
  end

  def vm_id_from_idx(vm_idx)
    @vms[vm_idx].id if @vms[vm_idx]
  end

  def disk_id_from_idx(vm_idx, disk_idx)
    return unless @vms[vm_idx]
    return unless @vms[vm_idx].disks
    @vms[vm_idx].disks[disk_idx].id if @vms[vm_idx].disks[disk_idx]
  end

  def vapp_net_name_from_idx(vapp_net_idx)
    @vapp_networks[vapp_net_idx].name if @vapp_networks[vapp_net_idx]
  end

  # Extract ems_ref of the template from the very first line of the XML. This line is supposed to
  # be put there by refresh parser.
  def self.template_ems_ref(ovf_string)
    return unless ovf_string
    if (reserved_line = ovf_string.lines.first) && (param_match = reserved_line.match(RESERVED_LINE_REGEX))
      param_match.captures.first
    end
  end

  private

  def parse(ovf_string)
    ovf = MiqXml.load(ovf_string)
    raise OvfParseError('OVF XML not valid xml') unless ovf
    parse_vms(ovf.root)
    parse_vapp_networks(ovf.root)
  end

  def parse_vms(ovf)
    ovf.each_element(vapp_xpaths(:vms)) do |el|
      vm                     = OvfVM.new
      vm.id                  = text(el, vm_xpaths(:id))
      vm.hostname            = text(el, vm_xpaths(:hostname))
      vm.name                = text(el, vm_xpaths(:name), :default => vm.hostname)
      vm.num_cores           = int(el, vm_xpaths(:num_cores))
      vm.cores_per_socket    = int(el, vm_xpaths(:cores_per_socket), :default => vm.num_cores)
      vm.memory_mb           = int(el, vm_xpaths(:memory_mb), :default => 1024)
      vm.guest_customization = bool(el, vm_xpaths(:guest_customization))

      # Disks.
      vm.disks = []
      el.each_element(vm_xpaths(:disks)) do |d|
        disk             = OvfDisk.new
        disk.id          = text(d, disk_xpaths(:id))
        disk.address     = text(d, disk_xpaths(:address))
        disk.capacity_mb = int(d, disk_xpaths(:capacity), :default => 0) / 2**20 # B -> MB
        vm.disks << disk
      end

      # NICs.
      vm.nics = []
      el.each_element(vm_xpaths(:nics)) do |n|
        nic            = OvfNIC.new
        nic.idx        = text(n, nic_xpaths(:idx))
        nic.network    = text_attr(n, nic_xpaths(:network_attr))
        nic.mode       = text(n, nic_xpaths(:mode))
        nic.ip_address = text(n, nic_xpaths(:ip), :default => nil)

        nic.network = nil if nic.network == 'none'
        nic.mode    = 'DHCP' if nic.mode == 'NONE'
        vm.nics << nic
      end

      @vms << vm
    end
  end

  def parse_vapp_networks(ovf)
    ovf.each_element(vapp_xpaths(:vapp_networks)) do |el|
      vapp_net      = OvfVappNetwork.new
      vapp_net.name = text_attr(el, vapp_net_xpaths(:name_attr))
      vapp_net.mode = text(el, vapp_net_xpaths(:mode), :default => 'isolated')

      vapp_net.subnets = []
      el.find_match(vapp_net_xpaths(:ip_scopes)).each do |ip_scope|
        subnet         = OvfSubnet.new
        subnet.gateway = text(ip_scope, ip_scope_xpaths(:gateway))
        subnet.netmask = text(ip_scope, ip_scope_xpaths(:netmask))
        subnet.dns1    = text(ip_scope, ip_scope_xpaths(:dns1))
        subnet.dns2    = text(ip_scope, ip_scope_xpaths(:dns2))
        vapp_net.subnets << subnet
      end

      @vapp_networks << vapp_net
    end
  end

  def bool(el, xpath, default: false)
    (match = el.elements[xpath]) ? match.text.downcase == 'true' : default
  end

  def text(el, xpath, default: '')
    (match = el.elements[xpath]) ? match.text : default
  end

  def text_attr(el, xpath, default: '')
    (match = el.elements[xpath]) ? match.value : default
  end

  def int(el, xpath, default: 1)
    (match = el.elements[xpath]) ? Integer(match.text) : default
  end

  # Example: https://pubs.vmware.com/vcd-80/index.jsp?topic=%2Fcom.vmware.vcloud.api.reference.doc_90%2Fdoc%2Flanding-user_operations.html
  # ResourceType definitions: https://blogs.vmware.com/vapp/2009/11/virtual-hardware-in-ovf-part-1.html
  def vm_xpaths(key)
    case key
    when :id
      './vcloud:GuestCustomizationSection/vcloud:VirtualMachineId'
    when :name
      './ovf:Name'
    when :num_cores
      "./ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType = '3']/rasd:VirtualQuantity"
    when :cores_per_socket
      "./ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType = '3']/vmw:CoresPerSocket"
    when :memory_mb
      "./ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType = '4']/rasd:VirtualQuantity"
    when :disks
      "./ovf:VirtualHardwareSection/ovf:Item[rasd:ResourceType = '17']"
    when :hostname
      './vcloud:GuestCustomizationSection/vcloud:ComputerName'
    when :nics
      './/vcloud:NetworkConnection'
    when :guest_customization
      './vcloud:GuestCustomizationSection/vcloud:Enabled'
    else
      ''
    end
  end

  def vapp_xpaths(key)
    case key
    when :vapp_networks
      "//vcloud:NetworkConfig[not(@networkName = 'none')]"
    when :vapp_network_names_attr
      "//vcloud:NetworkConfig[not(@networkName = 'none')]/@networkName"
    when :vms
      "//ovf:VirtualSystem"
    else
      ''
    end
  end

  def disk_xpaths(key)
    case key
    when :id
      './rasd:InstanceID'
    when :address
      './rasd:AddressOnParent'
    when :capacity
      './rasd:VirtualQuantity'
    else
      ''
    end
  end

  def nic_xpaths(key)
    case key
    when :idx
      './vcloud:NetworkConnectionIndex'
    when :network_attr
      '@network'
    when :mode
      './vcloud:IpAddressAllocationMode'
    when :ip
      './vcloud:IpAddress'
    else
      ''
    end
  end

  def vapp_net_xpaths(key)
    case key
    when :name_attr
      '@networkName'
    when :mode
      './vcloud:Configuration/vcloud:FenceMode'
    when :ip_scopes
      './vcloud:Configuration/vcloud:IpScopes/vcloud:IpScope'
    else
      ''
    end
  end

  def ip_scope_xpaths(key)
    case key
    when :gateway
      './vcloud:Gateway'
    when :netmask
      './vcloud:Netmask'
    when :dns1
      './vcloud:Dns1'
    when :dns2
      './vcloud:Dns2'
    else
      ''
    end
  end
end
