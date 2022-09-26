describe ManageIQ::Providers::Vmware::InfraManager::Provision::Cloning do
  let(:zone)              { EvmSpecHelper.local_miq_server.zone }
  let(:ems)               { FactoryBot.create(:ems_vmware_with_authentication, :zone => zone) }
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

  context "#start_clone" do
    let(:folder)    { FactoryBot.create(:vmware_folder_vm, :ext_management_system => ems) }
    let(:host)      { FactoryBot.create(:host_vmware_esx, :ext_management_system => ems, :ems_ref => "host-1") }
    let(:pool)      { FactoryBot.create(:resource_pool_vmware, :ext_management_system => ems) }
    let(:snapshot)  { FactoryBot.create(:snapshot, :ems_ref => "snapshot-1", :ems_ref_type => "Snapshot") }
    let(:datastore) { FactoryBot.create(:storage_vmware, :ext_management_system => ems) }

    let(:clone_options) do
      {
        :name      => "clone test",
        :folder    => folder,
        :host      => host,
        :pool      => pool,
        :snapshot  => snapshot,
        :datastore => datastore
      }
    end

    # Building the disk relocate spec has to connect to the ems so we need to
    # stub that out here.
    before { allow(provision).to receive(:build_disk_relocate_spec) }

    it "converts AR objects to VimTypes" do
      expect(provision)
        .to receive(:clone_vm)
        .with(
          hash_including(
            :folder   => folder.ems_ref_obj,
            :host     => host.ems_ref_obj,
            :pool     => pool.ems_ref_obj,
            :snapshot => VimString.new(snapshot.ems_ref, snapshot.ems_ref_type, :ManagedObjectReference)
          )
        )

      provision.start_clone(clone_options)
    end
  end
end
