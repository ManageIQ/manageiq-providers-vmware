describe ManageIQ::Providers::Vmware::InfraManager::OrchestrationTemplate do
  let(:ems) { FactoryBot.create(:ems_vmware) }
  let(:resource_pool) { FactoryBot.create(:resource_pool, :ems_ref => 'obj-103') }
  let(:options) { {:accept_all_eula => false, :resource_pool_id => resource_pool.id} }
  subject { FactoryBot.create(:orchestration_template_vmware_infra) }

  context "#deployment_spec" do
    describe "required fields" do
      it "raises an error if accept_all_eula is absent" do
        options.delete(:accept_all_eula)
        expect { subject.deployment_spec(options) }.to raise_error(/accept_all_eula is required for content library item deployment./)
      end

      it "raises an error if resource pool is absent" do
        options.delete(:resource_pool_id)
        expect { subject.deployment_spec(options) }.to raise_error(/Resource pool is required for content library item deployment./)
      end

      it "works with keys in string format" do
        options["vm_name"] = "new VM"
        result = subject.deployment_spec(options)
        expect(result.dig("target", "resource_pool_id")).to eq(resource_pool.ems_ref)
        expect(result.dig("deployment_spec", "accept_all_EULA")).to be false
        expect(result.dig("deployment_spec", "name")).to eq(options["vm_name"])
      end
    end
  end

  context "#deploy" do
    before { require 'vsphere-automation-vcenter' }

    it "calls provider#cis_connect" do
      item_api = double("VSphereAutomation::VCenter::OvfLibraryItemApi")
      allow(subject).to receive(:ext_management_system).and_return(ems)

      expect(ems).to receive(:cis_connect).once
      expect(ems).not_to receive(:vim_connect)
      expect(VSphereAutomation::VCenter::OvfLibraryItemApi).to receive(:new).and_return(item_api)
      expect(item_api).to receive(:deploy)

      subject.deploy(options)
    end
  end
end
