class ManageIQ::Providers::Vmware::Inventory::Parser::NetworkManager < ManageIQ::Providers::Vmware::Inventory::Parser
  def parse
    networks
    network_subnets
    network_routers
    network_ports
    floating_ips
  end
end
