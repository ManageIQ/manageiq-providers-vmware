describe ManageIQ::Providers::Vmware::InfraManager::VmOrTemplateShared::Operations do
  let(:ems)     { FactoryBot.create(:ems_vmware_with_authentication) }
  let(:vm)      { FactoryBot.create(:vm_vmware, :ext_management_system => ems) }
  let(:miq_vim) do
    double("VMwareWebService/MiqVim").tap do |vim|
      allow(vim).to receive(:disconnect)
      allow(vim).to receive(:sic)
      allow(vim).to receive(:about).and_return({"apiType" => "VirtualCenter"})
    end
  end
  let(:miq_vim_vm) do
    double("MiqVimVm").tap do |vm|
      allow(vm).to receive(:logUserEvent)
      allow(vm).to receive(:release)
    end
  end

  before do
    require "VMwareWebService/MiqVim"
    allow(MiqVim).to receive(:new).and_return(miq_vim)
    allow(miq_vim).to receive(:getVimVmByMor).and_return(miq_vim_vm)
  end

  describe "#clone" do
    let(:folder)    { FactoryBot.create(:vmware_folder_vm, :ext_management_system => ems) }
    let(:respool)   { FactoryBot.create(:resource_pool_vmware, :ext_management_system => ems) }
    let(:host)      { FactoryBot.create(:host_vmware_esx, :ext_management_system => ems) }
    let(:datastore) { FactoryBot.create(:storage_vmware, :ext_management_system => ems) }

    it "success: with proper parameters" do
      new_name = "#{vm.name}_new"
      expect(miq_vim_vm).to receive(:cloneVM).with(new_name, folder.ems_ref, respool.ems_ref, host.ems_ref, nil, false, false, nil, nil, nil, nil)
      vm.clone(new_name, folder, respool, host, datastore)
    end
  end
end
