FactoryBot.define do
  factory :ems_cluster_vmware, :class => "ManageIQ::Providers::Vmware::InfraManager::Cluster", :parent => :ems_cluster
end
