describe ManageIQ::Providers::Vmware::CloudManager::Refresher do
  ALL_REFRESH_SETTINGS = [
    {
      :inventory_object_refresh => false
    },
    {
      :inventory_object_refresh => true,
      :inventory_collections    => {
        :saver_strategy => :default,
      },
    }, {
      :inventory_object_refresh => true,
      :inventory_collections    => {
        :saver_strategy => :batch,
        :use_ar_object  => true,
      },
    }, {
      :inventory_object_refresh => true,
      :inventory_collections    => {
        :saver_strategy => :batch,
        :use_ar_object  => false,
      },
    }, {
      :inventory_object_saving_strategy => :recursive,
      :inventory_object_refresh         => true
    }
  ].freeze

  before do
    @host = Rails.application.secrets.vmware_cloud.try(:[], 'host') || 'vmwarecloudhost'
    host_uri = URI.parse("https://#{@host}")

    @hostname = host_uri.host
    @port = host_uri.port == 443 ? nil : host_uri.port

    _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
    @ems = FactoryBot.create(
      :ems_vmware_cloud,
      :zone        => zone,
      :hostname    => @hostname,
      :port        => @port,
      :api_version => '5.5'
    )

    @userid = Rails.application.secrets.vmware_cloud.try(:[], 'userid') || 'VMWARE_CLOUD_USERID'
    @password = Rails.application.secrets.vmware_cloud.try(:[], 'password') || 'VMWARE_CLOUD_PASSWORD'

    VCR.configure do |c|
      # workaround for escaping host in spec/spec_helper.rb
      c.before_playback do |interaction|
        interaction.filter!(CGI.escape(@host), @host)
        interaction.filter!(CGI.escape('VMWARE_CLOUD_HOST'), 'vmwarecloudhost')
      end

      c.filter_sensitive_data('VMWARE_CLOUD_AUTHORIZATION') { Base64.encode64("#{@userid}:#{@password}").chomp }
    end

    cred = {
      :userid   => @userid,
      :password => @password
    }

    @ems.authentications << FactoryBot.create(:authentication, cred)
  end

  it '.ems_type' do
    expect(described_class.ems_type).to eq(:vmware_cloud)
  end

  ALL_REFRESH_SETTINGS.each do |settings|
    context "with settings #{settings}" do
      before(:each) do
        stub_settings_merge(
          :ems_refresh => {
            :vmware_cloud => settings
          }
        )
      end

      it 'will perform a full refresh' do
        2.times do
          @ems.reload
          VCR.use_cassette(described_class.name.underscore, :allow_unused_http_interactions => true) do
            EmsRefresh.refresh(@ems)
          end
          @ems.reload

          assert_specific_orchestration_stack
          assert_table_counts
          assert_ems
          assert_specific_vdc
          assert_specific_template
          assert_specific_vm_powered_on
          assert_specific_vm_powered_off
          assert_specific_orchestration_template
          assert_specific_vm_with_snapshot
        end
      end
    end
  end

  def assert_table_counts
    expect(ExtManagementSystem.count).to eq(2) # cloud_manager + network_manager
    expect(Flavor.count).to eq(0)
    expect(AvailabilityZone.count).to eq(1)
    expect(FloatingIp.count).to eq(0)
    expect(AuthPrivateKey.count).to eq(0)
    expect(CloudNetwork.count).to eq(0)
    expect(CloudSubnet.count).to eq(0)
    expect(OrchestrationTemplate.count).to eq(1)
    expect(OrchestrationStack.count).to eq(3)
    expect(OrchestrationStackParameter.count).to eq(0)
    expect(OrchestrationStackOutput.count).to eq(0)
    expect(OrchestrationStackResource.count).to eq(0)
    expect(SecurityGroup.count).to eq(0)
    expect(FirewallRule.count).to eq(0)
    expect(VmOrTemplate.count).to eq(4)
    expect(Vm.count).to eq(3)
    expect(MiqTemplate.count).to eq(1)

    expect(CustomAttribute.count).to eq(0)
    expect(Disk.count).to eq(3)
    expect(GuestDevice.count).to eq(0)
    expect(Hardware.count).to eq(3)
    expect(OperatingSystem.count).to eq(3)
    expect(Snapshot.count).to eq(1)
    expect(SystemService.count).to eq(0)

    expect(Relationship.count).to eq(0)
    expect(MiqQueue.count).to eq(5)
  end

  def assert_ems
    expect(@ems).to have_attributes(
      :api_version => '5.5',
      :uid_ems     => nil
    )

    expect(@ems.flavors.size).to eq(0)
    expect(@ems.availability_zones.size).to eq(1)
    expect(@ems.floating_ips.count).to eq(0)
    expect(@ems.key_pairs.size).to eq(0)
    expect(@ems.cloud_networks.count).to eq(0)
    expect(@ems.security_groups.count).to eq(0)
    expect(@ems.vms_and_templates.size).to eq(4)
    expect(@ems.vms.size).to eq(3)
    expect(@ems.miq_templates.size).to eq(1)
    expect(@ems.orchestration_stacks.size).to eq(3)
    expect(@ems.orchestration_templates.size).to eq(1)

    expect(@ems.direct_orchestration_stacks.size).to eq(3)
  end

  def assert_specific_vdc
    @vdc = ManageIQ::Providers::Vmware::CloudManager::AvailabilityZone.where(:name => 'MIQ Devel VDC').first
    expect(@vdc).to have_attributes(
      :ems_id  => @ems.id,
      :name    => 'MIQ Devel VDC',
      :ems_ref => '0946827a-1a9e-4b9f-8ea3-732b3afe47c6',
      :type    => 'ManageIQ::Providers::Vmware::CloudManager::AvailabilityZone'
    )
  end

  def assert_specific_template
    @template = ManageIQ::Providers::Vmware::CloudManager::Template.where(:name => 'spec2-vm1').first
    expect(@template).not_to be_nil
    expect(@template).to have_attributes(
      :template              => true,
      :ems_ref               => 'vm-ac90bd58-3bc4-47a5-bc8c-f1c8f5c468b6',
      :ems_ref_obj           => nil,
      :uid_ems               => 'vm-ac90bd58-3bc4-47a5-bc8c-f1c8f5c468b6',
      :vendor                => 'vmware',
      :power_state           => 'never',
      :publicly_available    => false,
      :location              => 'vm-ac90bd58-3bc4-47a5-bc8c-f1c8f5c468b6',
      :tools_status          => nil,
      :boot_time             => nil,
      :standby_action        => nil,
      :connection_state      => "connected",
      :cpu_affinity          => nil,
      :memory_reserve        => nil,
      :memory_reserve_expand => nil,
      :memory_limit          => nil,
      :memory_shares         => nil,
      :memory_shares_level   => nil,
      :cpu_reserve           => nil,
      :cpu_reserve_expand    => nil,
      :cpu_limit             => nil,
      :cpu_shares            => nil,
      :cpu_shares_level      => nil
    )

    expect(@template.ext_management_system).to eq(@ems)
    expect(@template.operating_system).to be_nil
    expect(@template.custom_attributes.size).to eq(0)
    expect(@template.snapshots.size).to eq(0)
  end

  def assert_specific_vm_powered_on
    v = ManageIQ::Providers::Vmware::CloudManager::Vm.find_by(:name => 'spec1-vm1')
    expect(v).to have_attributes(
      :template               => false,
      :ems_ref                => 'vm-84faa107-c0b9-4a21-adc5-b17e0c5355a2',
      :ems_ref_obj            => nil,
      :uid_ems                => 'vm-84faa107-c0b9-4a21-adc5-b17e0c5355a2',
      :vendor                 => 'vmware',
      :power_state            => 'on',
      :location               => 'vm-84faa107-c0b9-4a21-adc5-b17e0c5355a2',
      :tools_status           => nil,
      :boot_time              => nil,
      :standby_action         => nil,
      :connection_state       => "connected",
      :cpu_affinity           => nil,
      :memory_reserve         => nil,
      :memory_reserve_expand  => nil,
      :memory_limit           => nil,
      :memory_shares          => nil,
      :memory_shares_level    => nil,
      :memory_hot_add_enabled => true,
      :cpu_reserve            => nil,
      :cpu_reserve_expand     => nil,
      :cpu_limit              => nil,
      :cpu_shares             => nil,
      :cpu_shares_level       => nil,
      :cpu_hot_add_enabled    => true,
      :hostname               => 'spec1-vm1'
    )

    expect(v.ext_management_system).to eq(@ems)
    expect(v.orchestration_stack).to eq(@orchestration_stack1)
    expect(v.availability_zone).to be_nil
    expect(v.floating_ip).to be_nil
    expect(v.key_pairs.size).to eq(0)
    expect(v.cloud_network).to be_nil
    expect(v.cloud_subnet).to be_nil
    expect(v.security_groups.size).to eq(0)

    expect(v.operating_system).to have_attributes(
      :product_name => 'Microsoft Windows Server 2016 (64-bit)',
    )
    expect(v.custom_attributes.size).to eq(0)
    expect(v.snapshots.size).to eq(0)

    expect(v.hardware).to have_attributes(
      :config_version       => nil,
      :virtual_hw_version   => nil,
      :guest_os             => 'Microsoft Windows Server 2016 (64-bit)',
      :guest_os_full_name   => 'Microsoft Windows Server 2016 (64-bit)',
      :cpu_sockets          => 2,
      :bios                 => nil,
      :bios_location        => nil,
      :time_sync            => nil,
      :annotation           => nil,
      :memory_mb            => 512,
      :host_id              => nil,
      :cpu_speed            => nil,
      :cpu_type             => nil,
      :size_on_disk         => nil,
      :manufacturer         => '',
      :model                => '',
      :number_of_nics       => nil,
      :cpu_usage            => nil,
      :memory_usage         => nil,
      :cpu_cores_per_socket => 4,
      :cpu_total_cores      => 8,
      :vmotion_enabled      => nil,
      :disk_free_space      => nil,
      :disk_capacity        => 10_737_418_240,
      :memory_console       => nil,
      :bitness              => 64,
      :virtualization_type  => nil,
      :root_device_type     => nil,
    )

    expect(v.hardware.disks.size).to eq(1)
    expect(v.hardware.disks.first).to have_attributes(
      :device_name     => 'Disk 0',
      :device_type     => 'disk',
      :disk_type       => 'LSI Logic SAS SCSI',
      :controller_type => 'LSI Logic SAS SCSI controller',
      :size            => 10_737_418_240,
      :location        => 'vm-84faa107-c0b9-4a21-adc5-b17e0c5355a2/0/0/2000',
      :filename        => 'Disk 0'
    )
    expect(v.hardware.guest_devices.size).to eq(0)
    expect(v.hardware.nics.size).to eq(0)
  end

  def assert_specific_vm_powered_off
    v = ManageIQ::Providers::Vmware::CloudManager::Vm.find_by(:name => 'spec2-vm1')
    expect(v).to have_attributes(
      :template              => false,
      :ems_ref               => 'vm-aaf94123-cbf9-4de9-841c-41dd41ac310e',
      :ems_ref_obj           => nil,
      :uid_ems               => 'vm-aaf94123-cbf9-4de9-841c-41dd41ac310e',
      :vendor                => 'vmware',
      :power_state           => 'off',
      :location              => 'vm-aaf94123-cbf9-4de9-841c-41dd41ac310e',
      :tools_status          => nil,
      :boot_time             => nil,
      :standby_action        => nil,
      :connection_state      => "connected",
      :cpu_affinity          => nil,
      :memory_reserve        => nil,
      :memory_reserve_expand => nil,
      :memory_limit          => nil,
      :memory_shares         => nil,
      :memory_shares_level   => nil,
      :cpu_reserve           => nil,
      :cpu_reserve_expand    => nil,
      :cpu_limit             => nil,
      :cpu_shares            => nil,
      :cpu_shares_level      => nil,
      :hostname              => 'spec2-vm1'
    )

    expect(v.ext_management_system).to eq(@ems)
    expect(v.orchestration_stack).to eq(@orchestration_stack2)
    expect(v.availability_zone).to be_nil
    expect(v.floating_ip).to be_nil
    expect(v.key_pairs.size).to eq(0)
    expect(v.cloud_network).to be_nil
    expect(v.cloud_subnet).to be_nil
    expect(v.security_groups.size).to eq(0)

    expect(v.operating_system).to have_attributes(
      :product_name => 'VMware Photon OS (64-bit)',
    )

    expect(v.custom_attributes.size).to eq(0)
    expect(v.snapshots.size).to eq(1)

    expect(v.hardware).to have_attributes(
      :config_version       => nil,
      :virtual_hw_version   => nil,
      :guest_os             => 'VMware Photon OS (64-bit)',
      :guest_os_full_name   => 'VMware Photon OS (64-bit)',
      :cpu_sockets          => 1,
      :bios                 => nil,
      :bios_location        => nil,
      :time_sync            => nil,
      :annotation           => nil,
      :memory_mb            => 256,
      :host_id              => nil,
      :cpu_speed            => nil,
      :cpu_type             => nil,
      :size_on_disk         => nil,
      :manufacturer         => '',
      :model                => '',
      :number_of_nics       => nil,
      :cpu_usage            => nil,
      :memory_usage         => nil,
      :cpu_cores_per_socket => 1,
      :cpu_total_cores      => 1,
      :vmotion_enabled      => nil,
      :disk_free_space      => nil,
      :disk_capacity        => 17_179_869_184,
      :memory_console       => nil,
      :bitness              => 64,
      :virtualization_type  => nil,
      :root_device_type     => nil,
    )

    expect(v.hardware.disks.size).to eq(1)
    expect(v.hardware.disks.first).to have_attributes(
      :device_name     => 'Disk 0',
      :device_type     => 'disk',
      :disk_type       => 'Paravirtual SCSI',
      :controller_type => 'Paravirtual SCSI controller',
      :size            => 17_179_869_184,
      :location        => 'vm-aaf94123-cbf9-4de9-841c-41dd41ac310e/0/0/2000',
      :filename        => 'Disk 0'
    )
    expect(v.hardware.guest_devices.size).to eq(0)
    expect(v.hardware.nics.size).to eq(0)
  end

  def assert_specific_orchestration_stack
    @orchestration_stack1 = ManageIQ::Providers::Vmware::CloudManager::OrchestrationStack
                            .find_by(:name => 'spec1-vapp')
    @orchestration_stack2 = ManageIQ::Providers::Vmware::CloudManager::OrchestrationStack
                            .find_by(:name => 'spec2-vapp')
    vm1 = ManageIQ::Providers::Vmware::CloudManager::Vm.find_by(:name => 'spec1-vm1')
    vm2 = ManageIQ::Providers::Vmware::CloudManager::Vm.find_by(:name => 'spec2-vm1')

    expect(vm1.orchestration_stack).to eq(@orchestration_stack1)
    expect(vm2.orchestration_stack).to eq(@orchestration_stack2)
  end

  def assert_specific_orchestration_template
    @template = ManageIQ::Providers::Vmware::CloudManager::OrchestrationTemplate.where(:name => 'spec2-vapp-win').first
    expect(@template).not_to be_nil
    expect(@template).to have_attributes(
      :ems_ref   => 'vappTemplate-7d70b225-56a6-4868-8eba-f64a3509c910',
      :orderable => true,
    )

    expect(@template.ems_id).to eq(@ems.id)
    expect(@template.content.include?('ovf:Envelope')).to be_truthy
    expect(@template.md5).to eq('vappTemplate-7d70b225-56a6-4868-8eba-f64a3509c910')
  end

  def assert_specific_vm_with_snapshot
    vm = ManageIQ::Providers::Vmware::CloudManager::Vm.find_by(:name => 'spec2-vm1')

    expect(vm.snapshots.first).not_to be_nil
    expect(vm.snapshots.first).to have_attributes(
      :ems_ref    => 'vm-aaf94123-cbf9-4de9-841c-41dd41ac310e_2018-03-12T15:43:30.986+01:00',
      :uid        => 'vm-aaf94123-cbf9-4de9-841c-41dd41ac310e_2018-03-12T15:43:30.986+01:00',
      :parent_uid => 'vm-aaf94123-cbf9-4de9-841c-41dd41ac310e',
      :name       => 'spec2-vm1 (snapshot)',
      :total_size => 17_179_869_184
    )
    expect(vm.snapshots.first.create_time.to_s).to eq('2018-03-12 14:43:30 UTC')
  end
end
