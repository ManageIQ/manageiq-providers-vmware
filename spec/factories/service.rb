FactoryBot.define do
  factory :service_ovf, :class => "ManageIQ::Providers::Vmware::InfraManager::OvfService", :parent => :service
end
