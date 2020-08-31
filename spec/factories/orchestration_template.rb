FactoryBot.define do
  factory :orchestration_template_vmware_cloud_in_xml,
          :parent => :orchestration_template,
          :class  => "ManageIQ::Providers::Vmware::CloudManager::OrchestrationTemplate" do
    content { File.read(ManageIQ::Providers::Vmware::Engine.root.join(*%w(spec fixtures orchestration_templates vmware_parameters_ovf.xml))) }
  end

  factory :orchestration_template_vmware_infra,
          :parent => :orchestration_template,
          :class  => "ManageIQ::Providers::Vmware::InfraManager::OrchestrationTemplate"
end
