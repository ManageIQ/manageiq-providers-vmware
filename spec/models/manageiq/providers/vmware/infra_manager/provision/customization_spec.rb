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
  let(:gui_unattended)   { {"autoLogonCount" => 1} }
  let(:user_data) do
    {
      "fullName"     => "sysprep_full_name_value",
      "orgName"      => "sysprep_organization_value",
      "computerName" => {"name" => "computerName"}
    }
  end
  let(:new_spec) do
    {
      "identity"         => {
        "guiUnattended"        => gui_unattended,
        "identification"       => {},
        "licenseFilePrintData" => {"autoMode" => "perServer"},
        "userData"             => user_data
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

    context "with encrypted passwords" do
      let(:gui_unattended) { {"autoLogonCount" => 1, "password" => {"plainText" => "true", "value" => "123456"}} }
      let(:new_spec) do
        {
          "identity"         => {
            "guiUnattended"        => gui_unattended,
            "identification"       => {},
            "licenseFilePrintData" => {"autoMode" => "perServer"},
            "userData"             => user_data
          },
          "globalIPSettings" => {},
          "nicSettingMap"    => nic_settings_map,
          "options"          => {},
          "encryptionKey"    => encryption_key
        }
      end

      let(:encryption_key) do
        "0\x82\x03:0\x82\x02\"\xA0\x03\x02\x01\x02\x02\x11\x00\xAE\x9D\xFC\x9AF/\xBEO\xDB\x03\x92a\xCE\x96jQ0\r\x06\t*\x86H\x86\xF7\r\x01\x01\v\x05\x000\x121\x100\x0E\x06\x03U\x04\n\x13\aAcme Co0 \x17\r700101000000Z\x18\x0F20840129160000Z0\x121\x100\x0E\x06\x03U\x04\n\x13\aAcme Co0\x82\x01\"0\r\x06\t*\x86H\x86\xF7\r\x01\x01\x01\x05\x00\x03\x82\x01\x0F\x000\x82\x01\n\x02\x82\x01\x01\x00\xAFe\"s88\x02\x88\xE3?\xB0\f\xD9/q\x90\xBAK\xA7\xB1\x15#\xB2\xB2\x9E\xCD<\x9C\x9A\x10\bV\xF7y\x0Fc\xB8\x0E\x7F\xA1\xF9h\xFD\xD5\xDD\x854\xBD\x8ABJ|\xFFR\x1C\x83\x0F\xEF\xE4\x9C\x1A\x1F\xD4\x9D\xC3\xA3\xB1U\xC1\x8BB\xDB\xDD\xEF\xAE\xD5\xDF|\xDB@\xBF(\x1F&\x87V\xD5\xD3\xE5\x96\x9D{d\x96\xEA\xEF\xA7\xA2\xF6\x85\xAA\xD5\x8EG\xA3\x1F\xECU\x89\x8DT\xDC\xED\xBC\x17\xCA\xD6kiK\xCC\xFCB\xB95-`\xB2. \xC7\x92\xF0\xC0\x84,\xB6:;\x9A\xA2\x9CB\xEA\xA4\x1E\x8D\xD5\x93\xD4\xFCpn\xAAm\xB8\xB5Z\x91\t\x9Er\x98\x85\xAE\xEAr\xF04\xC6\xD3\x1D+\xC7\x17Lt\x00\x13\xCB\bX\x1An=\x03\xF1k\xA1\xA8\x19\xE8s3\xDD\xB9\xB7\xF7\a\xBF\xC3\xA5H\xC7zW\xD6V\xD4S*\xDF\x8E\xF0`}IQ\xC3\x1C\x99\x00\x10c\xD9$\xC6\xB0\xE4\tk\x8EuxG\x04Iw\x12\x11l\xE3\x1A5\x10\xD5g\xFE\xCF<k\xD8`\a\x98\x8F\x02\x03\x01\x00\x01\xA3\x81\x880\x81\x850\x0E\x06\x03U\x1D\x0F\x01\x01\xFF\x04\x04\x03\x02\x02\xA40\x13\x06\x03U\x1D%\x04\f0\n\x06\b+\x06\x01\x05\x05\a\x03\x010\x0F\x06\x03U\x1D\x13\x01\x01\xFF\x04\x050\x03\x01\x01\xFF0\x1D\x06\x03U\x1D\x0E\x04\x16\x04\x14\x8E\xD4vU+\xB1r\x14\xF1{E\r\rZ\x96\f\xD3\x11\xDF\xB00.\x06\x03U\x1D\x11\x04'0%\x82\vexample.com\x87\x04\x7F\x00\x00\x01\x87\x10\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x010\r\x06\t*\x86H\x86\xF7\r\x01\x01\v\x05\x00\x03\x82\x01\x01\x00\"\xBB\xD4\xBDy!\xE6\x0F\x89\x01\xC5\x0Eiw\x12\x00\xE8Fw\x7F\xB4\x06\x99?\xD9\xD4d\x82\x0F-\x18\x14\x9D\x02\x134\vc\x16\x00o\xAAw\x90g\tP\xB5\xCA6\xB3\xC6\x17J+\xC1B \x13\x94\x11-\x18\x1C\xD5\xC6\xFD\xFAG\x8BS^WH\x80\x9CZ\tLqf\xDA\x80,\xBC2\x1A\xA4\x9A#\xF70\x13JVk\xA6t:\x9D\xB0\x935&\xA1\x0EkF\xB2_D\xCF\x82\xE8t\x7F\xFAU\xA46\xD1\xD1\xCD\xA5\x059)q4\x96\xCF\xA3\x9D\xCA\xE7s\xA8\x0E\xB8\xB0\x11\xCDO\xBCF\x0F\xC0W\x94_\x04\xF3\t\x9E\xBC\xA4\tVR`\xCA\v*~\x94\xF8c\"\xDD\x86\xCEx\xA0\xF8\x14\x8F\b\xD2j\x9B\x02\x8C\xEF\xAA\x05\xCB,\"\xDCr\x0F\xE7\xAA\xC3\xFD\xCC\x14\xB6\x8Ae\x17\xAF.V\xE0\xFC\x1Dv\xF5\x82\x01\xAC\xAA\xD1\xA2\x01>\x06-?-S\x9C>\x06\xD2\xBCd\x8B?,\xAE\xE6v.\xD6\xF1\xA2\x0E\x85E\a\x97Y`y]\xE8\x11\v\x9E\xDC\x0E\xD2\xA2\x00".unpack("c*")
      end
      before do
        options[:sysprep_custom_spec]       = ''
        options[:sysprep_password]          = '123456'
        options[:sysprep_full_name]         = 'sysprep_full_name_value'
        options[:sysprep_organization]      = 'sysprep_organization_value'
        options[:sysprep_encrypt_passwords] = true

        expect(prov_vm).to receive(:encryption_key).and_return(encryption_key)
      end

      it "sets the encryptionKey" do
        expect(prov_vm).not_to receive(:load_customization_spec)
        expect(prov_vm.build_customization_spec).to(eq(new_spec))
      end
    end
  end
end
