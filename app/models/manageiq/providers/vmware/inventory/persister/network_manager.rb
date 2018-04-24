class ManageIQ::Providers::Vmware::Inventory::Persister::NetworkManager < ManageIQ::Providers::Vmware::Inventory::Persister
  def initialize_inventory_collections
    add_inventory_collections(
      network,
      %i(cloud_networks cloud_subnets network_routers network_ports floating_ips cloud_subnet_network_ports)
    )
  end
end
