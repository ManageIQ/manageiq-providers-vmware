class ManageIQ::Providers::Vmware::Inventory::Persister::NetworkManager < ManageIQ::Providers::Vmware::Inventory::Persister
  def initialize_inventory_collections
    initialize_cloud_inventory_collections
    initialize_network_inventory_collections
  end

  def initialize_cloud_inventory_collections
    %i[availability_zones orchestration_stacks vms].each do |name|
      add_cloud_collection(name) { |builder| builder.add_properties(:strategy => :local_db_cache_all) }
    end
  end

  def initialize_network_inventory_collections
    %i[cloud_networks
       cloud_subnets
       cloud_subnet_network_ports
       floating_ips
       network_routers
       network_ports
       security_groups
       load_balancers
       load_balancer_pools
       load_balancer_pool_members
       load_balancer_pool_member_pools
       load_balancer_listeners
       load_balancer_listener_pools
       load_balancer_health_checks
       load_balancer_health_check_members].each do |name|

      add_network_collection(name)
    end
  end
end
