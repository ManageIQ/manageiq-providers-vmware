describe ManageIQ::Providers::Vmware::CloudManager::ProvisionWorkflow do
  include Spec::Support::WorkflowHelper

  let(:admin)    { FactoryGirl.create(:user_with_group) }
  let(:ems)      { FactoryGirl.create(:ems_vmware_cloud) }
  let(:template) { FactoryGirl.create(:template_vmware, :name => "template", :ext_management_system => ems) }
  let(:workflow) do
    stub_dialog
    allow_any_instance_of(User).to receive(:get_timezone).and_return(Time.zone)
    allow_any_instance_of(ManageIQ::Providers::CloudManager::ProvisionWorkflow).to receive(:update_field_visibility)

    wf = described_class.new({:src_vm_id => template.id}, admin.userid)
    wf
  end

  context "availability_zone_to_cloud_network" do
    it "has one when it should" do
      FactoryGirl.create(:cloud_network_google, :ext_management_system => ems.network_manager)

      expect(workflow.allowed_cloud_networks.size).to eq(1)
    end

    it "has none when it should" do
      expect(workflow.allowed_cloud_networks.size).to eq(0)
    end
  end
end
