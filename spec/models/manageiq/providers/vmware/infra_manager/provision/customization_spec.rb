require 'VMwareWebService/VimTypes'

describe ManageIQ::Providers::Vmware::InfraManager::Provision::Customization do
  let(:custom_spec_name) { 'custom_spec_name' }
  let(:target_vm_name)   { 'computerName' }
  let(:os)               { FactoryBot.create(:operating_system, :product_name => 'Microsoft Windows') }
  let(:ems)              { FactoryBot.create(:ems_vmware_with_authentication, :api_version => '6.0', :customization_specs => [custom_spec]) }
  let(:custom_spec)      { FactoryBot.create(:customization_spec, :name => custom_spec_name, :spec => spec) }
  let(:prov_request)     { FactoryBot.create(:miq_provision_request, :src_vm_id => vm_template.id) }
  let(:options) do
    {
      :pass                        => 1,
      :vm_name                     => target_vm_name,
      :number_of_vms               => 1,
      :cpu_limit                   => -1,
      :cpu_reserve                 => 0,
      :src_vm_id                   => [vm_template.id, vm_template.name],
      :sysprep_enabled             => 'enabled',
      :sysprep_custom_spec         => custom_spec_name,
      :sysprep_spec_override       => false,
      :sysprep_server_license_mode => 'perServer',
      :vm_target_hostname          => target_vm_name
    }
  end
  let(:prov_vm) do
    FactoryBot.create(
      :miq_provision_vmware,
      :miq_request  => prov_request,
      :source       => @vm_template,
      :request_type => 'template',
      :state        => 'pending',
      :status       => 'Ok',
      :options      => options
    )
  end
  let(:vm_template) do
    FactoryBot.create(
      :template_vmware,
      :ext_management_system => ems,
      :operating_system      => os,
      :cpu_limit             => -1,
      :cpu_reserve           => 0
    )
  end
  let(:spec) do
    vh = VimHash.new('CustomizationSpec')
    vh['options'] = VimHash.new('options') do |opt|
      opt.changeSID = 'true'
      opt.deleteAccounts = 'false'
    end
    vh['identity'] = VimHash.new('identity') do |i|
      i.guiUnattended = VimHash.new('guiUnattended') do |gu|
        gu.password       = { 'value' => '123456', 'plainText' => 'true' }
        gu.timeZone       = '35'
        gu.autoLogon      = 'true'
        gu.autoLogonCount = 1
      end
      i.userData = VimHash.new('userData') do |ud|
        ud.fullName     = 'MIQ'
        ud.orgName      = 'Red Hat'
        ud.computerName = { 'name' => target_vm_name }
        ud.productId    = ''
      end
      i.identification = VimHash.new('identification') do |idt|
        idt.joinWorkgroup = 'WORKGROUP'
      end
      i.licenseFilePrintData = VimHash.new('licenseFilePrintData') do |lfp|
        lfp.autoMode  = 'perServer'
        lfp.autoUsers = '5'
      end
    end
    vh['globalIPSettings'] = {}
    vh['nicSettingMap']    = []
    vh
  end
  let(:nic_settings_map) { [] }
  let(:new_spec) do
    {
      "identity"         => {
        "guiUnattended"        => { "autoLogonCount" => 1 },
        "identification"       => {},
        "licenseFilePrintData" => { "autoMode" => "perServer" },
        "userData"             => {
          "fullName"     => "sysprep_full_name_value",
          "orgName"      => "sysprep_organization_value",
          "computerName" => { "name" => "computerName" }
        }
      },
      "globalIPSettings" => {},
      "nicSettingMap"    => nic_settings_map,
      "options"          => {}
    }
  end

  it 'skips building spec' do
    options[:sysprep_enabled] = 'disabled'
    expect(prov_vm.build_customization_spec).to(be_nil)
  end

  context 'build_customization_spec for windows template' do
    it 'loads existing spec' do
      expect(prov_vm).to receive(:load_customization_spec).and_return(spec)
      expect(prov_vm.build_customization_spec).to(eq(spec))
    end

    it 'loads existing spec and override it' do
      spec_for_compare = spec
      options[:sysprep_spec_override] = true
      options[:sysprep_organization] = 'sysprep_organization_value'
      spec_for_compare.identity.userData.orgName = options[:sysprep_organization]
      options[:sysprep_full_name] = 'sysprep_full_name_value'
      spec_for_compare.identity.userData.fullName = options[:sysprep_full_name]
      spec_for_compare.identity.identification = VimHash.new

      expect(prov_vm).to receive(:load_customization_spec).and_return(spec)
      expect(prov_vm.build_customization_spec).to(eq(spec_for_compare))
    end

    it 'creates a new spec when the saved spec is nil' do
      options[:sysprep_full_name] = 'sysprep_full_name_value'
      options[:sysprep_organization] = 'sysprep_organization_value'
      expect(prov_vm).to receive(:load_customization_spec).and_return(nil)
      expect(prov_vm.build_customization_spec).to(eq(new_spec))
    end

    it 'creates a new spec when the name is blank' do
      options[:sysprep_custom_spec] = ''
      options[:sysprep_full_name] = 'sysprep_full_name_value'
      options[:sysprep_organization] = 'sysprep_organization_value'
      expect(prov_vm).not_to receive(:load_customization_spec)
      expect(prov_vm.build_customization_spec).to(eq(new_spec))
    end

    context "with network options" do
      context "set at the top level of options" do
        let(:ip_addr)          { "192.168.1.10" }
        let(:gateway)          { "192.168.1.1" }
        let(:dns_domain)       { "localdomain" }
        let(:nic_settings_map) { [{"adapter" => {"dnsDomain" => dns_domain, "gateway" => [gateway], "ip" => {"ipAddress" => ip_addr}}}] }

        it 'sets the nicSettingMap on the new spec' do
          options[:sysprep_custom_spec]  = ''
          options[:sysprep_full_name]    = 'sysprep_full_name_value'
          options[:sysprep_organization] = 'sysprep_organization_value'
          options[:requested_network_adapter_count] = 1
          options[:ip_addr]    = ip_addr
          options[:gateway]    = gateway
          options[:dns_domain] = dns_domain

          expect(prov_vm).not_to receive(:load_customization_spec)
          expect(prov_vm.build_customization_spec).to(eq(new_spec))
        end
      end

      context "with a nic_settings array in options" do
        let(:nic_settings_map) { [{"adapter" => {"ip" => {"ipAddress" => "192.168.1.10"}}}, {"adapter" => {"ip" => {"ipAddress" => "192.168.2.10"}}}] }

        it 'sets network settings for multiple nics' do
          options[:sysprep_custom_spec]  = ''
          options[:sysprep_full_name]    = 'sysprep_full_name_value'
          options[:sysprep_organization] = 'sysprep_organization_value'
          options[:requested_network_adapter_count] = 2
          options[:nic_settings] = [{:ip_addr => "192.168.1.10"}, {:ip_addr => "192.168.2.10"}]

          expect(prov_vm).not_to receive(:load_customization_spec)
          expect(prov_vm.build_customization_spec).to(eq(new_spec))
        end
      end
    end
  end
end
