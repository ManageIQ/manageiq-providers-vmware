describe ManageIQ::Providers::Vmware::InfraManager do
  let(:ems) { FactoryBot.create(:ems_vmware) }

  it ".ems_type" do
    expect(described_class.ems_type).to eq('vmwarews')
  end

  it ".description" do
    expect(described_class.description).to eq('VMware vCenter')
  end

  describe ".metrics_collector_queue_name" do
    it "returns the correct queue name" do
      worker_queue = ManageIQ::Providers::Vmware::InfraManager::MetricsCollectorWorker.default_queue_name
      expect(described_class.metrics_collector_queue_name).to eq(worker_queue)
    end
  end

  context "#supports_streaming_refresh?" do
    it "returns true for streaming_refresh" do
      expect(ems.supports_streaming_refresh?).to be_truthy
    end
  end

  context ".verify_credentials" do
    let(:verify_params) { {"endpoints" => {"default" => {"hostname" => "vcenter"}}, "authentications" => {"default" => {"username" => "root", "password" => "vmware"}}} }
    before do
      miq_vim = double("VMwareWebService/MiqVim")
      allow(miq_vim).to receive(:isVirtualCenter).and_return(is_virtual_center)
      allow(miq_vim).to receive(:disconnect)

      require "VMwareWebService/MiqVim"
      expect(MiqVim).to receive(:new).and_return(miq_vim)
    end

    context "virtual-center" do
      let(:is_virtual_center) { true }

      it "is successful" do
        expect(described_class.verify_credentials(verify_params)).to be_truthy
      end
    end

    context "esxi host" do
      let(:is_virtual_center) { false }

      it "returns a failure" do
        expect { described_class.verify_credentials(verify_params) }
          .to raise_error(MiqException::Error, "Adding ESX/ESXi Hosts is not supported")
      end
    end
  end

  context "#verify_credentials" do
    let(:ems) { FactoryBot.create(:ems_vmware_with_authentication) }
    before do
      miq_vim = double("VMwareWebService/MiqVim")
      allow(miq_vim).to receive(:isVirtualCenter).and_return(true)
      allow(miq_vim).to receive(:disconnect)

      require "VMwareWebService/MiqVim"
      expect(MiqVim).to receive(:new).and_return(miq_vim)
    end

    it "success with correct credentials" do
      expect(ems.verify_credentials("default")).to be_truthy
    end
  end

  context ".supports_authentication?" do
    it "returns true for supported auth types" do
      expect(ems.supports_authentication?("default")).to be_truthy
      expect(ems.supports_authentication?("console")).to be_truthy
    end

    it "returns false for non-supported auth types" do
      expect(ems.supports_authentication?("metrics")).to be_falsey
    end
  end

  context "#queue_name_for_ems_operations" do
    it "returns the per-ems queue_name" do
      expect(ems.queue_name_for_ems_operations).to eq(ems.queue_name)
    end
  end

  context ".provision_class" do
    it "returns ViaPxe for pxe" do
      expect(described_class.provision_class("pxe")).to eq(ems.class::ProvisionViaPxe)
    end

    it "returns Provision for everything else" do
      expect(described_class.provision_class("vm")).to eq(ems.class::Provision)
    end
  end

  context "#validate_remote_console_vmrc_support" do
    before(:each) do
      @ems = FactoryBot.create(:ems_vmware)
    end

    it "not raise for api_version == 5.0" do
      @ems.update(:api_version => "5.0", :uid_ems => "2E1C1E82-BD83-4E54-9271-630C6DFAD4D1")
      expect { @ems.validate_remote_console_vmrc_support }.not_to raise_error
    end

    it "raise for api_version == 4.0" do
      @ems.update(:api_version => "4.0", :uid_ems => "2E1C1E82-BD83-4E54-9271-630C6DFAD4D1")
      expect { @ems.validate_remote_console_vmrc_support }.to raise_error MiqException::RemoteConsoleNotSupportedError
    end

    it "raise for api_version == 4.1" do
      @ems.update(:api_version => "4.1", :uid_ems => "2E1C1E82-BD83-4E54-9271-630C6DFAD4D1")
      expect { @ems.validate_remote_console_vmrc_support }.to raise_error MiqException::RemoteConsoleNotSupportedError
    end

    it "raise for missing/blank values" do
      @ems.update(:api_version => "", :uid_ems => "2E1C1E82-BD83-4E54-9271-630C6DFAD4D1")
      expect { @ems.validate_remote_console_vmrc_support }.to raise_error MiqException::RemoteConsoleNotSupportedError
    end
  end

  context "#remote_console_vmrc_support_known?" do
    before(:each) do
      @ems = FactoryBot.create(:ems_vmware)
    end

    it "true with nothing missing/blank" do
      @ems.update(:api_version => "5.0", :uid_ems => "2E1C1E82-BD83-4E54-9271-630C6DFAD4D1")
      expect(@ems.remote_console_vmrc_support_known?).to be_truthy
    end

    it "false for blank hostname" do
      @ems.update(:hostname => "", :api_version => "5.0", :uid_ems => "2E1C1E82-BD83-4E54-9271-630C6DFAD4D1")
      expect(@ems.remote_console_vmrc_support_known?).not_to be_truthy
    end

    it "false for missing api_version" do
      @ems.update(:api_version => nil, :uid_ems => "2E1C1E82-BD83-4E54-9271-630C6DFAD4D1")
      expect(@ems.remote_console_vmrc_support_known?).not_to be_truthy
    end

    it "false for blank api_version" do
      @ems.update(:api_version => "", :uid_ems => "2E1C1E82-BD83-4E54-9271-630C6DFAD4D1")
      expect(@ems.remote_console_vmrc_support_known?).not_to be_truthy
    end

    it "false for missing uid_ems" do
      @ems.update(:api_version => "5.0", :uid_ems => nil)
      expect(@ems.remote_console_vmrc_support_known?).not_to be_truthy
    end

    it "false for blank uid_ems" do
      @ems.update(:api_version => "5.0", :uid_ems => "")
      expect(@ems.remote_console_vmrc_support_known?).not_to be_truthy
    end
  end

  context "#remote_console_vmrc_acquire_ticket" do
    let(:ems) do
      _, _, zone = EvmSpecHelper.create_guid_miq_server_zone
      FactoryBot.create(:ems_vmware, :zone => zone)
    end

    context "with console credentials" do
      before do
        ems.authentications << FactoryBot.create(:authentication, :userid => "root", :password => "vmware")
        ems.authentications << FactoryBot.create(:authentication, :authtype => "console", :userid => "readonly", :password => "1234")
      end

      it "uses the console credentials" do
        require 'VMwareWebService/MiqVim'

        vim = mock_miq_vim_connection

        expect(MiqVim).to receive(:new).with(ems.hostname, "readonly", "1234", nil, nil, nil).and_return(vim)
        expect(vim).to receive(:acquireCloneTicket)

        ems.remote_console_vmrc_acquire_ticket
      end
    end

    context "without console credentials" do
      before do
        ems.authentications << FactoryBot.create(:authentication, :userid => "root", :password => "vmware")
      end

      it "raises an exception" do
        require 'VMwareWebService/MiqVim'

        expect { ems.remote_console_vmrc_acquire_ticket }.to raise_error "no console credentials defined"
      end
    end
  end

  context "handling changes that may require EventCatcher restart" do
    before(:each) do
      guid, server, zone = EvmSpecHelper.create_guid_miq_server_zone
      @ems = FactoryBot.create(:ems_vmware, :zone => zone)
    end

    it "will restart EventCatcher when ipaddress changes" do
      @ems.update(:ipaddress => "1.1.1.1")
      assert_event_catcher_restart_queued
    end

    it "will restart EventCatcher when hostname changes" do
      @ems.update(:hostname => "something-else")
      assert_event_catcher_restart_queued
    end

    it "will restart EventCatcher when credentials change" do
      @ems.update_authentication(:default => {:userid => "new_user_id"})
      assert_event_catcher_restart_queued
    end

    it "will not put multiple restarts of the EventCatcher on the queue" do
      @ems.update(:ipaddress => "1.1.1.1")
      @ems.update(:hostname => "something else")
      assert_event_catcher_restart_queued
    end

    it "will not restart EventCatcher when name changes" do
      @ems.update(:name => "something else")
      expect(MiqQueue.count).to eq(0)
    end
  end

  context "catalog types" do
    it "#catalog_types" do
      ems = FactoryBot.create(:ems_vmware)
      expect(ems.catalog_types).to include("vmware")
    end
  end

  private

  def assert_event_catcher_restart_queued
    q = MiqQueue.where(:method_name => "stop_event_monitor")
    expect(q.length).to eq(1)
    expect(q[0].class_name).to eq("ManageIQ::Providers::Vmware::InfraManager")
    expect(q[0].instance_id).to eq(@ems.id)
    expect(q[0].role).to eq("event")
  end

  def mock_miq_vim_connection
    vim = double(vim)
    allow(vim).to receive(:server).and_return(ems.hostname)
    allow(vim).to receive(:isVirtualCenter?).and_return(true)
    allow(vim).to receive(:apiVersion).and_return(6.0)
    vim
  end
end
