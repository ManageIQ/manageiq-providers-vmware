class ManageIQ::Providers::Vmware::InventoryCollectionDefault::CloudManager < ManagerRefresh::InventoryCollectionDefault::CloudManager
  class << self
    def availability_zones(extra_attributes = {})
      attributes = {
        :model_class                 => ::ManageIQ::Providers::Vmware::CloudManager::AvailabilityZone,
        :inventory_object_attributes => %i(
          type
          ems_id
          ems_ref
          name
        )
      }

      super(attributes.merge!(extra_attributes))
    end

    def orchestration_stacks(extra_attributes = {})
      attributes = {
        :model_class                 => ::ManageIQ::Providers::Vmware::CloudManager::OrchestrationStack,
        :inventory_object_attributes => %i(
          type
          ems_id
          ems_ref
          name
          description
          status
        )
      }

      super(attributes.merge!(extra_attributes))
    end

    def vms(extra_attributes = {})
      attributes = {
        :model_class                 => ::ManageIQ::Providers::Vmware::CloudManager::Vm,
        :inventory_object_attributes => %i(
          type
          uid_ems
          ems_ref
          name
          hostname
          vendor
          raw_power_state
          snapshots
          hardware
          operating_system
          orchestration_stack
          cpu_hot_add_enabled
          memory_hot_add_enabled
        )
      }

      super(attributes.merge!(extra_attributes))
    end

    def snapshots(extra_attributes = {})
      attributes = {
        :model_class                 => ::ManageIQ::Providers::Vmware::CloudManager::Snapshot,
        :inventory_object_attributes => %i(
          type
          name
          uid
          ems_ref
          parent_uid
          create_time
          total_size
        ),
      }

      super(attributes.merge!(extra_attributes))
    end

    def hardwares(extra_attributes = {})
      attributes = {
        :inventory_object_attributes => %i(
          guest_os
          guest_os_full_name
          bitness
          cpu_sockets
          cpu_cores_per_socket
          cpu_total_cores
          memory_mb
          disk_capacity
          disks
        )
      }

      super(attributes.merge!(extra_attributes))
    end

    def disks(extra_attributes = {})
      attributes = {
        :inventory_object_attributes => %i(
          device_name
          device_type
          disk_type
          controller_type
          size
          location
          filename
        )
      }

      super(attributes.merge!(extra_attributes))
    end

    def operating_systems(extra_attributes = {})
      attributes = {
        :inventory_object_attributes => %i(
          product_name
        )
      }

      super(attributes.merge!(extra_attributes))
    end

    def orchestration_templates(extra_attributes = {})
      attributes = {
        :model_class                 => ::ManageIQ::Providers::Vmware::CloudManager::OrchestrationTemplate,
        :inventory_object_attributes => %i(
          type
          ems_ref
          name
          description
          orderable
          content
          ems_id
        ),
        :builder_params              => {
          :ems_id => ->(persister) { persister.manager.id },
        }
      }

      super(attributes.merge!(extra_attributes))
    end

    def miq_templates(extra_attributes = {})
      attributes = {
        :model_class                 => ::ManageIQ::Providers::Vmware::CloudManager::Template,
        :inventory_object_attributes => %i(
          uid_ems
          ems_ref
          name
          vendor
          raw_power_state
          publicly_available
        )
      }

      super(attributes.merge!(extra_attributes))
    end
  end
end
