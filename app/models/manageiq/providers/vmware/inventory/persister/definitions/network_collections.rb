module ManageIQ::Providers::Vmware::Inventory::Persister::Definitions::NetworkCollections
  extend ActiveSupport::Concern

  def initialize_network_inventory_collections
    %i(cloud_networks
       cloud_subnets
       security_groups
       load_balancers
       load_balancer_pools
       load_balancer_pool_members
       load_balancer_pool_member_pools
       load_balancer_listeners
       load_balancer_listener_pools
       load_balancer_health_checks
       load_balancer_health_check_members).each do |name|

      add_collection(network, name) do |builder|
        builder.add_properties(:parent => manager.network_manager) if targeted?
      end
    end
  end
end
