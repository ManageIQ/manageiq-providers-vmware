FactoryBot.define do
  factory :resource_pool_vmware, :class => "ManageIQ::Providers::Vmware::InfraManager::ResourcePool", :parent => :resource_pool do
    sequence(:ems_ref) { |n| "resgroups-#{n}" }
    ems_ref_type { "ResourcePool" }
  end
end
