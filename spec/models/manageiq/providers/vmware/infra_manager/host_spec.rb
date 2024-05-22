describe ManageIQ::Providers::Vmware::InfraManager::Host do
  include Spec::Support::SupportsHelper

  let(:ems)  { FactoryBot.create(:ems_vmware) }
  let(:host) { FactoryBot.create(:host_vmware, :ext_management_system => ems) }

  describe "supports :start" do
    let(:host) { FactoryBot.create(:host_vmware, :ext_management_system => ems, :power_state => power_state) }

    before { EvmSpecHelper.local_miq_server }

    context "when it does not support ipmi" do
      before do
        stub_supports_all_others(described_class)
        stub_supports_not(described_class, :ipmi)
      end

      let(:power_state) { "off" }
      it { expect(host.supports?(:start)).to be_falsey }
    end

    context "when it supports ipmi" do
      before do
        stub_supports_all_others(described_class)
        stub_supports(described_class, :ipmi)
      end

      context "when off" do
        let(:power_state) { "off" }
        it { expect(host.supports?(:start)).to be_truthy }
      end

      context "when on" do
        let(:power_state) { "on" }
        it { expect(host.supports?(:start)).to be_falsey }
      end

      # new in this provider
      context "when standby" do
        let(:power_state) { "standby" }
        it { expect(host.supports?(:start)).to be_truthy }
      end
    end
  end

  context "#reserve_next_available_vnc_port" do
    context "without EMS defaults set" do
      let(:ems)  { FactoryBot.create(:ems_vmware, :host_default_vnc_port_start => nil, :host_default_vnc_port_end => nil) }

      it "normal case" do
        host.update(:next_available_vnc_port => 5901)

        expect(host.reserve_next_available_vnc_port).to eq(5901)
        expect(host.next_available_vnc_port).to eq(5902)
      end

      it "with last value of nil" do
        host.update(:next_available_vnc_port => nil)

        expect(host.reserve_next_available_vnc_port).to eq(5900)
        expect(host.next_available_vnc_port).to eq(5901)
      end

      it "with last value at end of range" do
        host.update(:next_available_vnc_port => 5999)

        expect(host.reserve_next_available_vnc_port).to eq(5999)
        expect(host.next_available_vnc_port).to eq(5900)
      end

      it "with last value before start of range" do
        host.update(:next_available_vnc_port => 5899)

        expect(host.reserve_next_available_vnc_port).to eq(5900)
        expect(host.next_available_vnc_port).to eq(5901)
      end

      it "with last value after end of range" do
        host.update(:next_available_vnc_port => 6000)

        expect(host.reserve_next_available_vnc_port).to eq(5900)
        expect(host.next_available_vnc_port).to eq(5901)
      end
    end

    context "with EMS defaults set" do
      let(:ems)  { FactoryBot.create(:ems_vmware, :host_default_vnc_port_start => 5925, :host_default_vnc_port_end => 5930) }

      it "normal case" do
        host.update(:next_available_vnc_port => 5926)

        expect(host.reserve_next_available_vnc_port).to eq(5926)
        expect(host.next_available_vnc_port).to eq(5927)
      end

      it "with last value of nil" do
        host.update(:next_available_vnc_port => nil)

        expect(host.reserve_next_available_vnc_port).to eq(5925)
        expect(host.next_available_vnc_port).to eq(5926)
      end

      it "with last value at end of range" do
        host.update(:next_available_vnc_port => 5930)

        expect(host.reserve_next_available_vnc_port).to eq(5930)
        expect(host.next_available_vnc_port).to eq(5925)
      end

      it "with last value before start of range" do
        host.update(:next_available_vnc_port => 5924)

        expect(host.reserve_next_available_vnc_port).to eq(5925)
        expect(host.next_available_vnc_port).to eq(5926)
      end

      it "with last value after end of range" do
        host.update(:next_available_vnc_port => 5931)

        expect(host.reserve_next_available_vnc_port).to eq(5925)
        expect(host.next_available_vnc_port).to eq(5926)
      end
    end
  end
end
