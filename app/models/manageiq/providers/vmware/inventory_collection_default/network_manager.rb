class ManageIQ::Providers::Vmware::InventoryCollectionDefault::NetworkManager < ManagerRefresh::InventoryCollectionDefault::NetworkManager
  class << self
    def cloud_networks(extra_attributes = {})
      attributes = {
        :inventory_object_attributes => %i(
          type
          name
          ems_ref
          shared
          cidr
          enabled
        )
      }

      super(attributes.merge!(extra_attributes))
    end

    def cloud_subnets(extra_attributes = {})
      attributes = {
        :model_class                 => ::ManageIQ::Providers::Vmware::NetworkManager::CloudSubnet,
        :association                 => :cloud_subnets,
        :inventory_object_attributes => %i(
          type
          name
          ems_ref
          gateway
          dns_nameservers
          cidr
          dhcp_enabled
          cloud_network
          network_router
        )
      }

      super(attributes.merge!(extra_attributes))
    end

    def network_routers(extra_attributes = {})
      attributes = {
        :model_class                 => ::ManageIQ::Providers::Vmware::NetworkManager::NetworkRouter,
        :association                 => :network_routers,
        :inventory_object_attributes => %i(
          type
          name
          ems_ref
          cloud_network
        ),
        :builder_params              => {
          :type   => 'ManageIQ::Providers::Vmware::NetworkManager::NetworkRouter',
          :ems_id => ->(persister) { persister.manager.id },
        }
      }

      attributes.merge!(extra_attributes)
    end

    def network_ports(extra_attributes = {})
      attributes = {
        :model_class                 => ::ManageIQ::Providers::Vmware::NetworkManager::NetworkPort,
        :association                 => :network_ports,
        :inventory_object_attributes => %i(
          type
          name
          ems_ref
          device_ref
          device
          mac_address
          cloud_subnet_network_ports
        )
      }

      super(attributes.merge!(extra_attributes))
    end

    def floating_ips(extra_attributes = {})
      attributes = {
        :model_class                 => ::ManageIQ::Providers::Vmware::NetworkManager::FloatingIp,
        :association                 => :floating_ips,
        :inventory_object_attributes => %i(
          type
          ems_ref
          address
          fixed_ip_address
          cloud_network
          network_port
          vm
        )
      }

      super(attributes.merge!(extra_attributes))
    end

    def cloud_subnet_network_ports(extra_attributes = {})
      attributes = {
        :model_class                 => CloudSubnetNetworkPort,
        :manager_ref                 => %i(address cloud_subnet network_port),
        :association                 => :cloud_subnet_network_ports,
        :inventory_object_attributes => %i(
          network_port
          address
          cloud_subnet
        )
      }

      super(attributes.merge!(extra_attributes))
    end
  end
end
