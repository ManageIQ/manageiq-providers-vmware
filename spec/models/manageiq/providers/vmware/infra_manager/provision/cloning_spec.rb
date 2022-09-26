describe ManageIQ::Providers::Vmware::InfraManager::Provision::Cloning do
  let(:ems)               { FactoryBot.create(:ems_vmware_with_authentication) }
  let(:user_admin)        { FactoryBot.create(:user_admin) }
  let(:template)          { FactoryBot.create(:template_vmware, :name => "template1", :ext_management_system => ems, :cpu_limit => -1, :cpu_reserve => 0) }
  let(:provision)         { FactoryBot.create(:miq_provision_vmware, :userid => user_admin.userid, :miq_request => provision_request, :source => template, :request_type => 'template', :state => 'pending', :status => 'Ok', :options => options) }
  let(:provision_request) { FactoryBot.create(:miq_provision_request, :requester => user_admin, :src_vm_id => template.id) }
  let(:options) do
    {
      :pass          => 1,
      :vm_name       => "clone test",
      :number_of_vms => 1,
      :cpu_limit     => -1,
      :cpu_reserve   => 0,
      :src_vm_id     => [template.id, template.name],
    }
  end

  context "#dest_folder" do
    let(:folder_name)      { 'folder_one' }
    let(:ems_folder)       { FactoryBot.create(:vmware_folder_vm) }
    let(:dest_host)        { FactoryBot.create(:host_vmware, :ext_management_system => ems) }
    let(:dc_nested)        { EvmSpecHelper::EmsMetadataHelper.vmware_nested_folders(ems) }
    let(:dest_host_nested) { FactoryBot.create(:host_vmware, :ext_management_system => ems).tap { |h| h.parent = dc_nested } }
    let(:vm_folder_nested) { FactoryBot.create(:ems_folder, :name => 'vm', :ems_id => ems.id).tap { |v| v.parent = dc_nested } }

    it "returns a folder if one is found" do
      options[:placement_folder_name] = [ems_folder.id, ems_folder.name]
      expect(provision).to receive(:find_folder).never
      provision.dest_folder
    end

    it "attempts to find a usable folder if the ems_folder does not exist" do
      provision.options[:dest_host] = [dest_host_nested.id, dest_host_nested.name]
      expect(provision).to receive(:find_folder).once
      provision.dest_folder
    end
  end
end
