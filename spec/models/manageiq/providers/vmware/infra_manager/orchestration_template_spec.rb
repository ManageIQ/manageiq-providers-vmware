describe ManageIQ::Providers::Vmware::InfraManager::OrchestrationTemplate do
  subject { FactoryBot.create(:orchestration_template_vmware_infra) }

  context "#deployment_spec" do
    describe "required fields" do
      let(:resource_pool) { FactoryBot.create(:resource_pool, :ems_ref => 'obj-103') }
      let(:options) { {:accept_all_EULA => false, :resource_pool_id => resource_pool.id} }

      it "raises an error if accept_all_EULA is absent" do
        options.delete(:accept_all_EULA)
        expect { subject.deployment_spec(options) }.to raise_error(/accept_all_EULA is required for content library item deployment./)
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
end
