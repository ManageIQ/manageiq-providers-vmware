describe ManageIQ::Providers::Vmware::InfraManager::Vm::Operations::Snapshot do
  let(:vm) do
    _, _, zone = EvmSpecHelper.create_guid_miq_server_zone
    ems = FactoryBot.create(:ems_vmware, :zone => zone)
    host = FactoryBot.create(:host_vmware, :ext_management_system => ems)
    FactoryBot.create(:vm_vmware, :ext_management_system => ems, :host => host)
  end

  describe "#remove_snapshot" do
    context "with no snapshots" do
      it "raises an exception" do
        expect { vm.remove_snapshot(nil) }.to raise_error(MiqException::MiqVmError, "No snapshots available for this VM")
      end
    end

    context "with a snapshot" do
      let!(:snapshot) { FactoryBot.create(:snapshot, :vm_or_template => vm, :uid_ems => Time.now.utc) }

      it "calls to remove the snapshot" do
        expect(vm).to receive(:run_command_via_parent).with(:vm_remove_snapshot, :snMor => snapshot.uid_ems)

        vm.remove_snapshot(snapshot)
      end

      it "with an invalid snapshot id raises an exception" do
        expect { vm.remove_snapshot(nil) }.to raise_error("Requested VM snapshot not found, unable to remove snapshot")
      end

      context "with a consolidate helper snapshot" do
        let!(:ch_snapshot) { FactoryBot.create(:snapshot, :name => "Consolidate Helper", :vm_or_template => vm) }

        it "doesn't delete the snapshot" do
          expect { vm.remove_snapshot(snapshot) }
            .to raise_error("Refusing to delete snapshot when there is a Consolidate Helper snapshot")
        end
      end

      context "with a VCB snapshot" do
        let(:vcb_snapshot) { FactoryBot.create(:snapshot, :name => "_VCB-BACKUP_", :vm_or_template => vm) }

        it "doesn't delete the snpashot" do
          expect { vm.remove_snapshot(vcb_snapshot) }.to raise_error("Refusing to delete a VCB Snapshot")
        end
      end
    end
  end
end
