describe ManageIQ::Providers::Vmware::InfraManager::HostEsx do
  include Spec::Support::SupportsHelper

  let(:ems)          { FactoryBot.create(:ems_vmware_with_authentication) }
  let(:host)         { FactoryBot.create(:host_vmware_esx, :ext_management_system => ems, :power_state => power_state) }
  let(:power_state)  { "on" }
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

  describe "supports features" do
    before { EvmSpecHelper.local_miq_server }

    describe ":refresh_advanced_settings" do
      it "is supported" do
        expect(host.supports?(:refresh_advanced_settings)).to be_truthy
      end
    end

    describe ":refresh_firewall_rules" do
      it "is supported" do
        expect(host.supports?(:refresh_firewall_rules)).to be_truthy
      end
    end

    describe ":refresh_logs" do
      it "is supported" do
        expect(host.supports?(:refresh_logs)).to be_truthy
      end
    end

    describe ":start" do
      context "when host is in standby" do
        let(:power_state) { "standby" }

        it "is supported" do
          expect(host.supports?(:start)).to be_truthy
        end
      end

      context "when host is on" do
        let(:power_state) { "on" }

        it "is not supported" do
          expect(host.supports?(:start)).to be_falsey
          expect(host.unsupported_reason(:start)).to eq("The host is not in standby")
        end
      end

      context "when host has no active provider" do
        let(:ems) { nil }

        it "is not supported" do
          expect(host.supports?(:start)).to be_falsey
          expect(host.unsupported_reason(:start)).to eq("The Host is not connected to an active Provider")
        end
      end
    end

    describe ":reboot" do
      context "when host is on" do
        let(:power_state) { "on" }

        it "is supported" do
          expect(host.supports?(:reboot)).to be_truthy
        end
      end

      context "when host is off" do
        let(:power_state) { "off" }

        it "is not supported" do
          expect(host.supports?(:reboot)).to be_falsey
          expect(host.unsupported_reason(:reboot)).to eq("The host is not running")
        end
      end

      context "when host has no active provider" do
        let(:ems) { nil }

        it "is not supported" do
          expect(host.supports?(:reboot)).to be_falsey
          expect(host.unsupported_reason(:reboot)).to eq("The Host is not connected to an active Provider")
        end
      end
    end

    describe ":shutdown" do
      context "when host is on" do
        let(:power_state) { "on" }

        it "is supported" do
          expect(host.supports?(:shutdown)).to be_truthy
        end
      end

      context "when host is off" do
        let(:power_state) { "off" }

        it "is not supported" do
          expect(host.supports?(:shutdown)).to be_falsey
          expect(host.unsupported_reason(:shutdown)).to eq("The host is not running")
        end
      end

      context "when host has no active provider" do
        let(:ems) { nil }

        it "is not supported" do
          expect(host.supports?(:shutdown)).to be_falsey
          expect(host.unsupported_reason(:shutdown)).to eq("The Host is not connected to an active Provider")
        end
      end
    end

    describe ":standby" do
      context "when host is on" do
        let(:host) { FactoryBot.create(:host_vmware_esx, :ext_management_system => ems, :power_state => "on") }

        it "is supported" do
          expect(host.supports?(:standby)).to be_truthy
        end
      end

      context "when host is off" do
        let(:host) { FactoryBot.create(:host_vmware_esx, :ext_management_system => ems, :power_state => "off") }

        it "is not supported" do
          expect(host.supports?(:standby)).to be_falsey
          expect(host.unsupported_reason(:standby)).to eq("The host is not running")
        end
      end

      context "when host has no active provider" do
        let(:host) { FactoryBot.create(:host_vmware_esx, :ext_management_system => nil, :power_state => "on") }

        it "is not supported" do
          expect(host.supports?(:standby)).to be_falsey
          expect(host.unsupported_reason(:standby)).to eq("The Host is not connected to an active Provider")
        end
      end
    end

    describe ":enter_maint_mode" do
      context "when host is on" do
        let(:power_state) { "on" }

        it "is supported" do
          expect(host.supports?(:enter_maint_mode)).to be_truthy
        end
      end

      context "when host is off" do
        let(:power_state) { "off" }

        it "is not supported" do
          expect(host.supports?(:enter_maint_mode)).to be_falsey
          expect(host.unsupported_reason(:enter_maint_mode)).to eq("The host is not running")
        end
      end

      context "when host has no active provider" do
        let(:ems) { nil }

        it "is not supported" do
          expect(host.supports?(:enter_maint_mode)).to be_falsey
          expect(host.unsupported_reason(:enter_maint_mode)).to eq("The Host is not connected to an active Provider")
        end
      end
    end

    describe ":exit_maint_mode" do
      context "when host is in maintenance mode" do
        let(:power_state) { "maintenance" }

        it "is supported" do
          expect(host.supports?(:exit_maint_mode)).to be_truthy
        end
      end

      context "when host is on but not in maintenance mode" do
        let(:power_state) { "on" }

        it "is not supported" do
          expect(host.supports?(:exit_maint_mode)).to be_falsey
          expect(host.unsupported_reason(:exit_maint_mode)).to eq("The host is not in maintenance mode")
        end
      end

      context "when host has no active provider" do
        let(:power_state) { "maintenance" }
        let(:ems)         { nil }

        it "is not supported" do
          expect(host.supports?(:exit_maint_mode)).to be_falsey
          expect(host.unsupported_reason(:exit_maint_mode)).to eq("The Host is not connected to an active Provider")
        end
      end
    end

    describe ":enable_vmotion" do
      context "when host is on with active provider" do
        it "is supported" do
          expect(host.supports?(:enable_vmotion)).to be_truthy
        end
      end

      context "when host is off" do
        let(:power_state) { "off" }

        it "is not supported" do
          expect(host.supports?(:enable_vmotion)).to be_falsey
          expect(host.unsupported_reason(:enable_vmotion)).to eq("The host is not powered 'on'")
        end
      end

      context "when host has no active provider" do
        let(:ems) { nil }

        it "is not supported" do
          expect(host.supports?(:enable_vmotion)).to be_falsey
          expect(host.unsupported_reason(:enable_vmotion)).to eq("The Host is not connected to an active Provider")
        end
      end
    end

    describe ":disable_vmotion" do
      context "when host is on with active provider" do
        it "is supported" do
          expect(host.supports?(:disable_vmotion)).to be_truthy
        end
      end

      context "when host is off" do
        let(:power_state) { "off" }

        it "is not supported" do
          expect(host.supports?(:disable_vmotion)).to be_falsey
          expect(host.unsupported_reason(:disable_vmotion)).to eq("The host is not powered 'on'")
        end
      end

      context "when host has no active provider" do
        let(:ems) { nil }

        it "is not supported" do
          expect(host.supports?(:disable_vmotion)).to be_falsey
          expect(host.unsupported_reason(:disable_vmotion)).to eq("The Host is not connected to an active Provider")
        end
      end
    end

    describe ":vmotion_enabled" do
      context "when host is on with active provider" do
        let(:power_state) { "on" }

        it "is supported" do
          expect(host.supports?(:vmotion_enabled)).to be_truthy
        end
      end

      context "when host is off" do
        let(:power_state) { "off" }

        it "is not supported" do
          expect(host.supports?(:vmotion_enabled)).to be_falsey
          expect(host.unsupported_reason(:vmotion_enabled)).to eq("The host is not powered 'on'")
        end
      end

      context "when host has no active provider" do
        let(:ems) { nil }

        it "is not supported" do
          expect(host.supports?(:vmotion_enabled)).to be_falsey
          expect(host.unsupported_reason(:vmotion_enabled)).to eq("The Host is not connected to an active Provider")
        end
      end
    end
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
