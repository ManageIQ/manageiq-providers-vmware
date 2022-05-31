describe ManageIQ::Providers::Vmware::InfraManager::Host do
  let(:ems)  { FactoryBot.create(:ems_vmware) }
  let(:host) { FactoryBot.create(:host_vmware, :ext_management_system => ems) }

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
