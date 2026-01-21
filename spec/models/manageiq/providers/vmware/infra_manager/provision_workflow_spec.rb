silence_warnings { ManageIQ::Providers::Vmware::InfraManager::ProvisionWorkflow.const_set("DIALOGS_VIA_AUTOMATE", false) }

describe ManageIQ::Providers::Vmware::InfraManager::ProvisionWorkflow do
  include Spec::Support::WorkflowHelper

  let(:admin)    { FactoryBot.create(:user_with_group) }
  let(:template) { FactoryBot.create(:template_vmware) }

  before do
    EvmSpecHelper.local_miq_server
  end

  describe "#new" do
    it "pass platform attributes to automate" do
      stub_dialog(:get_dialogs)
      assert_automate_dialog_lookup(admin, "infra", "vmware", "get_pre_dialog_name", nil)

      described_class.new({}, admin.userid)
    end

    it "sets up workflow" do
      stub_dialog(:get_pre_dialogs)
      stub_dialog(:get_dialogs)
      workflow = described_class.new(values = {}, admin.userid)

      expect(workflow.requester).to eq(admin)
      expect(values).to eq({})
    end
  end

  describe "#init_from_dialog" do
    let(:user)     { FactoryBot.create(:user_with_email, :role => 'super_administrator', :password => 'x') }
    let(:ems)      { FactoryBot.create(:ems_vmware_with_authentication) }
    let(:template) { FactoryBot.create(:template_vmware, :ext_management_system => ems) }
    let(:req)      { FactoryBot.create(:miq_provision_request, :requester => user, :source => template) }
    let(:options)  { req.get_options.merge(:org_controller=>"vm") }

    subject        { req.workflow(options) }

    before do
      EvmSpecHelper.local_miq_server
      MiqDialog.seed
    end

    it "does not raise an error" do
      expect { subject.init_from_dialog(options) }.to_not raise_error
    end
  end

  describe "#make_request" do
    let(:alt_user) { FactoryBot.create(:user_with_group) }
    it "creates and update a request" do
      stub_dialog(:get_pre_dialogs)
      stub_dialog(:get_dialogs)

      # if running_pre_dialog is set, it will run 'continue_request'
      workflow = described_class.new(values = {:running_pre_dialog => false}, admin)

      expect(AuditEvent).to receive(:success).with(
        :event        => "vm_provision_request_created",
        :target_class => "Vm",
        :userid       => admin.userid,
        :message      => "VM Provisioning requested by <#{admin.userid}> for Vm:#{template.id}"
      )

      # creates a request
      stub_get_next_vm_name

      # the dialogs populate this
      values.merge!(:src_vm_id => template.id, :vm_tags => [])

      request = workflow.make_request(nil, values)

      expect(request).to be_valid
      expect(request).to be_a_kind_of(MiqProvisionRequest)
      expect(request.request_type).to eq("template")
      expect(request.description).to eq("Provision from [#{template.name}] to [New VM]")
      expect(request.requester).to eq(admin)
      expect(request.userid).to eq(admin.userid)
      expect(request.requester_name).to eq(admin.name)

      # updates a request

      stub_get_next_vm_name

      workflow = described_class.new(values, alt_user)

      expect(AuditEvent).to receive(:success).with(
        :event        => "vm_provision_request_updated",
        :target_class => "Vm",
        :userid       => alt_user.userid,
        :message      => "VM Provisioning request updated by <#{alt_user.userid}> for Vm:#{template.id}"
      )
      workflow.make_request(request, values)
    end
  end

  context 'provisioning a VM' do
    let(:workflow) { described_class.new({}, admin.userid) }
    before do
      @ems    = FactoryBot.create(:ems_vmware)
      @host1  = FactoryBot.create(:host_vmware, :ems_id => @ems.id)
      @host2  = FactoryBot.create(:host_vmware, :ems_id => @ems.id)
      @src_vm = FactoryBot.create(:vm_vmware, :host => @host1, :ems_id => @ems.id)
      stub_dialog(:get_dialogs)
      workflow.instance_variable_set(:@values, :vm_tags => [], :src_vm_id => @src_vm.id)
      workflow.instance_variable_set(:@target_resource, nil)
    end

    context '#allowed_storage_profiles' do
      let(:profile) { FactoryBot.create(:storage_profile, :name => 'Gold') }
      it 'when storage_profile selection is set, will not touch storage_profile selection value' do
        selected = []
        workflow.instance_variable_set(:@values, :src_vm_id => template.id, :placement_storage_profile => selected)
        workflow.allowed_storage_profiles
        values = workflow.instance_variable_get(:@values)
        expect(values[:placement_storage_profile]).to eq(selected)
      end

      context 'when storage_profile selection is not set' do
        it 'set storage_profile selection to [nil, nil] if template has no storage_profile' do
          template = FactoryBot.create(:vm_vmware, :host => @host1, :ems_id => @ems.id)
          workflow.instance_variable_set(:@values, :src_vm_id => template.id, :placement_storage_profile => nil)
          workflow.allowed_storage_profiles
          values = workflow.instance_variable_get(:@values)
          expect(values[:placement_storage_profile]).to eq([nil, nil])
        end

        it 'set storage_profile selection to that of template if template has one' do
          template = FactoryBot.create(:vm_vmware, :host => @host1, :ems_id => @ems.id, :storage_profile => profile)
          workflow.instance_variable_set(:@values, :src_vm_id => template.id, :placement_storage_profile => nil)
          workflow.allowed_storage_profiles
          values = workflow.instance_variable_get(:@values)
          expect(values[:placement_storage_profile]).to eq([profile.id, profile.name])
        end
      end

      context 'storage_profile filter' do
        let(:ems) { FactoryBot.create(:ems_vmware, :storage_profiles => [profile]) }
        let(:template) { FactoryBot.create(:vm_vmware, :ems_id => ems.id) }
        it 'list storage_profiles associated with ems' do
          workflow.instance_variable_set(:@values, :src_vm_id => template.id, :src_ems_id => ems.id)
          workflow.allowed_storage_profiles
          filters = workflow.instance_variable_get(:@filters)
          expect(filters[:StorageProfile]).to eq(profile.id => profile.name)
        end
      end
    end

    context '#supports_cloud_init?' do
      let(:ems) { FactoryBot.create(:ems_vmware_with_authentication, :api_version => api_version) }
      let(:template) { FactoryBot.create(:template_vmware, :ext_management_system => ems) }
      before do
        workflow.instance_variable_set(:@values, :src_vm_id => template.id, :src_ems_id => ems.id)
      end

      context "with a 7.0.0 vcenter" do
        let(:api_version) { "7.0.0" }

        it "returns not supported" do
          expect(workflow.supports_cloud_init?).to be_falsey
        end
      end

      context "with a 7.0.3 vcenter" do
        let(:api_version) { "7.0.3" }

        it "returns supported" do
          expect(workflow.supports_cloud_init?).to be_truthy
        end
      end
    end

    context '#allowed_customization_templates' do
      let(:ems) { FactoryBot.create(:ems_vmware_with_authentication, :api_version => api_version) }
      let(:template) { FactoryBot.create(:template_vmware, :ext_management_system => ems) }
      before do
        workflow.instance_variable_set(:@values, :src_vm_id => template.id, :src_ems_id => ems.id)
      end

      context "with a 7.0.0 vcenter" do
        let(:api_version) { "7.0.0" }

        it "returns an empty array" do
          expect(workflow.allowed_customization_templates).to be_empty
        end
      end

      context "with a 7.0.3 vcenter" do
        let(:api_version) { "7.0.3" }

        context "with no cloud-init customizaion templates" do
          let!(:kickstart_template) { FactoryBot.create(:customization_template_kickstart) }

          it "returns an empty array" do
            expect(workflow.allowed_customization_templates).to be_empty
          end
        end

        context "with a cloud-init customization template" do
          let!(:cloud_init_template) { FactoryBot.create(:customization_template_cloud_init) }

          it "returns an the template" do
            expect(workflow.allowed_customization_templates.count).to eq(1)

            template = workflow.allowed_customization_templates.first
            expect(template).to have_attributes(
              :evm_object_class => :CustomizationTemplate,
              :id               => cloud_init_template.id,
              :name             => cloud_init_template.name
            )
          end
        end
      end
    end

    context '#set_on_vm_id_changed' do
      before(:each) do
        workflow.instance_variable_set(:@filters, :Host => {21 => "ESX 6.0"}, :StorageProfile => {1 => "Tag 1"})
        workflow.instance_variable_set(:@values, :src_vm_id => @src_vm.id, :placement_storage_profile => [])
        allow(workflow).to receive(:set_or_default_hardware_field_values).with(@src_vm)
      end
      it 'clears StorageProfile filter' do
        workflow.set_on_vm_id_changed
        filters = workflow.instance_variable_get(:@filters)
        expect(filters).to eq(:Host => {21=>"ESX 6.0"}, :StorageProfile => nil)
      end
      it 'clears :placement_storage_profile value' do
        workflow.set_on_vm_id_changed
        values = workflow.instance_variable_get(:@values)
        expect(values[:placement_storage_profile]).to be_nil
      end
    end

    context 'network selection' do
      let(:s11) { FactoryBot.create(:switch, :name => "A") }
      let(:s12) { FactoryBot.create(:switch, :name => "B") }
      let(:s13) { FactoryBot.create(:switch, :name => "C") }
      let(:s14) { FactoryBot.create(:switch, :name => "DVS14", :shared => true) }
      let(:s15) { FactoryBot.create(:switch, :name => "DVS15", :shared => true) }
      let(:s21) { FactoryBot.create(:switch, :name => "DVS21", :shared => true) }
      let(:s22) { FactoryBot.create(:switch, :name => "DVS22", :shared => true) }

      before do
        @lan11 = FactoryBot.create(:lan, :name => "lan_A",   :switch_id => s11.id)
        @lan12 = FactoryBot.create(:lan, :name => "lan_B",   :switch_id => s12.id)
        @lan13 = FactoryBot.create(:lan, :name => "lan_C",   :switch_id => s13.id)
        @lan14 = FactoryBot.create(:lan, :name => "lan_DVS", :switch_id => s14.id)
        @lan15 = FactoryBot.create(:lan, :name => "lan_DVS", :switch_id => s15.id)
        @lan21 = FactoryBot.create(:lan, :name => "lan_DVS", :switch_id => s21.id)
        @lan22 = FactoryBot.create(:lan, :name => "lan_A",   :switch_id => s22.id)
      end

      it '#allowed_vlans' do
        @host1.switches = [s11, s12, s13]
        allow(workflow).to receive(:allowed_hosts).with(no_args).and_return([workflow.host_to_hash_struct(@host1)])
        vlans, _hosts = workflow.allowed_vlans(:vlans => true, :dvs => true)
        lan_keys   = [@lan11.name, @lan13.name, @lan12.name]
        lan_values = [@lan11.name, @lan13.name, @lan12.name]
        expect(vlans.keys).to match_array(lan_keys)
        expect(vlans.values).to match_array(lan_values)
      end

      it 'concatenates dvswitches of the same portgroup name' do
        @host1.switches = [s11, s12, s13, s14, s15]
        allow(workflow).to receive(:allowed_hosts).with(no_args).and_return([workflow.host_to_hash_struct(@host1)])
        vlans, _hosts = workflow.allowed_vlans(:vlans => true, :dvs => true)
        lan_keys = [@lan11.name, @lan13.name, @lan12.name, "dvs_#{@lan14.name}"]
        switches = [s14.name, s15.name].sort.join('/')
        lan_values = [@lan11.name, @lan13.name, @lan12.name, "#{@lan14.name} (#{switches})"]
        expect(vlans.keys).to match_array(lan_keys)
        expect(vlans.values).to match_array(lan_values)
      end

      it 'concatenates dvswitches of the same portgroup name from different hosts' do
        @host1.switches = [s11, s12, s13, s14, s15]
        @host2.switches = [s15, s21]
        allow(workflow).to receive(:allowed_hosts).with(no_args).and_return(
          [workflow.host_to_hash_struct(@host1), workflow.host_to_hash_struct(@host2)]
        )

        vlans, _hosts = workflow.allowed_vlans(:vlans => true, :dvs => true)
        lan_keys = [@lan11.name, @lan13.name, @lan12.name, "dvs_#{@lan14.name}"]
        switches = [s14.name, s15.name, s21.name].sort.join('/')
        lan_values = [@lan11.name, @lan13.name, @lan12.name, "#{@lan14.name} (#{switches})"]
        expect(vlans.keys).to match_array(lan_keys)
        expect(vlans.values).to match_array(lan_values)
      end

      it 'excludes dvs if told so' do
        @host1.switches = [s11, s12, s13, s14, s15]
        @host2.switches = [s15, s21]
        allow(workflow).to receive(:allowed_hosts).with(no_args).and_return(
          [workflow.host_to_hash_struct(@host1), workflow.host_to_hash_struct(@host2)]
        )
        vlans, _hosts = workflow.allowed_vlans(:vlans => true, :dvs => false)
        lan_keys = [@lan11.name, @lan13.name, @lan12.name]
        expect(vlans.keys).to match_array(lan_keys)
        expect(vlans.values).to match_array(lan_keys)
      end

      it 'concatenates dvswitches of the same portgroup name from different hosts when autoplacement is on' do
        @host1.switches = [s11, s12, s13, s14, s15]
        @host2.switches = [s21]
        workflow.instance_variable_set(:@values, :vm_tags => [], :src_vm_id => @src_vm.id, :placement_auto => true)
        vlans, _hosts = workflow.allowed_vlans(:vlans => true, :dvs => true)
        lan_keys = [@lan11.name, @lan13.name, @lan12.name, "dvs_#{@lan14.name}"]
        switches = [s14.name, s15.name, s21.name].sort.join('/')
        lan_values = [@lan11.name, @lan13.name, @lan12.name, "#{@lan14.name} (#{switches})"]
        expect(vlans.keys).to match_array(lan_keys)
        expect(vlans.values).to match_array(lan_values)
      end

      it 'returns no vlans when autoplacement is off and no allowed_hosts' do
        @host1.switches = [s11, s12, s13, s14, s15]
        @host2.switches = [s21]
        workflow.instance_variable_set(:@values, :vm_tags => [], :src_vm_id => @src_vm.id, :placement_auto => false)
        vlans, _hosts = workflow.allowed_vlans(:vlans => true, :dvs => true)
        expect(vlans.keys).to match_array([])
        expect(vlans.values).to match_array([])
      end

      it 'Returns both dvportgroup and lan with the same name' do
        @host1.switches = [s11, s22]
        allow(workflow).to receive(:allowed_hosts).with(no_args).and_return([workflow.host_to_hash_struct(@host1)])
        vlans, _hosts = workflow.allowed_vlans(:vlans => true, :dvs => true)

        lan_keys   = [@lan11.name, "dvs_#{@lan22.name}"]
        lan_values = [@lan11.name, "#{@lan22.name} (#{s22.name})"]
        expect(vlans.keys).to   match_array(lan_keys)
        expect(vlans.values).to match_array(lan_values)
      end

      context '#allowed_hosts_obj' do
        before do
          allow(workflow).to receive(:find_all_ems_of_type).and_return([@host1, @host2])
          allow(Rbac).to receive(:search) do |hash|
            [Array.wrap(hash[:targets])]
          end
        end

        it 'finds all hosts with no selected network' do
          workflow.instance_variable_set(:@values, :src_vm_id => @src_vm.id)
          expect(workflow.allowed_hosts_obj).to match_array([@host1, @host2])
        end

        it 'finds only the hosts that can access the selected vSwitch network' do
          @host1.switches = [s11]
          @host2.switches = [s22]
          workflow.instance_variable_set(:@values, :src_vm_id => @src_vm.id, :vlan => [@lan11.name, @lan11.name])
          expect(workflow.allowed_hosts_obj).to match_array([@host1])
        end

        it 'finds only the hosts that can access the selected dvSwitch network' do
          @host1.switches = [s11]
          @host2.switches = [s22]
          workflow.instance_variable_set(:@values, :src_vm_id => @src_vm.id, :vlan => ["dvs_#{@lan22.name}", @lan22.name])
          expect(workflow.allowed_hosts_obj).to match_array([@host2])
          expect(workflow.instance_variable_get(:@values)[:vlan]).to match_array(["dvs_#{@lan22.name}", @lan22.name])
        end
      end
    end
  end
end
