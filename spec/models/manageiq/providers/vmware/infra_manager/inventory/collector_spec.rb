require 'rbvmomi/vim'

describe ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector do
  let!(:ems) do
    _, _, zone = EvmSpecHelper.create_guid_miq_server_zone
    hostname = Rails.application.secrets.vmware.try(:[], "hostname") || "HOSTNAME"
    FactoryBot.create(:ems_vmware_with_authentication, :hostname => hostname, :zone => zone).tap do |ems|
      # NOTE: VCR filter_sensitive_data was replacing rootFolder with VMWARE_USERNAME and
      # vmware_soap_string_abcdef with VMWARE_PASSWORD_string_abcdef, given these are the
      # default credentials for a virtual center this doesn't need to be hidden
      username = "root"
      password = "vmware"

      ems.update_authentication(:default => {:userid => username, :password => password})
    end
  end
  let(:collector) { described_class.new(ems, :run_once => true, :threaded => false) }

  context "#monitor_updates" do
    context "full refresh" do
      it "Performs a full refresh" do
        2.times do
          run_full_refresh
          ems.reload

          assert_ems
          assert_specific_datacenter
          assert_specific_datastore
          assert_specific_folder
          assert_specific_host
          assert_specific_cluster
          assert_specific_resource_pool
          assert_specific_switch
          assert_specific_lan
          assert_specific_dvswitch
          assert_specific_dvportgroup
          assert_specific_vm
        end
      end

      it "Same as classic refresh" do
        with_vcr("classic") { EmsRefresh.init_console; EmsRefresh.refresh(ems) }
        inventory_after_classic_refresh = serialize_inventory

        with_vcr("graph")   { collector.run }
        inventory_after_graph_refresh = serialize_inventory

        assert_inventory_not_changed(inventory_after_classic_refresh, inventory_after_graph_refresh)
      end

      def with_vcr(suffix, &block)
        path = described_class.name
        path << "::#{suffix}"

        VCR.use_cassette(path.underscore, :match_requests_on => [:body]) { block.call }
      end

      def serialize_inventory
        internal_models = [MiqRegionRemote, VmdbDatabaseConnection, VmdbDatabaseLock, VmdbDatabaseSetting]
        temp_failures = [GuestDevice, HostSwitch, Lan, Relationship, Switch]
        models = ApplicationRecord.subclasses - internal_models - temp_failures

        global_skip_attrs = ["created_on", "updated_on"]
        table_skip_attrs = {
          "EmsFolder"           => ["hidden"],
          "ExtManagementSystem" => ["last_refresh_date"],
        }

        models.each_with_object({}) do |model, inventory|
          inventory[model.name] = model.all.map do |rec|
            skip_attrs = global_skip_attrs + table_skip_attrs[model.name].to_a
            rec.attributes.except(*skip_attrs)
          end.sort_by { |rec| rec["id"] }
        end
      end

      def assert_inventory_not_changed(before, after)
        expect(before.keys).to match_array(after.keys)
        before.keys.each do |model|
          expect(before[model].count).to eq(after[model].count)

          before[model].each do |item_before|
            item_after = after[model].detect { |i| i["id"] == item_before["id"]}
            expect(item_before).to eq(item_after)
          end
        end
      end
    end

    context "targeted refresh" do
      let(:vim)             { RbVmomi::VIM.new(:ns => "urn2", :rev => "6.5") }
      let(:property_filter) { RbVmomi::VIM.PropertyFilter(vim, "session[6f2dcefd-41de-6dfb-0160-1ee1cc024553]") }
      let(:cache)           { collector.send(:inventory_cache) }

      before do
        # Use the VCR to prime the cache and do the initial save_inventory
        run_full_refresh
      end

      it "doesn't impact unassociated inventory" do
        run_targeted_refresh(targeted_update_set([vm_power_on_object_update]))
        assert_ems
      end

      it "power on a virtual machine" do
        vm = ems.vms.find_by(:ems_ref => 'vm-107')

        expect(vm.power_state).to eq("off")
        run_targeted_refresh(targeted_update_set([vm_power_on_object_update]))
        expect(vm.reload.power_state).to eq("on")
      end

      it "migrate a virtual machine" do
        vm = ems.vms.find_by(:ems_ref => 'vm-107')

        expect(vm.host.ems_ref).to eq("host-98")
        run_targeted_refresh(targeted_update_set([vm_migrate_object_update]))
        expect(vm.reload.host.ems_ref).to eq("host-99")
      end

      it "deleting a virtual machine" do
        vm = ems.vms.find_by(:ems_ref => 'vm-107')

        expect(vm.archived?).to be_falsy
        run_targeted_refresh(targeted_update_set(vm_delete_object_updates))
        expect(vm.reload.archived?).to be_truthy
      end

      it "moving a vm to a new folder and resource-pool" do
        vm = ems.vms.find_by(:ems_ref => "vm-107")

        prev_folder  = vm.parent_blue_folder
        prev_respool = vm.parent_resource_pool

        expect(prev_folder.ems_ref).to eq("group-v62")
        expect(prev_folder.children).to include(vm)

        run_targeted_refresh(targeted_update_set(vm_new_folder_object_updates))

        new_folder  = vm.parent_blue_folder
        new_respool = vm.parent_resource_pool

        expect(new_folder.ems_ref).to eq("group-v2000")
        expect(prev_folder.reload.children).not_to include(vm)

        expect(new_respool.ems_ref).to eq("resgroup-111")
        expect(prev_respool.reload.children).not_to include(vm)
      end

      it "creating and deleting a snapshot" do
        vm = ems.vms.find_by(:ems_ref => "vm-107")

        expect(vm.snapshots.count).to eq(0)

        run_targeted_refresh(targeted_update_set([vm_create_snapshot_object_update]))

        vm.reload

        expect(vm.snapshots.count).to eq(1)
        expect(vm.snapshots.first).to have_attributes(
          :uid         => "2018-05-19T06:47:56.000000Z",
          :parent_uid  => nil,
          :name        => "VM Snapshot 5%2f19%2f2018, 6:47:56 AM",
          :description => "",
          :current     => 1,
          :create_time => Time.parse("2018-05-19 06:47:56 UTC").utc,
          :parent_id   => nil,
          :uid_ems     => "2018-05-19 06:47:56 UTC",
          :ems_ref     => "snapshot-1100",
        )

        run_targeted_refresh(targeted_update_set([vm_delete_snapshot_object_update]))

        vm.reload

        expect(vm.snapshots.count).to eq(0)
      end

      it "creating a snapshot with a parent" do
        vm = ems.vms.find_by(:ems_ref => "vm-107")

        expect(vm.snapshots.count).to eq(0)

        run_targeted_refresh(targeted_update_set([vm_create_snapshot_object_update, vm_create_child_snapshot_object_update]))

        vm.reload

        expect(vm.snapshots.count).to eq(2)
        root_snapshot = vm.snapshots.find_by(:ems_ref => "snapshot-1100")
        child_snapshot = vm.snapshots.find_by(:ems_ref => "snapshot-1101")

        expect(child_snapshot.parent).to eq(root_snapshot)
      end

      def run_targeted_refresh(update_set)
        persister       = ems.class::Inventory::Persister::Targeted.new(ems)
        parser          = ems.class::Inventory::Parser.new(cache, persister)
        updated_objects = collector.send(:process_update_set, property_filter, update_set)

        collector.send(:parse_updates, updated_objects, parser)
        collector.send(:save_inventory, persister)
      end

      def targeted_update_set(object_updates)
        property_filter_update = RbVmomi::VIM.PropertyFilterUpdate(
          :filter    => property_filter,
          :objectSet => object_updates,
        )

        RbVmomi::VIM.UpdateSet(
          :version   => "1",
          :filterSet => [property_filter_update],
          :truncated => false,
        )
      end

      def vm_power_on_object_update
        RbVmomi::VIM.ObjectUpdate(
          :dynamicProperty => [],
          :kind            => "modify",
          :obj             => RbVmomi::VIM.VirtualMachine(vim, "vm-107"),
          :changeSet       => [
            RbVmomi::VIM.PropertyChange(:name => "config.hotPlugMemoryIncrementSize", :op => "assign"),
            RbVmomi::VIM.PropertyChange(:name => "config.hotPlugMemoryLimit",         :op => "assign"),
            RbVmomi::VIM.PropertyChange(:name => "summary.runtime.powerState",        :op => "assign", :val => "poweredOn"),
            RbVmomi::VIM.PropertyChange(:name => "summary.storage.committed",         :op => "assign", :val => 210_930),
            RbVmomi::VIM.PropertyChange(:name => "summary.storage.unshared",          :op => "assign", :val => 0),
          ],
          :missingSet      => [],
        )
      end

      def vm_migrate_object_update
        RbVmomi::VIM.ObjectUpdate(
          :dynamicProperty => [],
          :kind            => "modify",
          :obj             => RbVmomi::VIM.VirtualMachine(vim, "vm-107"),
          :changeSet       => [
            RbVmomi::VIM.PropertyChange(:name => "summary.runtime.host", :op => "assign", :val => RbVmomi::VIM.HostSystem(vim, "host-99")),
          ],
          :missingSet      => [],
        )
      end

      def vm_delete_object_updates
        [
          RbVmomi::VIM.ObjectUpdate(
            :dynamicProperty => [],
            :kind            => "leave",
            :obj             => RbVmomi::VIM.VirtualMachine(vim, "vm-107"),
            :changeSet       => [],
            :missingSet      => [],
          ),
          RbVmomi::VIM.ObjectUpdate(
            :dynamicProperty => [],
            :kind            => "modify",
            :obj             => RbVmomi::VIM.ClusterComputeResource(vim, "domain-c96"),
            :changeSet       => [
              RbVmomi::VIM.PropertyChange(
                :dynamicProperty => [],
                :name            => "summary.effectiveCpu",
                :op              => "assign",
                :val             => 47_983,
              ),
              RbVmomi::VIM.PropertyChange(
                :dynamicProperty => [],
                :name            => "summary.effectiveMemory",
                :op              => "assign",
                :val             => 59_871,
              ),
            ],
            :missingSet      => [],
          ),
        ]
      end

      def vm_new_folder_object_updates
        [
          RbVmomi::VIM.ObjectUpdate(
            :dynamicProperty => [],
            :kind            => "enter",
            :obj             => RbVmomi::VIM.Folder(vim, "group-v2000"),
            :changeSet       => [
              RbVmomi::VIM.PropertyChange(
                :dynamicProperty => [],
                :name            => "name",
                :op              => "assign",
                :val             => "test-folder-1",
              ),
              RbVmomi::VIM.PropertyChange(
                :dynamicProperty => [],
                :name            => "parent",
                :op              => "assign",
                :val             => RbVmomi::VIM.Folder(vim, "group-v3"),
              ),
            ],
            :missingSet      => [],
          ),
          RbVmomi::VIM.ObjectUpdate(
            :dynamicProperty => [],
            :kind            => "modify",
            :obj             => RbVmomi::VIM.VirtualMachine(vim, "vm-107"),
            :changeSet       => [
              RbVmomi::VIM.PropertyChange(
                :dynamicProperty => [],
                :name            => "parent",
                :op              => "assign",
                :val             => RbVmomi::VIM.Folder(vim, "group-v2000"),
              ),
              RbVmomi::VIM.PropertyChange(
                :dynamicProperty => [],
                :name            => "resourcePool",
                :op              => "assign",
                :val             => RbVmomi::VIM.ResourcePool(vim, "resgroup-111"),
              ),
            ],
            :missingSet      => [],
          ),
        ]
      end
    end

    def vm_create_snapshot_object_update
      RbVmomi::VIM.ObjectUpdate(
        :dynamicProperty => [],
        :kind            => "modify",
        :obj             => RbVmomi::VIM.VirtualMachine(vim, "vm-107"),
        :changeSet       => [
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[2000].backing.deltaDiskFormat",
            :op              => "assign",
            :val             => "redoLogFormat",
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[2000].backing.deltaDiskFormatVariant",
            :op              => "assign",
            :val             => "vmfsSparseVariant",
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[2000].backing.fileName",
            :op              => "assign",
            :val             => "[GlobalDS_0] DC0_C1_RP1_VM0/DC0_C1_RP1_VM0-000001.vmdk",
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[2000].backing.parent",
            :op              => "assign",
            :val             => RbVmomi::VIM.VirtualDiskFlatVer2BackingInfo(
              :dynamicProperty => [],
              :fileName        => "[GlobalDS_0] DC0_C1_RP1_VM0/DC0_C1_RP1_VM0.vmdk",
              :datastore       => RbVmomi::VIM.Datastore(vim, "datastore-15"),
              :backingObjectId => "",
              :diskMode        => "persistent",
              :thinProvisioned => true,
              :uuid            => "52dab7a1-6c3e-1f7b-fe00-a2c6213343b7",
              :contentId       => "2929a7a583fe0c83749f9402fffffffe",
              :digestEnabled   => false,
            ),
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "snapshot",
            :op              => "assign",
            :val             => RbVmomi::VIM.VirtualMachineSnapshotInfo(
              :dynamicProperty  => [],
              :currentSnapshot  => RbVmomi::VIM.VirtualMachineSnapshot(vim, "snapshot-1100"),
              :rootSnapshotList => [
                RbVmomi::VIM.VirtualMachineSnapshotTree(
                  :dynamicProperty   => [],
                  :snapshot          => RbVmomi::VIM.VirtualMachineSnapshot(vim, "snapshot-1100"),
                  :vm                => RbVmomi::VIM.VirtualMachine(vim, "vm-107"),
                  :name              => "VM Snapshot 5%252f19%252f2018, 6:47:56 AM",
                  :description       => "",
                  :id                => 5,
                  :createTime        => Time.parse("2018-05-19 06:47:56 UTC").utc,
                  :state             => "poweredOff",
                  :quiesced          => false,
                  :childSnapshotList => [],
                  :replaySupported   => false,
                ),
              ],
            ),
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "summary.storage.committed",
            :op              => "assign",
            :val             => 54_177,
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "summary.storage.unshared",
            :op              => "assign",
            :val             => 41_855,
          ),
        ],
        :missingSet      => [],
      )
    end

    def vm_delete_snapshot_object_update
      RbVmomi::VIM.ObjectUpdate(
        :dynamicProperty => [],
        :kind            => "modify",
        :obj             => RbVmomi::VIM.VirtualMachine(vim, "vm-107"),
        :changeSet       => [
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[2000].backing.deltaDiskFormat",
            :op              => "assign",
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[2000].backing.deltaDiskFormatVariant",
            :op              => "assign",
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[2000].backing.fileName",
            :op              => "assign",
            :val             => "[GlobalDS_0] DC0_C1_RP1_VM0/DC0_C1_RP1_VM0.vmdk",
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[2000].backing.parent",
            :op              => "assign",
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "snapshot",
            :op              => "assign",
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "summary.storage.committed",
            :op              => "assign",
            :val             => 2316,
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "summary.storage.unshared",
            :op              => "assign",
            :val             => 538,
          ),
        ],
        :missingSet      => [],
      )
    end

    def vm_create_child_snapshot_object_update
      RbVmomi::VIM.ObjectUpdate(
        :dynamicProperty => [],
        :kind            => "modify",
        :obj             => RbVmomi::VIM.VirtualMachine(vim, "vm-107"),
        :changeSet       => [
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[2000].backing.deltaDiskFormat",
            :op              => "assign",
            :val             => "redoLogFormat",
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[2000].backing.deltaDiskFormatVariant",
            :op              => "assign",
            :val             => "vmfsSparseVariant",
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[2000].backing.fileName",
            :op              => "assign",
            :val             => "[GlobalDS_0] DC0_C1_RP1_VM0/DC0_C1_RP1_VM0-000002.vmdk",
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[2000].backing.parent.fileName",
            :op              => "assign",
            :val             => "[GlobalDS_0] DC0_C1_RP1_VM0/DC0_C1_RP1_VM0-000001.vmdk",
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[2000].backing.parent.parent",
            :op              => "assign",
            :val             => RbVmomi::VIM.VirtualDiskFlatVer2BackingInfo(
              :dynamicProperty => [],
              :fileName        => "[GlobalDS_0] DC0_C1_RP1_VM0/DC0_C1_RP1_VM0.vmdk",
              :datastore       => RbVmomi::VIM.Datastore(vim, "datastore-15"),
              :backingObjectId => "",
              :diskMode        => "persistent",
              :thinProvisioned => true,
              :uuid            => "52dab7a1-6c3e-1f7b-fe00-a2c6213343b7",
              :contentId       => "2929a7a583fe0c83749f9402fffffffe",
              :digestEnabled   => false,
            ),
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "snapshot.currentSnapshot",
            :op              => "assign",
            :val             => RbVmomi::VIM.VirtualMachineSnapshot(vim, "snapshot-1101"),
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "snapshot.rootSnapshotList",
            :op              => "assign",
            :val             => [
              RbVmomi::VIM.VirtualMachineSnapshotTree(
                :dynamicProperty   => [],
                :snapshot          => RbVmomi::VIM.VirtualMachineSnapshot(vim, "snapshot-1100"),
                :vm                => RbVmomi::VIM.VirtualMachine(vim, "vm-107"),
                :name              => "VM Snapshot 5%252f19%252f2018, 6:47:56 AM",
                :description       => "",
                :id                => 5,
                :createTime        => Time.parse("2018-05-19 06:47:56 UTC").utc,
                :state             => "poweredOff",
                :quiesced          => false,
                :childSnapshotList => [
                  RbVmomi::VIM.VirtualMachineSnapshotTree(
                    :dynamicProperty   => [],
                    :snapshot          => RbVmomi::VIM.VirtualMachineSnapshot(vim, "snapshot-1101"),
                    :vm                => RbVmomi::VIM.VirtualMachine(vim, "vm-107"),
                    :name              => "VM Snapshot 5%252f19%252f2018, 9:54:05 AM",
                    :description       => "",
                    :id                => 5,
                    :createTime        => Time.parse("2018-05-19 09:54:05 UTC").utc,
                    :state             => "poweredOff",
                    :quiesced          => false,
                    :childSnapshotList => [],
                    :replaySupported   => false,
                  )
                ],
                :replaySupported   => false,
              ),
            ],
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "summary.storage.committed",
            :op              => "assign",
            :val             => 54_177,
          ),
          RbVmomi::VIM.PropertyChange(
            :dynamicProperty => [],
            :name            => "summary.storage.unshared",
            :op              => "assign",
            :val             => 41_855,
          ),
        ],
        :missingSet      => [],
      )
    end

    def run_full_refresh
      # All VIM API calls go to uri https://hostname/sdk so we have to match on the body
      VCR.use_cassette(described_class.name.underscore, :match_requests_on => [:body]) do
        collector.run
      end
    end

    def assert_ems
      expect(ems.api_version).to eq("5.5")
      expect(ems.last_refresh_error).to be_nil
      expect(ems.last_refresh_date).not_to be_nil
      expect(ems.uid_ems).to eq("D6EB1D64-05B2-4937-BFF6-6F77C6E647B7")
      expect(ems.ems_clusters.count).to eq(4)
      expect(ems.ems_folders.count).to eq(11)
      expect(ems.ems_folders.where(:type => "Datacenter").count).to eq(2)
      expect(ems.disks.count).to eq(64)
      expect(ems.guest_devices.count).to eq(64)
      expect(ems.hardwares.count).to eq(64)
      expect(ems.hosts.count).to eq(16)
      expect(ems.host_operating_systems.count).to eq(16)
      expect(ems.operating_systems.count).to eq(64)
      expect(ems.resource_pools.count).to eq(12)
      expect(ems.storages.count).to eq(1)
      expect(ems.vms_and_templates.count).to eq(64)
      expect(ems.switches.count).to eq(18)
      expect(ems.lans.count).to eq(36)
    end

    def assert_specific_datacenter
      datacenter = ems.ems_folders.find_by(:ems_ref => "datacenter-2")

      expect(datacenter).not_to be_nil
      expect(datacenter).to have_attributes(
        :ems_ref => "datacenter-2",
        :name    => "DC0",
        :type    => "Datacenter",
        :uid_ems => "datacenter-2",
      )

      expect(datacenter.parent.ems_ref).to eq("group-d1")

      expect(datacenter.children.count).to eq(4)
      expect(datacenter.children.map(&:name)).to match_array(%w(host network datastore vm))
    end

    def assert_specific_datastore
      storage = ems.storages.find_by(:location => "ds:///vmfs/volumes/5280a4c3-b5e2-7dc7-5c31-7a344d35466c/")

      expect(storage).to have_attributes(
        :location                      => "ds:///vmfs/volumes/5280a4c3-b5e2-7dc7-5c31-7a344d35466c/",
        :name                          => "GlobalDS_0",
        :store_type                    => "VMFS",
        :total_space                   => 1_099_511_627_776,
        :free_space                    => 824_633_720_832,
        :multiplehostaccess            => 1,
        :directory_hierarchy_supported => true,
        :thin_provisioning_supported   => true,
        :raw_disk_mappings_supported   => true,
      )

      expect(storage.hosts.count).to eq(16)
      expect(storage.disks.count).to eq(64)
      expect(storage.vms.count).to   eq(64)
    end

    def assert_specific_folder
      folder = ems.ems_folders.find_by(:ems_ref => "group-d1")

      expect(folder).not_to be_nil
      expect(folder).to have_attributes(
        :ems_ref => "group-d1",
        :name    => "Datacenters",
        :uid_ems => "group-d1",
        :hidden  => true,
      )

      expect(folder.parent).to eq(ems)
      expect(folder.children.count).to eq(2)
      expect(folder.children.map(&:name)).to match_array(%w(DC0 DC1))
    end

    def assert_specific_host
      host = ems.hosts.find_by(:ems_ref => "host-14")

      expect(host).not_to be_nil

      expect(host.parent).not_to be_nil
      expect(host.parent.ems_ref).to eq("domain-c12")

      switch = host.switches.find_by(:name => "vSwitch0")

      expect(switch).not_to be_nil
      expect(switch).to have_attributes(
        :name              => "vSwitch0",
        :uid_ems           => "vSwitch0",
        :ports             => 64,
        :allow_promiscuous => false,
        :forged_transmits  => true,
        :mac_changes       => true,
        :type              => "ManageIQ::Providers::Vmware::InfraManager::HostVirtualSwitch",
      )

      vnic = host.hardware.guest_devices.find_by(:uid_ems => "vmnic0")
      expect(vnic).not_to be_nil
      expect(vnic).to have_attributes(
        :device_name     => "vmnic0",
        :device_type     => "ethernet",
        :location        => "03:00.0",
        :controller_type => "ethernet",
        :uid_ems         => "vmnic0",
        :switch          => switch,
      )

      hba = host.hardware.guest_devices.find_by(:uid_ems => "vmhba1")

      expect(hba).not_to be_nil
      expect(hba).to have_attributes(
        :device_name     => "vmhba1",
        :device_type     => "storage",
        :location        => "0e:00.0",
        :controller_type => "Block",
        :model           => "Smart Array P400",
        :present         => true,
        :start_connected => true,
        :uid_ems         => "vmhba1",
      )

      expect(hba.miq_scsi_targets.count).to eq(1)

      scsi_target = hba.miq_scsi_targets.first
      expect(scsi_target).to have_attributes(
        :target      => 0,
        :uid_ems     => "0",
        :iscsi_name  => nil,
        :iscsi_alias => nil,
        :address     => nil,
      )

      expect(scsi_target.miq_scsi_luns.count).to eq(1)

      scsi_lun = scsi_target.miq_scsi_luns.first
      expect(scsi_lun).to have_attributes(
        :lun            => 0,
        :canonical_name => "mpx.vmhba1:C0:T0:L0",
        :lun_type       => "disk",
        :device_name    => "/vmfs/devices/disks/mpx.vmhba1:C0:T0:L0",
        :device_type    => "disk",
        :block          => 1_146_734_896,
        :block_size     => 512,
        :capacity       => 573_367_448,
        :uid_ems        => "0000000000766d686261313a303a30",
      )

      system_services = host.system_services
      expect(system_services.count).to eq(2)
      expect(system_services.find_by(:name => "ntpd")).to have_attributes(
        :name         => "ntpd",
        :display_name => "NTP Daemon",
        :running      => true,
      )
    end

    def assert_specific_cluster
      cluster = ems.ems_clusters.find_by(:ems_ref => "domain-c12")

      expect(cluster).not_to be_nil
      expect(cluster).to have_attributes(
        :drs_automation_level    => "manual",
        :drs_enabled             => true,
        :drs_migration_threshold => 3,
        :effective_cpu           => 47_984,
        :effective_memory        => 62_780_342_272,
        :ems_ref                 => "domain-c12",
        :ha_admit_control        => true,
        :ha_enabled              => false,
        :ha_max_failures         => 1,
        :name                    => "DC0_C0",
        :uid_ems                 => "domain-c12",
      )

      expect(cluster.parent).not_to be_nil
      expect(cluster.parent.ems_ref).to eq("group-h4")

      expect(cluster.children.count).to eq(5)
      expect(cluster.default_resource_pool.ems_ref).to eq("resgroup-13")
    end

    def assert_specific_resource_pool
      resource_pool = ems.resource_pools.find_by(:ems_ref => "resgroup-13")

      expect(resource_pool).not_to be_nil
      expect(resource_pool).to have_attributes(
        :cpu_limit             => 47_984,
        :cpu_reserve           => 47_984,
        :cpu_reserve_expand    => true,
        :cpu_shares            => 4_000,
        :cpu_shares_level      => "normal",
        :memory_limit          => 59_872,
        :memory_reserve        => 59_872,
        :memory_reserve_expand => true,
        :memory_shares         => 163_840,
        :memory_shares_level   => "normal",
        :name                  => "Default for Cluster / Deployment Role DC0_C0",
        :vapp                  => false,
        :is_default            => true,
      )

      expect(resource_pool.parent.ems_ref).to eq("domain-c12")

      expect(resource_pool.children.count).to eq(2)
      expect(resource_pool.children.map(&:ems_ref)).to match_array(%w(resgroup-28 resgroup-19))
    end

    def assert_specific_switch
      host = ems.hosts.find_by(:ems_ref => "host-14")
      switch = host.switches.find_by(:name => "vSwitch0")

      expect(switch).not_to be_nil
      expect(switch).to have_attributes(
        :name              => "vSwitch0",
        :ports             => 64,
        :uid_ems           => "vSwitch0",
        :allow_promiscuous => false,
        :forged_transmits  => true,
        :mac_changes       => true,
      )

      expect(switch.lans.count).to eq(2)
      expect(switch.hosts.count).to eq(1)
    end

    def assert_specific_lan
      host = ems.hosts.find_by(:ems_ref => "host-14")
      switch = host.switches.find_by(:name => "vSwitch0")
      lan = switch.lans.find_by(:uid_ems => "VM Network")

      expect(lan).not_to be_nil
      expect(lan).to have_attributes(
        :name                       => "VM Network",
        :uid_ems                    => "VM Network",
        :tag                        => "0",
        :allow_promiscuous          => false,
        :forged_transmits           => true,
        :mac_changes                => true,
        :computed_allow_promiscuous => false,
        :computed_forged_transmits  => true,
        :computed_mac_changes       => true,
      )

      expect(lan.switch.uid_ems).to eq("vSwitch0")
    end

    def assert_specific_dvswitch
      dvs = ems.switches.find_by(:uid_ems => "dvs-8")

      expect(dvs).not_to be_nil
      expect(dvs).to have_attributes(
        :uid_ems           => "dvs-8",
        :name              => "DC0_DVS",
        :ports             => 288,
        :switch_uuid       => "a9 af 24 50 51 3a 40 48-56 b4 3d fe 0c 8b a0 5f",
        :type              => "ManageIQ::Providers::Vmware::InfraManager::DistributedVirtualSwitch",
        :allow_promiscuous => false,
        :forged_transmits  => false,
        :mac_changes       => false,
      )

      expect(dvs.lans.count).to eq(2)
      expect(dvs.hosts.count).to eq(8)
    end

    def assert_specific_dvportgroup
      lan = ems.lans.find_by(:uid_ems => "dvportgroup-10")

      expect(lan).not_to be_nil
      expect(lan).to have_attributes(
        :name              => "DC0_DVPG0",
        :uid_ems           => "dvportgroup-10",
        :allow_promiscuous => false,
        :forged_transmits  => false,
        :mac_changes       => false,
        :tag               => nil,
      )

      expect(lan.switch.uid_ems).to eq("dvs-8")
    end

    def assert_specific_vm
      vm = ems.vms.find_by(:ems_ref => "vm-21")

      expect(vm).to have_attributes(
        :connection_state      => "connected",
        :cpu_reserve           => 0,
        :cpu_reserve_expand    => false,
        :cpu_limit             => -1,
        :cpu_shares            => 1000,
        :cpu_shares_level      => "normal",
        :cpu_affinity          => nil,
        :ems_ref               => "vm-21",
        :location              => "DC0_C0_RP0_VM1/DC0_C0_RP0_VM1.vmx",
        :memory_reserve        => 0,
        :memory_reserve_expand => false,
        :memory_limit          => -1,
        :memory_shares         => 640,
        :memory_shares_level   => "normal",
        :name                  => "DC0_C0_RP0_VM1",
        :raw_power_state       => "poweredOn",
        :type                  => "ManageIQ::Providers::Vmware::InfraManager::Vm",
        :uid_ems               => "42243da9-7676-d9ec-7a9b-e61e5db3725c",
        :vendor                => "vmware",
      )

      expect(vm.hardware).to have_attributes(
        :bios                 => "42243da9-7676-d9ec-7a9b-e61e5db3725c",
        :cpu_cores_per_socket => 1,
        :cpu_sockets          => 1,
        :cpu_total_cores      => 1,
        :virtual_hw_version   => "07",
      )

      nic = vm.hardware.guest_devices.find_by(:uid_ems => "00:50:56:a4:01:01")
      expect(nic).to have_attributes(
        :device_name     => "Network adapter 1",
        :device_type     => "ethernet",
        :controller_type => "ethernet",
        :present         => true,
        :start_connected => true,
        :model           => "VirtualE1000",
        :address         => "00:50:56:a4:01:01",
        :uid_ems         => "00:50:56:a4:01:01",
      )

      expect(nic.lan).not_to be_nil
      expect(nic.lan.uid_ems).to eq("dvportgroup-11")

      expect(vm.disks.count).to eq(1)

      disk = vm.disks.first
      expect(disk).to have_attributes(
        :controller_type => "scsi",
        :device_name     => "Hard disk 1",
        :device_type     => "disk",
        :disk_type       => "thick",
        :filename        => "[GlobalDS_0] DC0_C0_RP0_VM1/DC0_C0_RP0_VM1.vmdk",
        :location        => "0:0",
        :mode            => "persistent",
        :size            => 536_870_912,
        :start_connected => true,
      )

      expect(vm.ems_cluster).not_to be_nil
      expect(vm.ems_cluster.ems_ref).to eq("domain-c12")

      expect(vm.host).not_to be_nil
      expect(vm.host.ems_ref).to eq("host-16")

      expect(vm.storage).not_to be_nil
      expect(vm.storage.name).to eq("GlobalDS_0")

      expect(vm.parent_blue_folder).not_to be_nil
      expect(vm.parent_blue_folder.ems_ref).to eq("group-v3")

      expect(vm.parent_yellow_folder).not_to be_nil
      expect(vm.parent_yellow_folder.ems_ref).to eq("group-d1")

      expect(vm.parent_resource_pool).not_to be_nil
      expect(vm.parent_resource_pool.ems_ref).to eq("resgroup-19")
    end
  end

  context "#process_change_set" do
    let(:vm) { RbVmomi::VIM.VirtualMachine(nil, "vm-123") }
    let(:vm_folder) { RbVmomi::VIM.Folder(nil, "group-v3") }
    let(:folder_change_set) do
      [
        RbVmomi::VIM::PropertyChange(:dynamicProperty => [], :name => "name",        :op => "assign", :val => "vm"),
        RbVmomi::VIM::PropertyChange(:dynamicProperty => [], :name => "childEntity", :op => "assign", :val => [vm]),
      ]
    end
    let(:vm_change_set) do
      [
        RbVmomi::VIM::PropertyChange(
          :dynamicProperty => [],
          :name            => "config.hardware.device",
          :op              => "assign",
          :val             => [
            RbVmomi::VIM::VirtualLsiLogicController(
              :dynamicProperty    => [],
              :key                => 1000,
              :deviceInfo         => RbVmomi::VIM::Description(:label => "SCSI controller 0", :summary => "LSI Logic"),
              :controllerKey      => 100,
              :unitNumber         => 3,
              :busNumber          => 0,
              :device             => [2000],
              :hotAddRemove       => true,
              :sharedBus          => "noSharing",
              :scsiCtlrUnitNumber => 7,
            ),
            RbVmomi::VIM::VirtualDisk(
              :dynamicProperty => [],
              :key             => 2000,
              :deviceInfo      => RbVmomi::VIM::Description(:label => "Hard disk 1", :summary => "41,943,040 KB"),
              :backing         => RbVmomi::VIM::VirtualDiskFlatVer2BackingInfo(
                :fileName        => "[datastore] vm1/vm1.vmdk",
                :datastore       => RbVmomi::VIM::Datastore(nil, "datastore-1"),
                :diskMode        => "persistent",
                :thinProvisioned => true,
                :uuid            => "6000C294-264b-3f91-8e5c-8c2ebac1bfe8",
              ),
              :controllerKey   => 1000,
              :unitNumber      => 0,
              :capacityInKB    => 41_943_040,
            ),
          ]
        ),
        RbVmomi::VIM::PropertyChange(
          :dynamicProperty => [],
          :name            => "config.version",
          :op              => "assign",
          :val             => "vmx-08"
        ),
        RbVmomi::VIM::PropertyChange(
          :dynamicProperty => [],
          :name            => "name",
          :op              => "assign",
          :val             => "vm1"
        ),
        RbVmomi::VIM::PropertyChange(
          :dynamicProperty => [],
          :name            => "parent",
          :op              => "assign",
          :val             => vm_folder
        ),
      ]
    end

    let(:vm_props) { collector.process_change_set(vm_change_set) }
    let(:folder_props) { collector.process_change_set(folder_change_set) }

    context "initial" do
      it "processes initial change set" do
        expect(vm_props.keys).to include(:config, :name, :parent)
      end
    end

    context "update" do
      it "updates a value in an array" do
        update_change_set = [
          RbVmomi::VIM::PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[1000].device",
            :op              => "assign",
            :val             => [2000, 2001]
          ),
          RbVmomi::VIM::PropertyChange(
            :dynamicProperty => [],
            :name            => "config.hardware.device[2002]",
            :op              => "add",
            :val             => RbVmomi::VIM::VirtualDisk(
              :dynamicProperty => [],
              :key             => 2001,
              :deviceInfo      => RbVmomi::VIM::Description(:dynamicProperty => [], :label => "Hard disk 2", :summary => "16,777,216 KB"),
              :backing         => RbVmomi::VIM::VirtualDiskFlatVer2BackingInfo(),
              :controllerKey   => 1000,
              :unitNumber      => 2,
              :capacityInKB    => 16_777_216,
            )
          ),
        ]

        props = collector.process_change_set(update_change_set, vm_props)

        controller = props[:config][:hardware][:device].detect { |dev| dev.key == 1000 }
        expect(controller[:device]).to match_array([2000, 2001])
      end

      it "removes a managed entity in an array by mor" do
        update_change_set = [
          RbVmomi::VIM::PropertyChange(:dynamicProperty => [], :name => "childEntity[\"vm-123\"]", :op => "remove")
        ]

        props = collector.process_change_set(update_change_set, folder_props)
        expect(props[:childEntity]).not_to include(vm)
      end

      it "removes a data object in an array by key" do
        update_change_set = [
          RbVmomi::VIM.PropertyChange(:name => "config.hardware.device[1000].device", :op => "assign", :val => []),
          RbVmomi::VIM.PropertyChange(:name => "config.hardware.device[2000]", :op => "remove"),
          RbVmomi::VIM.PropertyChange(:name => "summary.storage.committed", :op => "assign", :val => 1422),
          RbVmomi::VIM.PropertyChange(:name => "summary.storage.unshared", :op => "assign", :val => 0),
        ]

        props = collector.process_change_set(update_change_set, vm_props)

        device_keys = props[:config][:hardware][:device].map(&:key)
        expect(device_keys).not_to include(2000)
      end

      it "assigns to array with a ref as an array key" do
        datastore_host = [
          RbVmomi::VIM.DatastoreHostMount(
            :key       => RbVmomi::VIM.HostSystem(nil, "host-815"),
            :mountInfo => RbVmomi::VIM.HostMountInfo(
              :path       => "/vmfs/volumes/b4db3893-29a32816",
              :accessMode => "readWrite",
              :mounted    => true,
              :accessible => true
            )
          ),
          RbVmomi::VIM.DatastoreHostMount(
            :key       => RbVmomi::VIM.HostSystem(nil, "host-244"),
            :mountInfo => RbVmomi::VIM.HostMountInfo(
              :path       => "/vmfs/volumes/b4db3893-29a32816",
              :accessMode => "readWrite",
              :mounted    => true,
              :accessible => true
            )
          ),
        ]

        initial_change_set = [
          RbVmomi::VIM.PropertyChange(:dynamicProperty => [], :name => "host", :op => "assign", :val => datastore_host),
        ]

        ds_props = collector.process_change_set(initial_change_set)

        update_change_set = [
          RbVmomi::VIM::PropertyChange(
            :dynamicProperty => [],
            :name            => "host[\"host-244\"].mountInfo",
            :op              => "assign",
            :val             => RbVmomi::VIM::HostMountInfo(
              :dynamicProperty => [],
              :path            => "/vmfs/volumes/b4db3893-29a32816",
              :accessMode      => "readWrite",
              :mounted         => false,
              :accessible      => false
            )
          )
        ]

        props = collector.process_change_set(update_change_set, ds_props)

        host_mount = props[:host].detect { |h| h.key._ref == "host-244" }
        expect(host_mount.mountInfo.props).to include(:mounted => false, :accessible => false)
      end
    end
  end
end
