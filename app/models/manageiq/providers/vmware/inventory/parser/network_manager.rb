class ManageIQ::Providers::Vmware::Inventory::Parser::NetworkManager < ManageIQ::Providers::Vmware::Inventory::Parser
  def parse
    network_ports
    floating_ips
  end
end
