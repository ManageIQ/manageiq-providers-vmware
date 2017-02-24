describe ManageIQ::Providers::Vmware::InfraManager::RefreshParser::Filter do
  context "filter_vc_data" do
    let(:ems)         { FactoryGirl.create(:ems_vmware) }
    let(:dc)          { FactoryGirl.create(:vmware_datacenter) }
    let(:root_folder) { FactoryGirl.create(:vmware_folder_root) }
    let(:vm_folder)   { FactoryGirl.create(:vmware_folder_vm) }
    let(:host_folder) { FactoryGirl.create(:vmware_folder_host) }
    let(:host)        { FactoryGirl.create(:host_with_ref) }
    let(:vm)          { FactoryGirl.create(:vm_with_ref) }

    let(:vc_data) do
      inv = Hash.new { |h, k| h[k] = {} }

      inv[:vm][vm.ems_ref] = {
        "MOR"     => vm.ems_ref,
        "summary" => { "runtime" => { "host" => host.ems_ref } }
      }

      inv[:host][host.ems_ref] = {
        "MOR"    => host.ems_ref,
        "parent" => host_folder.ems_ref
      }

      inv[:dc][dc.ems_ref] = {
        "MOR"    => dc.ems_ref,
        "parent" => root_folder.ems_ref
      }

      inv[:folder][root_folder.ems_ref] = {
        "MOR"         => root_folder.ems_ref,
        "childEntity" => [dc.ems_ref]
      }

      inv[:folder][vm_folder.ems_ref] = {
        "MOR"         => vm_folder.ems_ref,
        "childEntity" => [vm.ems_ref],
        "parent"      => dc.ems_ref
      }

      inv[:folder][host_folder.ems_ref] = {
        "MOR"         => host_folder.ems_ref,
        "childEntity" => [],
        "parent"      => dc.ems_ref
      }

      inv
    end

    before do
      @refresher = ems.refresher.new([ems])
      @refresher.instance_variable_set(:@vc_data, vc_data)
    end

    context "with 1 host and 1 vm" do
      context "targeting the ems" do
        it "returns the full inventory" do
          filtered_data = @refresher.filter_vc_data(ems, ems)
          expect(filtered_data).to eq(vc_data)
        end
      end

      context "targeting a vm" do
        it "returns relevent data" do
          filtered_data = @refresher.filter_vc_data(ems, vm)

          expect(filtered_data[:host].count).to eq(1)
          expect(filtered_data[:host]).to       include(host.ems_ref)

          expect(filtered_data[:vm].count).to   eq(1)
          expect(filtered_data[:vm]).to         include(vm.ems_ref)
        end
      end
    end

    context "with a vm and no host" do
      before do
        vc_data[:host] = {}
      end

      context "targeting a vm" do
        # Test to make sure that a targeted refresh of a VM with no host
        # in inventory still returns the root folder
        it "returns the root folder" do
          filtered_data = @refresher.filter_vc_data(ems, vm)

          expect(filtered_data[:host]).not_to include(host.ems_ref)
          expect(filtered_data[:folder]).to include(root_folder.ems_ref)
        end
      end
    end
  end
end
