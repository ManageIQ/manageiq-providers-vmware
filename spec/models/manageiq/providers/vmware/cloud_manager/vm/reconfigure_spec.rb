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

  it '#reconfigurable?' do
    expect(vm.reconfigurable?).to be_truthy
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
  end
end
