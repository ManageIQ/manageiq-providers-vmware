class ManageIQ::Providers::Vmware::Inventory::Collector::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Collector::ContainerManager
  def persistent_volumes
    # VMware Tanzu Administrator cannot access persistent_volumes
    []
  end
end
