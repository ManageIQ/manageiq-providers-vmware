class ManageIQ::Providers::Vmware::Inventory::Parser::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Parser::ContainerManager
  require_nested :WatchNotice
end
