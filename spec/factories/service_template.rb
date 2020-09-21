FactoryBot.define do
  factory :service_template_ovf, :class => "ManageIQ::Providers::Vmware::InfraManager::OvfServiceTemplate", :parent => :service_template
end
