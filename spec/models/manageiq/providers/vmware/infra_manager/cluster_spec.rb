describe ManageIQ::Providers::Vmware::InfraManager::Cluster do
  let(:ems)      { FactoryBot.create(:ems_vmware_with_authentication) }
  let(:cluster)  { FactoryBot.create(:ems_cluster_vmware, :ext_management_system => ems) }
  let(:host_ref) { "host-123" }

  describe "#register_host" do
    before do
      vim = double("VMwareWebService/MiqVim")
      vim_cluster = double("ClusterComputeResource")
      expect(vim_cluster).to receive(:addHost).and_return(host_ref)
      allow(vim_cluster).to receive(:release)
      expect(vim).to receive(:getVimClusterByMor).and_return(vim_cluster)
      expect(ems).to receive(:connect).and_return(vim)
    end

    it "success: with valid host" do
      cluster.register_host(Host.new)

      expect(cluster.reload.hosts.count).to eq(1)
    end
  end
end
