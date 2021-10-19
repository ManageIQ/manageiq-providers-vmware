class ManageIQ::Providers::Vmware::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :CloudManager
  require_nested :ContainerManager
  require_nested :NetworkManager

  def initialize_inventory_collections
    initialize_cloud_inventory_collections
    initialize_network_inventory_collections
  end

  def initialize_cloud_inventory_collections
    add_cloud_collection(:availability_zones)
    add_cloud_collection(:disks)
    add_cloud_collection(:hardwares)
    add_cloud_collection(:miq_templates)
    add_cloud_collection(:operating_systems)
    add_cloud_collection(:orchestration_stacks)
    add_cloud_collection(:snapshots)
    add_cloud_collection(:orchestration_templates) do |builder|
      builder.add_default_values(:ext_management_system => cloud_manager)
    end
    add_cloud_collection(:vms)
  end

  def initialize_network_inventory_collections
    %i[
      cloud_networks
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
      load_balancer_health_check_members
    ].each do |name|
      add_network_collection(name)
    end
  end
end
