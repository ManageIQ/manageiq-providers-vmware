describe ManageIQ::Providers::Vmware::InfraManager::HostEsx do
  let(:ems)  { FactoryBot.create(:ems_vmware_with_authentication) }
  let(:host) { FactoryBot.create(:host_vmware_esx, :ext_management_system => ems) }

  let(:miq_vim)      { double("VMwareWebService/MiqVim") }
  let(:miq_vim_host) { MiqVimHost.new(miq_vim, "summary" => {"config" => {}}) }

  before do
    require "VMwareWebService/MiqVim"
    allow(MiqVim).to  receive(:new).and_return(miq_vim)
    allow(miq_vim).to receive(:disconnect)
    allow(miq_vim).to receive(:sic)
    allow(miq_vim).to receive(:about).and_return("apiType" => "VirtualCenter")
    allow(miq_vim).to receive(:getVimHostByMor).and_return(miq_vim_host)
  end

  describe "#vim_firewall_rules" do
    let(:firewall_system) { MiqHostFirewallSystem.new("", miq_vim) }
    let(:host_firewall_info) do
      VimHash.new("HostFirewallInfo").tap do |fi|
        fi["ruleset"] = [
          {
            "key"          => "CIMHttpServer",
            "label"        => "CIM Server",
            "required"     => "false",
            "rule"         => [
              {
                "port"      => "5988",
                "direction" => "inbound",
                "portType"  => "dst",
                "protocol"  => "tcp"
              }
            ],
            "service"      => "sfcbd-watchdog",
            "enabled"      => "true",
            "allowedHosts" => {
              "allIp" => "true"
            }
          }
        ]
      end
    end

    before do
      allow(firewall_system).to receive(:firewallInfo).and_return(host_firewall_info)
      allow(miq_vim_host).to receive(:firewallSystem).and_return(firewall_system)
    end

    it "parses host firewallSystem" do
      expect(host.vim_firewall_rules).to match_array(
        [
          {
            :name          => "CIMHttpServer 5988 (tcp-inbound)",
            :display_name  => "CIM Server 5988 (tcp-inbound)",
            :host_protocol => "tcp",
            :direction     => "in",
            :port          => "5988 (tcp-inbound)",
            :end_port      => nil,
            :group         => "CIMHttpServer",
            :enabled       => "true",
            :required      => "false"
          }
        ]
      )
    end
  end

  describe "#vim_advanced_settings" do
    let(:advanced_options_manager) { MiqHostAdvancedOptionManager.new("", miq_vim) }
    before do
      allow(advanced_options_manager).to receive(:setting).and_return(
        [{"key" => "Annotations.WelcomeMessage", "value" => {}}]
      )
      allow(advanced_options_manager).to receive(:supportedOption).and_return(
        [
          {
            "label"      => "Flush interval",
            "summary"    => "Flush at this interval (milliseconds)",
            "key"        => "BufferCache.FlushInterval",
            "optionType" => {"valueIsReadonly" => "false", "min" => "100", "max" => "3600000", "defaultValue" => "30000"}
          }
        ]
      )
      allow(miq_vim_host).to receive(:advancedOptionManager).and_return(advanced_options_manager)
    end

    it "parses host advancedOptions" do
      expect(host.vim_advanced_settings).to match_array(
        [
          {
            :default_value => nil,
            :description   => nil,
            :display_name  => nil,
            :max           => nil,
            :min           => nil,
            :name          => "Annotations.WelcomeMessage",
            :read_only     => nil,
            :value         => "{}"
          }
        ]
      )
    end
  end
end
