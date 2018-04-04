describe ManageIQ::Providers::Vmware::CloudManager::OrchestrationTemplate do
  describe ".eligible_manager_types" do
    it "lists the classes of eligible managers" do
      described_class.eligible_manager_types.each do |klass|
        expect(klass <= ManageIQ::Providers::Vmware::CloudManager).to be_truthy
      end
    end
  end

  let(:valid_template) { FactoryGirl.create(:orchestration_template_vmware_cloud_in_xml) }

  describe '#validate_format' do
    it 'passes validation if no content' do
      expect(subject.validate_format).to be_nil
    end

    it 'passes validation with correct OVF content' do
      expect(valid_template.validate_format).to be_nil
    end

    it 'fails validations with incorrect OVF content' do
      template = described_class.new(:content => "Invalid String")
      expect(template.validate_format).not_to be_nil
    end
  end

  describe "OVF content of vApp template" do
    let(:vdc_net1) { FactoryGirl.create(:cloud_network_vmware_vdc, :name => "VDC1", :ems_ref => "vdc_net1") }
    let(:vapp_net) { FactoryGirl.create(:cloud_network_vmware_vapp, :name => "vapp", :ems_ref => "vapp") }
    let(:ems) do
      FactoryGirl.create(:ems_vmware_cloud) do |ems|
        ems.cloud_networks << vdc_net1
        ems.cloud_networks << vapp_net
      end
    end
    let(:orchestration_template) { FactoryGirl.create(:orchestration_template_vmware_cloud_in_xml, :ems_id => ems.id) }

    context "orchestration template OVF file" do
      it "is properly read" do
        expect(orchestration_template.content.include?('ovf:Envelope')).to be_truthy
      end

      it "is parsed using MiqXml" do
        ovf_doc = MiqXml.load(orchestration_template.content)

        expect(ovf_doc).not_to be(nil)
        expect(ovf_doc.root.name).not_to be("Envelope")
      end

      it "contains template ems_ref" do
        ems_ref = described_class.calc_md5(valid_template.content)
        expect(ems_ref).to eq('vappTemplate-05e4d68f-1a4e-40d5-9361-a121c1a67393')
      end
    end

    context "orchestration template tabbed" do
      let(:tabs) { orchestration_template.parameter_groups_tabbed }

      it "creates 3 separate tab data hashes" do
        expect(tabs).not_to be_nil
        expect(tabs.size).to eq(3)

        expect(tabs[0]).not_to be_nil
        expect(tabs[1]).not_to be_nil
        expect(tabs[2]).not_to be_nil
      end

      it "creates Basic information tab" do
        expect(tabs[0][:title]).to eq("Basic Information")
        expect(tabs[0][:stack_group]).not_to be_nil
        expect(tabs[0][:param_group]).not_to be_nil
      end

      it "creates correct vapp_parameter_group" do
        assert_vapp_parameter_group(tabs[0][:param_group])
      end

      it "creates correct deployment options" do
        options = tabs[0][:stack_group]
        assert_deployment_option(options[0], "tenant_name", :OrchestrationParameterAllowedDynamic)
        assert_deployment_option(options[1], "stack_name", :OrchestrationParameterPattern)
        assert_deployment_option(options[2], "availability_zone", :OrchestrationParameterAllowedDynamic)
      end

      it "creates Networks tab" do
        expect(tabs[1][:title]).to eq("Networks")
        expect(tabs[1][:stack_group]).to be_nil
        expect(tabs[1][:param_group]).not_to be_nil
      end

      it "creates correct vapp_net_param_groups" do
        tabs[1][:param_group].each_with_index do |param_group, vapp_net_idx|
          expect(param_group).not_to be_nil

          assert_parameter_group(
            param_group,
            'parent'     => {
              :name      => "parent-#{vapp_net_idx}",
              :label     => 'Parent Network',
              :data_type => 'string',
              :required  => nil
            },
            'fence_mode' => {
              :name      => "fence_mode-#{vapp_net_idx}",
              :label     => 'Fence Mode',
              :data_type => 'string',
              :required  => true
            },
          )
        end
      end

      it "creates VMs tab" do
        expect(tabs[2][:title]).to eq("VMs")
        expect(tabs[2][:stack_group]).to be_nil
        expect(tabs[2][:param_group]).not_to be_nil
      end

      it "creates correct vm_param_groups" do
        tabs[2][:param_group].each_with_index do |param_group, vm_index|
          expect(param_group).not_to be_nil

          assert_parameter_group(
            param_group,
            'instance_name'    => {
              :name      => "instance_name-#{vm_index}",
              :label     => "Instance name",
              :data_type => 'string',
              :required  => true
            },
            'hostname'         => {
              :name      => "hostname-#{vm_index}",
              :label     => "Instance Hostname",
              :data_type => 'string',
              :required  => true
            },
            'cores_per_socket' => {
              :name      => "cores_per_socket-#{vm_index}",
              :label     => "Cores per socket",
              :data_type => 'integer',
              :required  => true
            }
          )
        end
      end
    end

    context "orchestration template" do
      let(:parameter_groups) { orchestration_template.parameter_groups }

      it "creates vapp parameter group for given template" do
        assert_vapp_parameter_group(parameter_groups)
      end

      [
        {
          :vm_name          => 'VM1',
          :vm_id            => 'e9b55b85-640b-462c-9e7a-d18c47a7a5f3',
          :hostname         => 'vm-1',
          :num_cores        => 2,
          :cores_per_socket => 2,
          :memory_mb        => 2048,
          :admin_password   => nil,
          :admin_reset      => false,
          :disks            => [
            { :disk_id => '2000', :disk_address => '0', :size => 16_384 },
            { :disk_id => '2001', :disk_address => '1', :size => 40_960 }
          ],
          :nics             => [{ :idx => '0', :network => nil, :mode => 'DHCP', :ip_address => nil }]
        },
        {
          :vm_name          => 'VM2',
          :vm_id            => '04f85cca-3f8d-43b4-8473-7aa099f95c1b',
          :hostname         => 'vm-2',
          :num_cores        => 2,
          :cores_per_socket => 2,
          :memory_mb        => 4096,
          :admin_password   => nil,
          :admin_reset      => false,
          :disks            => [{ :disk_id => '2000', :disk_address => '0', :size => 40_960 }],
          :nics             => [
            { :idx => '0', :network => 'RedHat Private network 43', :mode => 'MANUAL', :ip_address => '192.168.43.100' },
            { :idx => '1', :network => nil, :mode => 'DHCP', :ip_address => nil }
          ]
        }
      ].each_with_index do |args, vm_idx|
        it "creates specific vm parameter group - #{args[:vm_name]} - for given template" do
          # Group exists.
          vm_group = parameter_groups.detect { |g| g.label == "VM Instance Parameters for '#{args[:vm_name]}'" }
          expect(vm_group).not_to be_nil
          # Group has expected parameters.
          assert_parameter_group(
            vm_group,
            'instance_name'    => {
              :name          => "instance_name-#{vm_idx}",
              :label         => 'Instance name',
              :data_type     => 'string',
              :required      => true,
              :default_value => args[:vm_name],
              :constraints   => []
            },
            'hostname'         => {
              :name          => "hostname-#{vm_idx}",
              :label         => 'Instance Hostname',
              :data_type     => 'string',
              :required      => true,
              :default_value => args[:hostname]
            },
            'num_cores'        => {
              :name          => "num_cores-#{vm_idx}",
              :label         => 'Number of virtual CPUs',
              :data_type     => 'integer',
              :required      => true,
              :default_value => args[:num_cores]
            },
            'cores_per_socket' => {
              :name          => "cores_per_socket-#{vm_idx}",
              :label         => 'Cores per socket',
              :data_type     => 'integer',
              :required      => true,
              :default_value => args[:cores_per_socket]
            },
            'memory_mb'        => {
              :name          => "memory_mb-#{vm_idx}",
              :label         => 'Total memory (MB)',
              :data_type     => 'integer',
              :required      => true,
              :default_value => args[:memory_mb]
            },
            'admin_password'   => {
              :name          => "admin_password-#{vm_idx}",
              :label         => 'Administrator Password',
              :data_type     => 'string',
              :required      => nil,
              :default_value => args[:admin_password]
            },
            'admin_reset'      => {
              :name          => "admin_reset-#{vm_idx}",
              :label         => 'Require password change',
              :data_type     => 'boolean',
              :required      => nil,
              :default_value => args[:admin_reset]
            }
          )
          assert_vm_disks(vm_group, args[:disks], vm_idx)
          assert_vm_nics(vm_group, args[:nics], vm_idx)
          # Group has not extra parameters.
          expect(vm_group.parameters.size).to eq(7 + args[:disks].count + 3 * args[:nics].count)
        end
      end

      [
        {
          :vapp_net_name => 'VM Network',
          :parent        => nil,
          :mode          => 'isolated',
          :subnets       => [{ :gateway => '192.168.254.1', :netmask => '255.255.255.0', :dns1 => '', :dns2 => '' }]
        },
        {
          :vapp_net_name => 'RedHat Private network 43',
          :parent        => nil,
          :mode          => 'bridged',
          :subnets       => [{ :gateway => '192.168.43.1', :netmask => '255.255.255.0', :dns1 => '192.168.43.1', :dns2 => '' }]
        }
      ].each_with_index do |args, vapp_net_idx|
        it "creates specific vapp network parameter group - #{args[:vapp_net_name]} - for given template" do
          # Group exists.
          vapp_net_group = parameter_groups.detect { |g| g.label == "vApp Network Parameters for '#{args[:vapp_net_name]}'" }
          expect(vapp_net_group).not_to be_nil
          # Group has expected parameters.
          assert_parameter_group(
            vapp_net_group,
            'parent'     => {
              :name          => "parent-#{vapp_net_idx}",
              :label         => 'Parent Network',
              :data_type     => 'string',
              :required      => nil,
              :default_value => args[:parent]
            },
            'fence_mode' => {
              :name          => "fence_mode-#{vapp_net_idx}",
              :label         => 'Fence Mode',
              :data_type     => 'string',
              :required      => true,
              :default_value => args[:mode]
            },
          )
          assert_vapp_net_subnets(vapp_net_group, vapp_net_idx, args[:subnets])
          # Group has not extra parameters.
          expect(vapp_net_group.parameters.size).to eq(2 + 4 * args[:subnets].count)
        end
      end
    end
  end

  def assert_vapp_parameter_group(groups)
    group = groups.detect { |g| g.label == 'vApp Parameters' }
    expect(group).not_to be_nil
    expect(group.parameters.size).to eq(2)

    expect(group.parameters[0]).to have_attributes(
      :name          => "deploy",
      :label         => "Deploy vApp",
      :data_type     => "boolean",
      :default_value => true,
    )
    expect(group.parameters[0].constraints.size).to be(1)
    expect(group.parameters[0].constraints[0]).to be_instance_of(OrchestrationTemplate::OrchestrationParameterBoolean)
    expect(group.parameters[1]).to have_attributes(
      :name          => "powerOn",
      :label         => "Power On vApp",
      :data_type     => "boolean",
      :default_value => false,
    )
    expect(group.parameters[1].constraints.size).to be(1)
    expect(group.parameters[1].constraints[0]).to be_instance_of(OrchestrationTemplate::OrchestrationParameterBoolean)
  end

  def assert_parameter_group(group, params)
    params.each do |key, attrs|
      parameter = group.parameters.detect { |p| p.name.start_with?(key) }
      expect(parameter).not_to be_nil
      assert_parameter(parameter, attrs)
    end
  end

  def assert_vm_disks(group, disks, vm_idx)
    disks.each_with_index do |disk, disk_idx|
      disk_name = "disk_mb-#{vm_idx}-#{disk_idx}"
      parameter = group.parameters.detect { |p| p.name == disk_name }
      assert_parameter(
        parameter,
        :name          => disk_name,
        :label         => "Disk #{disk[:disk_address]} (MB)",
        :data_type     => 'integer',
        :required      => true,
        :default_value => disk[:size]
      )
    end
  end

  def assert_vm_nics(vm_group, nics, vm_idx)
    nics.each_with_index do |nic, nic_idx|
      suffix = "#{vm_idx}-#{nic_idx}"
      assert_parameter_group(
        vm_group,
        "nic_network-#{suffix}"    => {
          :name          => "nic_network-#{suffix}",
          :label         => "NIC##{nic[:idx]} Network",
          :data_type     => 'string',
          :required      => nil,
          :default_value => nic[:network]
        },
        "nic_mode-#{suffix}"       => {
          :name          => "nic_mode-#{suffix}",
          :label         => "NIC##{nic[:idx]} Mode",
          :data_type     => 'string',
          :required      => true,
          :default_value => nic[:mode]
        },
        "nic_ip_address-#{suffix}" => {
          :name          => "nic_ip_address-#{suffix}",
          :label         => "NIC##{nic[:idx]} IP Address",
          :data_type     => 'string',
          :required      => nil,
          :default_value => nic[:ip_address]
        },
      )
    end
  end

  def assert_vapp_net_subnets(vapp_net_group, vapp_net_idx, subnets)
    subnets.each_with_index do |subnet, subnet_idx|
      assert_parameter_group(
        vapp_net_group,
        "gateway" => {
          :name          => "gateway-#{vapp_net_idx}-#{subnet_idx}",
          :label         => 'Gateway',
          :data_type     => 'string',
          :required      => nil,
          :default_value => subnet[:gateway]
        }
      )
    end
  end

  def assert_parameter(field, attributes)
    expect(field).to have_attributes(attributes)
  end

  describe '#deployment_options' do
    it do
      options = subject.deployment_options
      assert_deployment_option(options[0], "tenant_name", :OrchestrationParameterAllowedDynamic)
      assert_deployment_option(options[1], "stack_name", :OrchestrationParameterPattern)
      assert_deployment_option(options[2], "availability_zone", :OrchestrationParameterAllowedDynamic)
    end
  end

  def assert_deployment_option(option, name, constraint_type)
    expect(option.name).to eq(name)
    expect(option.constraints[0]).to be_kind_of("OrchestrationTemplate::#{constraint_type}".constantize)
  end
end
