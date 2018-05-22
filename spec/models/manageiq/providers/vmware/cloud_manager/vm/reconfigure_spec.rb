describe ManageIQ::Providers::Vmware::CloudManager::Vm::Reconfigure do
  before { EvmSpecHelper.create_guid_miq_server_zone }
  let(:vm) do
    FactoryGirl.create(
      :vm_vmware_cloud,
      :name                   => 'test_vm',
      :raw_power_state        => 'off',
      :cpu_hot_add_enabled    => true,
      :cpu_hot_remove_enabled => true,
      :memory_hot_add_enabled => true,
      :orchestration_stack    => orchestration_stack,
      :network_ports          => [FactoryGirl.create(:network_port, :name => 'NIC#0')],
      :hardware               => FactoryGirl.create(
        :hardware,
        :cpu4x2,
        :ram1GB,
        :disks => [
          FactoryGirl.create(:disk, :size => 1024, :filename => 'Disk 0', :location => '0/1/2000'),
          FactoryGirl.create(:disk, :size => 2048, :filename => 'Disk 1', :location => '0/2/2001'),
        ]
      )
    )
  end
  let(:orchestration_stack) do
    stack = FactoryGirl.create(:orchestration_stack, :name => 'vapp name')
    FactoryGirl.create(:cloud_network, :name => 'vApp network name (vapp name)', :orchestration_stack => stack)
    stack
  end

  it '#reconfigurable?' do
    expect(vm.reconfigurable?).to be_truthy
  end

  it '.max_cpu_cores_per_socket' do
    expect(vm.max_cpu_cores_per_socket).to eq(128)
  end

  it '.max_total_vcpus' do
    expect(vm.max_total_vcpus).to eq(128)
  end

  it '.max_vcpus' do
    expect(vm.max_vcpus).to eq(128)
  end

  it '.max_memory_mb' do
    expect(vm.max_memory_mb).to eq(4_194_304)
  end

  it '.disk_types' do
    expect(vm.disk_types).to eq(['LSI Logic Parallel SCSI'])
  end

  it '.disk_default_type' do
    expect(vm.disk_default_type).to eq('LSI Logic Parallel SCSI')
  end

  it '.available_adapter_names' do
    expect(vm.available_adapter_names).to eq(['NIC#1', 'NIC#2', 'NIC#3'])
  end

  describe '#build_config_spec' do
    let(:fog_options) { vm.build_config_spec(options) }
    let(:options) do
      {
        :vm_memory        => 16_384,
        :cores_per_socket => 2,
        :number_of_cpus   => 16,
        :disk_add         => [{ :disk_size_in_mb => '4096' }],
        :disk_resize      => [{ :disk_name => 'Disk 0', :disk_size_in_mb => '6144' }],
        :disk_remove      => [{ :disk_name => 'Disk 1' }],
      }
    end

    describe 'no hardware changes' do
      let(:options) { {} }

      it 'fog request optimized' do
        expect(fog_options).to eq({})
      end
    end

    context 'VM off' do
      it 'memory' do
        expect(fog_options[:hardware][:memory][:quantity_mb]).to eq(16_384)
      end

      describe 'cpu' do
        it 'num_cores' do
          expect(fog_options[:hardware][:cpu][:num_cores]).to eq(16)
        end

        it 'cores_per_socket' do
          expect(fog_options[:hardware][:cpu][:cores_per_socket]).to eq(2)
        end
      end

      describe 'disks' do
        it 'add' do
          expect(fog_options[:hardware][:disk]).to include(:capacity_mb => 4096)
        end

        it 'resize' do
          expect(fog_options[:hardware][:disk]).to include(:id => '2000', :capacity_mb => 6144)
        end

        it 'remove' do
          expect(fog_options[:hardware][:disk]).to include(:id => '2001', :capacity_mb => -1)
        end
      end
    end

    context 'VM on' do
      before { vm.raw_power_state = 'on' }

      describe 'memory' do
        it 'add memory' do
          expect(fog_options[:hardware][:memory][:quantity_mb]).to eq(16_384)
        end

        it 'remove memory' do
          options[:vm_memory] = 512
          expect { fog_options }.to raise_error(MiqException::MiqVmError, 'Cannot remove memory from a running VM')
        end
      end

      describe 'cpu' do
        it 'add cores' do
          expect(fog_options[:hardware][:cpu][:num_cores]).to eq(16)
        end

        it 'add cores per socket' do
          expect(fog_options[:hardware][:cpu][:cores_per_socket]).to eq(2)
        end

        it 'remove cores per socket' do
          options[:cores_per_socket] = 1
          expect { fog_options }.to raise_error(MiqException::MiqVmError, 'Cannot change CPU cores per socket on a running VM')
        end
      end

      describe 'hot memory disabled' do
        before { vm.memory_hot_add_enabled = false }

        it 'add memory' do
          expect { fog_options }.to raise_error(MiqException::MiqVmError, 'Memory Hot-Add not enabled')
        end
      end

      describe 'hot cpu add disabled' do
        before { vm.cpu_hot_add_enabled = false }

        it 'add cores' do
          expect { fog_options }.to raise_error(MiqException::MiqVmError, 'CPU Hot-Add not enabled')
        end
      end

      describe 'hot cpu remove disabled' do
        before { vm.cpu_hot_remove_enabled = false }

        it 'remove cores' do
          options[:number_of_cpus] = 1
          expect { fog_options }.to raise_error(MiqException::MiqVmError, 'CPU Hot-Remove not enabled')
        end
      end
    end

    context 'VM with snapshot' do
      before { FactoryGirl.create(:snapshot, :vm_or_template => vm) }

      describe 'disks' do
        it 'resize' do
          expect { fog_options }.to raise_error(MiqException::MiqVmError, 'Cannot resize disk of VM with shapshots')
        end
      end
    end

    describe 'network adapters' do
      let(:options) do
        {
          :network_adapter_add    => [
            { :cloud_network => 'vApp Network Name (vapp name)', :name => 'VM Name#NIC#2' },
            { :cloud_network => nil, :name => 'VM Name#NIC#3' }
          ],
          :network_adapter_remove => [{ :network => { :name => 'VM Name#NIC#0' } }]
        }
      end

      it 'add' do
        expect(fog_options[:networks]).to include(:new_idx => '2', :name => 'vApp Network Name')
      end

      it 'add unhooked' do
        expect(fog_options[:networks]).to include(:new_idx => '3', :name => 'none')
      end

      it 'remove' do
        expect(fog_options[:networks]).to include(:idx => '0', :new_idx => -1)
      end
    end
  end
end
