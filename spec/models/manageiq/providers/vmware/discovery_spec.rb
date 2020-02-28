describe ManageIQ::Providers::Vmware::Discovery do
  describe ".probe" do
    let(:discover_types) { %i[virtualcenter esx vmwareserver] }
    let(:ost)            { OpenStruct.new(:ipaddr => "0.0.0.0", :discover_types => discover_types, :hypervisor => [], :os => []) }
    before do
      require "VMwareWebService/MiqVimClientBase"

      miq_vim_client_base = double("VMwareWebService/MiqVimClientBase")
      allow(miq_vim_client_base).to receive(:about).and_return(about_info)
      allow(MiqVimClientBase).to receive(:new).and_return(miq_vim_client_base)
    end

    context "connection failed" do
      let(:about_info) { nil }

      it "handles unreachable server" do
        allow(MiqVimClientBase).to receive(:new).and_raise(HTTPClient::ConnectTimeoutError, "execution expired")

        expect(ost.hypervisor).to be_empty
        expect(ost.os).to         be_empty
      end

      it "handles nil aboutInfo" do
        described_class.probe(ost)

        expect(ost.hypervisor).to be_empty
        expect(ost.os).to         be_empty
      end
    end

    context "vpx" do
      context "vcsa" do
        let(:about_info) do
          VimHash.new("AboutInfo").tap do |about|
            about.name          = "VMware vCenter Server"
            about.vendor        = "VMware, Inc."
            about.version       = "6.7.0"
            about.osType        = "linux-x64"
            about.productLineId = "vpx"
            about.apiType       = "VirtualCenter"
            about.apiVersion    = "6.7.1"
          end
        end

        it "Discovers VirtualCenters" do
          described_class.probe(ost)

          expect(ost.hypervisor).to include(:virtualcenter)
          expect(ost.os).to         include(:linux)
        end
      end

      context "windows" do
        let(:about_info) do
          VimHash.new("AboutInfo").tap do |about|
            about.name          = "VMware vCenter Server"
            about.vendor        = "VMware, Inc."
            about.version       = "5.1.0"
            about.osType        = "win32"
            about.productLineId = "vpx"
            about.apiType       = "VirtualCenter"
            about.apiVersion    = "5.1.0"
          end
        end

        it "Discovers VirtualCenters" do
          described_class.probe(ost)

          expect(ost.hypervisor).to include(:virtualcenter)
          expect(ost.os).to         include(:mswin)
        end
      end
    end

    context "esx" do
      let(:about_info) do
        VimHash.new("AboutInfo").tap do |about|
          about.name          = "VMware ESXi"
          about.vendor        = "VMware, Inc."
          about.version       = "6.7.0"
          about.osType        = "vmnix-x86"
          about.productLineId = "esx"
          about.apiType       = "HostAgent"
          about.apiVersion    = "6.7"
        end
      end

      it "discovers ESX Hosts" do
        described_class.probe(ost)

        expect(ost.hypervisor).to include(:esx)
        expect(ost.os).to         include(:linux)
      end
    end

    context "embeddedEsx" do
      let(:about_info) do
        VimHash.new("AboutInfo").tap do |about|
          about.name          = "VMware ESXi"
          about.vendor        = "VMware, Inc."
          about.version       = "6.7.0"
          about.osType        = "vmnix-x86"
          about.productLineId = "embeddedEsx"
          about.apiType       = "HostAgent"
          about.apiVersion    = "6.7"
        end
      end

      it "discovers ESX Hosts" do
        described_class.probe(ost)

        expect(ost.hypervisor).to include(:esx)
        expect(ost.os).to         include(:linux)
      end
    end

    context "gsx" do
      let(:about_info) do
        VimHash.new("AboutInfo").tap do |about|
          about.name          = "VMware GSX"
          about.vendor        = "VMware, Inc."
          about.version       = "1.0"
          about.osType        = "vmnix-x86"
          about.productLineId = "gsx"
          about.apiType       = "HostAgent"
          about.apiVersion    = "1.0"
        end
      end

      it "discovers ESX Hosts" do
        described_class.probe(ost)

        expect(ost.hypervisor).to include(:vmwareserver)
        expect(ost.os).to         include(:linux)
      end
    end

    context "Unknown Products" do
      let(:about_info) do
        VimHash.new("AboutInfo").tap do |about|
          about.name          = "VMware vCloud Director"
          about.vendor        = "VMware, Inc."
          about.version       = "1.0"
          about.osType        = "linux"
          about.productLineId = "vcd"
        end
      end

      it "handles unknown products" do
        described_class.probe(ost)

        expect(ost.hypervisor).to be_empty
        expect(ost.os).to         be_empty
      end
    end
  end
end
