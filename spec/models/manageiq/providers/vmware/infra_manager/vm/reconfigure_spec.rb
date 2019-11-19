describe ManageIQ::Providers::Vmware::InfraManager::Vm::Reconfigure do
  let(:storage) { FactoryBot.create(:storage_vmware) }
  let(:host) do
    FactoryBot.create(:host_vmware_esx).tap do |host|
      host.host_storages.create(:storage_id => storage.id, :host_id => host.id, :ems_ref => "datastore-1")
    end
  end
  let(:vm) do
    FactoryBot.create(
      :vm_vmware,
      :name            => 'test_vm',
      :raw_power_state => 'poweredOff',
      :storage         => FactoryBot.create(:storage, :name => 'storage'),
      :hardware        => FactoryBot.create(:hardware, :cpu4x2, :ram1GB, :virtual_hw_version => "07"),
      :host            => host,
    )
  end

  describe "#reconfigurable?" do
    let(:ems)         { FactoryBot.create(:ext_management_system) }
    let(:vm_active)   { FactoryBot.create(:vm_vmware, :storage => storage, :ext_management_system => ems) }
    let(:vm_retired)  { FactoryBot.create(:vm_vmware, :retired => true, :storage => storage, :ext_management_system => ems) }
    let(:vm_orphaned) { FactoryBot.create(:vm_vmware, :storage => storage) }
    let(:vm_archived) { FactoryBot.create(:vm_vmware) }

    it 'returns true for active vm' do
      expect(vm_active.reconfigurable?).to be_truthy
    end

    it 'returns false for orphaned vm' do
      expect(vm_orphaned.reconfigurable?).to be_falsey
    end

    it 'returns false for retired vm' do
      expect(vm_retired.reconfigurable?).to be_falsey
    end

    it 'returns false for archived vm' do
      expect(vm_archived.reconfigurable?).to be_falsey
    end
  end

  context "#max_total_vcpus" do
    before do
      @host = FactoryBot.create(:host, :hardware => FactoryBot.create(:hardware, :cpu_total_cores => 160))
      vm.host = @host
    end
    subject { vm.max_total_vcpus }

    context "vitural_hw_version" do
      it "07" do
        expect(subject).to eq(8)
      end

      it "08" do
        vm.hardware.update(:virtual_hw_version => "08")
        expect(subject).to eq(32)
      end

      it "09" do
        vm.hardware.update(:virtual_hw_version => "09")
        expect(subject).to eq(64)
      end

      it "10" do
        vm.hardware.update(:virtual_hw_version => "10")
        expect(subject).to eq(64)
      end

      it "11" do
        vm.hardware.update(:virtual_hw_version => "11")
        expect(subject).to eq(128)
      end
    end

    it "small host logical cpus" do
      @host.hardware.update(:cpu_total_cores => 4)
      expect(subject).to eq(4)
    end

    it "big host logical cpus" do
      expect(subject).to eq(8)
    end

    it 'when no host' do
      vm.update(:host_id => nil)
      expect(subject).to eq(vm.max_total_vcpus_by_version)
    end
  end

  context "#build_config_spec" do
    let(:options ) { {:vm_memory => '1024', :number_of_cpus => '8', :cores_per_socket => '2'} }
    subject { vm.build_config_spec(options) }

    it "memoryMB" do
      expect(subject["memoryMB"]).to eq(1024)
    end

    it "numCPUs" do
      expect(subject["numCPUs"]).to eq(8)
    end

    context "numCoresPerSocket" do
      it "vm_vmware virtual_hw_version = 07" do
        expect(subject["extraConfig"]).to eq([{"key" => "cpuid.coresPerSocket", "value" => "2"}])
      end

      it "vm_vmware virtual_hw_version != 07" do
        vm.hardware.update(:virtual_hw_version => "08")
        expect(subject["numCoresPerSocket"]).to eq(2)
      end
    end

    context "Running VM" do
      before do
        vm.update(:raw_power_state => 'poweredOn')
      end

      context "with CPU Hot-Add disabled" do
        it "raises an exception when adding CPUs" do
          options[:number_of_cpus] = '16'
          expect { subject }.to raise_error(MiqException::MiqVmError, "CPU Hot-Add not enabled")
        end
      end

      context "with CPU Hot-Add enabled" do
        before do
          vm.update(:cpu_hot_add_enabled    => true,
                               :cpu_hot_remove_enabled => false)
        end

        it "raises an exception when removing CPUs" do
          options[:number_of_cpus] = '2'

          expect { subject }.to raise_error(MiqException::MiqVmError, "Cannot remove CPUs from a running VM")
        end

        it "raises an exception when changing numCoresPerSocket" do
          options[:cores_per_socket] = 4

          expect { subject }.to raise_error(MiqException::MiqVmError, "Cannot change CPU cores per socket on a running VM")
        end

        it "sets numCPUs correctly" do
          options[:number_of_cpus] = '16'

          expect(subject["numCPUs"]).to eq(16)
        end
      end

      context "with Memory Hot-Add disabled" do
        it "raises an exception when adding RAM" do
          options[:vm_memory] = '2048'

          expect { subject }.to raise_error(MiqException::MiqVmError, "Memory Hot-Add not enabled")
        end
      end

      context "with Memory Hot-Add enabled" do
        before do
          vm.update(:memory_hot_add_enabled => true,
                               :memory_hot_add_limit   => 2048)
        end

        it "raises an exception when removing memory" do
          options[:vm_memory] = '512'

          expect { subject }.to raise_error(MiqException::MiqVmError, "Cannot remove memory from a running VM")
        end

        it "raises an exception if adding more than the memory limit" do
          options[:vm_memory] = '4096'

          expect { subject }.to raise_error(MiqException::MiqVmError, "Cannot add more than 2048MB to this VM")
        end

        it "sets memoryMB correctly" do
          options[:vm_memory] = '1536'

          expect(subject["memoryMB"]).to eq(1536)
        end
      end
    end
  end

  context "#add_disk_config_spec" do
    before do
      @vmcs    = VimHash.new("VirtualMachineConfigSpec")
      @options = {:disk_size_in_mb => 10, :controller_key => 1000, :unit_number => 2}
    end
    subject { vm.add_disk_config_spec(@vmcs, @options).first }

    it 'required option' do
      @options.delete(:disk_size_in_mb)
      expect { subject }.to raise_error(RuntimeError, /Disk size is required to add a new disk./)
    end

    it 'with default options' do
      expect(subject["operation"]).to                          eq("add")
      expect(subject["fileOperation"]).to                      eq("create")
      expect(subject.fetch_path("device", "controllerKey")).to eq(1000)
      expect(subject.fetch_path("device", "unitNumber")).to    eq(2)
      expect(subject.fetch_path("device", "capacityInKB")).to  eq(10 * 1024)
      expect(subject.fetch_path("device", "backing", "thinProvisioned")).to be_truthy
      expect(subject.fetch_path("device", "backing", "diskMode")).to        eq("persistent")
      expect(subject.fetch_path("device", "backing", "fileName")).to        eq("[#{vm.storage.name}]")
    end

    it 'with user inputs' do
      @options[:thin_provisioned] = false
      @options[:dependent]        = false
      @options[:persistent]       = false
      @options[:disk_name]        = 'test_disk'

      expect(subject.fetch_path("device", "backing", "thinProvisioned")).to be_falsey
      expect(subject.fetch_path("device", "backing", "diskMode")).to        eq("independent_nonpersistent")
      expect(subject.fetch_path("device", "backing", "fileName")).to        eq("[#{vm.storage.name}]")
    end

    it 'with invalid diskMode' do
      @options[:dependent]  = true
      @options[:persistent] = false

      expect { subject }.to raise_error(MiqException::MiqVmError, "Disk mode nonpersistent is not supported for virtual disk")
    end
  end

  context '#remove_disk_config_spec' do
    before do
      @vmcs     = VimHash.new("VirtualMachineConfigSpec")
      @vim_obj  = double('provider object', :getDeviceKeysByBacking => [900, 1])
      @filename = "[datastore] vm_name/abc.vmdk"
      @options  = {:disk_name => @filename}
      @hardware = {
        "device"   => [],
        "memoryMB" => vm.hardware.memory_mb,
        "numCPU"   => vm.hardware.cpu_total_cores
      }
    end
    subject { vm.remove_disk_config_spec(@vim_obj, @vmcs, @hardware, @options).first }

    it 'with default options' do
      expect(subject["operation"]).to eq("remove")
      device = subject["device"]
      expect(device["controllerKey"]).to  eq(900)
      expect(device["capacityInKB"]).to   eq(0)
      expect(device["key"]).to            eq(1)
    end

    it 'keep backfile' do
      expect(subject["fileOperation"]).to be_nil
    end

    it 'delete backfile' do
      @options[:delete_backing] = true
      expect(subject["fileOperation"]).to eq("destroy")
    end
  end

  context '#resize_disk_config_spec' do
    let(:vmcs)      { VimHash.new("VirtualMachineConfigSpec") }
    let(:filename)  { '[datastore] vm_name/abc.vmdk' }
    let(:hardware)  { VimHash.new("VirtualHardware") }
    let(:disk_size) { 2048 }
    let(:device)    do
      VimHash.new("VirtualDisk").tap do |disk|
        disk.key           = 2_000
        disk.capacityInKB  = 1_048_576
        disk.controllerKey = 1_000
        disk.unitNumber    = 0
        disk.backing       = VimHash.new("VirtualDiskFlatVer2BackingInfo").tap do |backing|
          backing.fileName = filename
        end
      end
    end
    let(:vim_obj)   { double('provider object', :getDeviceByBacking => device) }
    let(:options)   { {:disk_name => filename, :disk_size_in_mb => disk_size} }
    subject         { vm.resize_disk_config_spec(vim_obj, vmcs, hardware, options) }

    context 'with no disk name passed' do
      let(:filename) { nil }
      it 'raises an exception' do
        expect { subject }.to raise_error(RuntimeError, /resize_disk_config_spec: disk filename is required./)
      end
    end

    context 'with no disks' do
      let(:device) { nil }
      it 'raises an exception with no disks' do
        expect { subject }.to raise_error(RuntimeError, /resize_disk_config_spec: no virtual device associated with: /)
      end
    end

    context 'with new disk size smaller than existing disk' do
      let(:disk_size) { 512 }

      it 'raises an exception' do
        expect { subject }.to raise_error(RuntimeError, /resize_disk_config_spec: decrease size is not supported for: /)
      end
    end

    context 'with new disk size greater than existing disk' do
      it 'returns the device config spec' do
        device_change = subject.first
        expect(device_change["device"]["capacityInKB"]).to eq(disk_size * 1024)
      end
    end
  end

  context '#backing_filename' do
    subject { vm.backing_filename }

    it 'no primary disk' do
      expect(subject).to eq("[#{vm.storage.name}]")
    end

    it 'with primary disk' do
      datastore = FactoryBot.create(:storage, :name => "test_datastore")
      FactoryBot.create(
        :disk,
        :device_type => "disk",
        :storage     => datastore,
        :hardware_id => vm.hardware.id
      )
      expect(subject).to eq("[#{datastore.name}]")
    end
  end

  context '#disk_mode' do
    subject { vm.disk_mode(@dependent, @persistent) }

    it 'persistent' do
      @dependent, @persistent = [true, true]
      expect(subject).to eq('persistent')
    end

    it 'nonpersistent' do
      @dependent, @persistent = [true, false]
      expect(subject).to eq('nonpersistent')
    end

    it 'independent_persistent' do
      @dependent, @persistent = [false, true]
      expect(subject).to eq('independent_persistent')
    end

    it 'independent_nonpersistent' do
      @dependent, @persistent = [false, false]
      expect(subject).to eq('independent_nonpersistent')
    end
  end

  context '#add_disks' do
    let(:vim)  { double("vim object") }
    let(:vmcs) { VimHash.new("VirtualMachineConfigSpec") }
    let(:hardware) do
      {
        "device"   => [],
        "memoryMB" => vm.hardware.memory_mb,
        "numCPU"   => vm.hardware.cpu_total_cores
      }
    end

    context 'add 1 disk' do
      let(:disk) { {:disk_size_in_mb => 1024} }

      it 'with valid controller key' do
        allow(vim).to receive(:available_scsi_units).and_return([[1000, 1]])
        allow(vim).to receive(:available_scsi_buses).and_return([1, 2, 3])

        expect(vm).not_to receive(:add_scsi_controller)
        expect(vm).to receive(:add_disk_config_spec).with(vmcs, disk).once
        vm.add_disks(vim, vmcs, hardware, [disk])
      end

      it 'with no controller key' do
        allow(vim).to receive(:available_scsi_units).and_return([])
        allow(vim).to receive(:available_scsi_buses).and_return([0, 1, 2, 3])

        expect(vm).to receive(:add_scsi_controller).with(vim, vmcs, hardware, nil, 0, -99).once
        expect(vm).to receive(:add_disk_config_spec).with(vmcs, disk).once
        vm.add_disks(vim, vmcs, hardware, [disk])
      end

      it 'with a defined new controller type' do
        sas_controller = 'VirtualLsiLogicSASController'
        disk[:new_controller_type] = sas_controller

        allow(vim).to receive(:available_scsi_units).and_return([])
        allow(vim).to receive(:available_scsi_buses).and_return([0, 1, 2, 3])

        expect(vm).to receive(:add_scsi_controller).with(vim, vmcs, hardware, sas_controller, 0, -99).once
        expect(vm).to receive(:add_disk_config_spec).with(vmcs, disk).once
        vm.add_disks(vim, vmcs, hardware, [disk])
      end
    end

    context 'add 2 disks' do
      let(:disks) { [{:disk_size_in_mb => 1024}, {:disk_size_in_mb => 2048}] }

      it 'with 2 free controller units' do
        allow(vim).to receive(:available_scsi_units).and_return([[1000, 14], [1000, 15]])
        allow(vim).to receive(:available_scsi_buses).and_return([1, 2, 3])

        expected_disks = [
          disks[0].merge(:controller_key => 1000, :unit_number => 14),
          disks[1].merge(:controller_key => 1000, :unit_number => 15)
        ]

        expect(vm).not_to receive(:add_scsi_controllers)
        expect(vm).to receive(:add_disk_config_spec).with(vmcs, expected_disks[0]).once
        expect(vm).to receive(:add_disk_config_spec).with(vmcs, expected_disks[1]).once

        vm.add_disks(vim, vmcs, hardware, disks)
      end

      it 'with 2 non-consecutive controller units' do
        allow(vim).to receive(:available_scsi_units).and_return([[1000, 1], [1000, 3]])
        allow(vim).to receive(:available_scsi_buses).and_return([1, 2, 3])

        expected_disks = [
          disks[0].merge(:controller_key => 1000, :unit_number => 1),
          disks[1].merge(:controller_key => 1000, :unit_number => 3)
        ]

        expect(vm).not_to receive(:add_scsi_controllers)
        expect(vm).to receive(:add_disk_config_spec).with(vmcs, expected_disks[0]).once
        expect(vm).to receive(:add_disk_config_spec).with(vmcs, expected_disks[1]).once

        vm.add_disks(vim, vmcs, hardware, disks)
      end

      it 'with 1 free controller unit' do
        allow(vim).to receive(:available_scsi_units).and_return([[1000, 15]])
        allow(vim).to receive(:available_scsi_buses).and_return([1, 2, 3])

        expected_disks = [
          disks[0].merge(:controller_key => 1000, :unit_number => 15),
          disks[1].merge(:controller_key => -99,  :unit_number => 0)
        ]

        expect(vm).to receive(:add_scsi_controller).with(vim, vmcs, hardware, nil, 1, -99).once
        expect(vm).to receive(:add_disk_config_spec).with(vmcs, expected_disks[0]).once
        expect(vm).to receive(:add_disk_config_spec).with(vmcs, expected_disks[1]).once

        vm.add_disks(vim, vmcs, hardware, disks)
      end

      it 'with 1 free unit on second controller' do
        allow(vim).to receive(:available_scsi_units).and_return([[1001, 15]])
        allow(vim).to receive(:available_scsi_buses).and_return([2, 3])

        expected_disks = [
          disks[0].merge(:controller_key => 1001, :unit_number => 15),
          disks[1].merge(:controller_key => -99,  :unit_number => 0)
        ]

        expect(vm).to receive(:add_scsi_controller).with(vim, vmcs, hardware, nil, 2, -99).once
        expect(vm).to receive(:add_disk_config_spec).with(vmcs, expected_disks[0]).once
        expect(vm).to receive(:add_disk_config_spec).with(vmcs, expected_disks[1]).once

        vm.add_disks(vim, vmcs, hardware, disks)
      end

      it 'with 1 free unit on the last scsi controller' do
        allow(vim).to receive(:available_scsi_units).and_return([[1003, 15]])
        allow(vim).to receive(:available_scsi_buses).and_return([])

        expected_disk = disks[0].merge(:controller_key => 1003, :unit_number => 15)

        expect(vm).not_to receive(:add_scsi_controller)
        expect(vm).to receive(:add_disk_config_spec).with(vmcs, expected_disk).once

        vm.add_disks(vim, vmcs, hardware, disks)
      end
    end

    context '#add_scsi_controller' do
      let(:disk)           { {:disk_size_in_mb => 1024} }
      let(:lsi_scsi_ctrlr) { VimHash.new("VirtualLsiLogicController") { |ctrlr| ctrlr.key = 1000 } }
      let(:pv_scsi_ctrlr)  { VimHash.new("ParaVirtualSCSIController") { |ctrlr| ctrlr.key = 1001 } }

      context 'with no existing controllers' do
        before do
          allow(vim).to receive(:getScsiControllers).and_return([])
          allow(vim).to receive(:available_scsi_units).and_return([])
          allow(vim).to receive(:available_scsi_buses).and_return([0, 1, 2, 3])
        end

        it 'adds an LSI Logic Controller' do
          vm.add_disks(vim, vmcs, hardware, [disk])
          expect(vmcs.deviceChange.count).to eq(2)

          new_ctrlr = vmcs.deviceChange.first.device
          expect(new_ctrlr.xsiType).to eq('VirtualLsiLogicController')
        end
      end

      context 'with an existing PV SCSI Controller' do
        before do
          allow(vim).to receive(:getScsiControllers).and_return([pv_scsi_ctrlr])
          allow(vim).to receive(:available_scsi_units).and_return([])
          allow(vim).to receive(:available_scsi_buses).and_return([1, 2, 3])
        end

        it 'adds a new pv scsi controller' do
          vm.add_disks(vim, vmcs, hardware, [disk])
          expect(vmcs.deviceChange.count).to eq(2)

          new_ctrlr = vmcs.deviceChange.first.device
          expect(new_ctrlr.xsiType).to eq('ParaVirtualSCSIController')
        end
      end

      context 'with two existing controllers' do
        before do
          allow(vim).to receive(:getScsiControllers).and_return([lsi_scsi_ctrlr, pv_scsi_ctrlr])
          allow(vim).to receive(:available_scsi_units).and_return([])
          allow(vim).to receive(:available_scsi_buses).and_return([2, 3])
        end

        it 'adds a new controller with the same type as the last one' do
          vm.add_disks(vim, vmcs, hardware, [disk])
          expect(vmcs.deviceChange.count).to eq(2)

          new_ctrlr = vmcs.deviceChange.first.device
          expect(new_ctrlr.xsiType).to eq('ParaVirtualSCSIController')
        end
      end
    end
  end

  context "#connect_cdroms" do
    let(:vim_obj) { double("MiqVimVm obj") }
    let(:vmcs) { VimHash.new("VirtualMachineConfigSpec") }
    let(:options) do
      [
        {
          :device_name => "CD/DVD drive 1",
          :filename    => "[NFS Share] ISO/centos.iso",
          :storage_id  => storage.id,
        }
      ]
    end
    let(:subject) { vm.connect_cdroms(vim_obj, vmcs, hardware, options) }

    context "with no virtual cdroms" do
      let(:hardware) { {"device" => []} }

      before do
        expect(vim_obj).to receive(:getDeviceByLabel).and_return(nil)
      end

      it "raises an exception when the cdrom can't be found" do
        expect { subject }.to raise_error('connect_cdrom_config_spec: no virtual device associated with: CD/DVD drive 1')
      end
    end

    context "with one virtual cdrom" do
      let(:hardware) { {"device" => [virtual_cdrom]} }
      let(:virtual_cdrom) do
        VimHash.new("VirtualCdrom").tap do |cdrom|
          cdrom.backing       = VimHash.new("VirtualCdromRemoteAtapiBackingInfo")
          cdrom.connectable   = VimHash.new("VirtualDeviceConnectInfo")
          cdrom.controllerKey = 15_000
          cdrom.deviceInfo    = VimHash.new("Description") do |description|
            description.label = "CD/DVD drive 1"
          end
          cdrom.key           = 16_000
          cdrom.unitNumber    = 0
        end
      end

      before do
        expect(vim_obj).to receive(:getDeviceByLabel).and_return(virtual_cdrom)
      end

      it "sets the device backing" do
        subject

        expect(vmcs.deviceChange.count).to eq(1)

        device_change = vmcs.deviceChange.first.device
        expect(device_change.backing.xsiType).to  eq("VirtualCdromIsoBackingInfo")
        expect(device_change.backing.fileName).to eq(options.first[:filename])
      end
    end
  end

  context "#disconnect_cdroms" do
    let(:vim_obj) { double("MiqVimVm obj") }
    let(:vmcs) { VimHash.new("VirtualMachineConfigSpec") }
    let(:hardware) { {"device" => [virtual_cdrom]} }
    let(:options) { [{:device_name => "CD/DVD drive 1"}] }
    let(:subject) { vm.disconnect_cdroms(vim_obj, vmcs, hardware, options) }
    let(:virtual_cdrom) do
      VimHash.new("VirtualCdrom").tap do |cdrom|
        cdrom.backing       = VimHash.new("VirtualCdromIsoBackingInfo")
        cdrom.connectable   = VimHash.new("VirtualDeviceConnectInfo")
        cdrom.controllerKey = 15_000
        cdrom.deviceInfo    = VimHash.new("Description") do |description|
          description.label = "CD/DVD drive 1"
        end
        cdrom.key           = 16_000
        cdrom.unitNumber    = 0
      end
    end

    before do
      expect(vim_obj).to receive(:getDeviceByLabel).and_return(virtual_cdrom)
    end

    it "sets the device backing" do
      subject

      expect(vmcs.deviceChange.count).to eq(1)
      device_change = vmcs.deviceChange.first.device
      expect(device_change.backing.xsiType).to eq("VirtualCdromRemoteAtapiBackingInfo")
      expect(device_change.backing.deviceName).to eq("")
    end
  end
end
