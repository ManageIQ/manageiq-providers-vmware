describe VmScan do
  context "A single VM Scan Job," do
    before do
      @server = EvmSpecHelper.local_miq_server(:has_vix_disk_lib => true)
      assign_smartproxy_role_to_server(@server)

      # TODO: stub only settings needed for test instead of all from settings.yml
      stub_settings(::Settings.to_hash.merge(:coresident_miqproxy => {:scan_via_host => false}))

      @user      = FactoryBot.create(:user_with_group, :userid => "tester")
      @ems       = FactoryBot.create(:ems_vmware_with_authentication, :name   => "Test EMS", :zone => @server.zone,
                                      :tenant                                  => FactoryBot.create(:tenant))
      @storage   = FactoryBot.create(:storage, :name => "test_storage", :store_type => "VMFS")
      @host      = FactoryBot.create(:host, :name => "test_host", :hostname => "test_host",
                                      :state       => 'on', :ext_management_system => @ems)
      @vm        = FactoryBot.create(:vm_vmware, :name => "test_vm", :location => "abc/abc.vmx",
                                      :raw_power_state       => 'poweredOn',
                                      :host                  => @host,
                                      :ext_management_system => @ems,
                                      :miq_group             => @user.current_group,
                                      :evm_owner             => @user,
                                      :storage               => @storage
                                     )

      allow(MiqEventDefinition).to receive_messages(:find_by => true)
      @ems.authentication_type(:default).update_attribute(:status, "Valid")
      @vm.scan
      job_item = MiqQueue.find_by(:class_name => "MiqAeEngine", :method_name => "deliver")
      job_item.delivered(*job_item.deliver)

      @job = Job.first
    end

    it "should start in a state of waiting_to_start" do
      expect(@job.state).to eq("waiting_to_start")
    end

    it "should start in a dispatch_status of pending" do
      expect(@job.dispatch_status).to eq("pending")
    end

    it "should respond properly to proxies4job" do
      expect(@vm.proxies4job[:message]).to eq("Perform SmartState Analysis on this VM")
    end

    it "#log_start_user_event_message" do
      allow(VmOrTemplate).to receive(:find).with(@vm.id).and_return(@vm)
      expect(@vm).to receive(:log_user_event).with(@job.start_user_event_message)
      @job.log_start_user_event_message
    end

    it "#log_end_user_event_message" do
      allow(VmOrTemplate).to receive(:find).with(@vm.id).and_return(@vm)
      expect(@vm).to receive(:log_user_event).with(@job.end_user_event_message).once
      @job.log_end_user_event_message
      @job.log_end_user_event_message
    end

    context "#create_scan_args" do
      it "should have no vmScanProfiles by default" do
        args = @job.create_scan_args
        expect(args["vmScanProfiles"]).to eq []
      end

      it "should have vmScanProfiles from scan_profiles option" do
        profiles = [{:name => 'default'}]
        @job.options[:scan_profiles] = profiles
        args = @job.create_scan_args
        expect(args["vmScanProfiles"]).to eq profiles
      end
    end

    context "#call_check_policy" do
      it "should raise vm_scan_start for Vm" do
        expect(MiqAeEvent).to receive(:raise_evm_event).with(
          "vm_scan_start",
          an_instance_of(ManageIQ::Providers::Vmware::InfraManager::Vm),
          an_instance_of(Hash),
          an_instance_of(Hash)
        )
        @job.call_check_policy
      end

      it "should raise vm_scan_start for template" do
        template = FactoryBot.create(
          :template_vmware,
          :name                  => "test_vm",
          :location              => "abc/abc.vmx",
          :raw_power_state       => 'poweredOn',
          :host                  => @host,
          :ext_management_system => @ems,
          :miq_group             => @user.current_group,
          :evm_owner             => @user,
          :storage               => @storage
        )

        Job.destroy_all # clear the first job from before section
        template.scan
        job_item = MiqQueue.find_by(:class_name => "MiqAeEngine", :method_name => "deliver")
        job_item.delivered(*job_item.deliver)

        job = Job.first

        expect(MiqAeEvent).to receive(:raise_evm_event).with(
          "vm_scan_start",
          an_instance_of(ManageIQ::Providers::Vmware::InfraManager::Template),
          an_instance_of(Hash),
          an_instance_of(Hash)
        )
        job.call_check_policy
      end
    end

    describe "#call_snapshot_create" do
      before { @job.miq_server_id = @server.id }

      it "does not call #create_snapshot but sends signal :snapshot_complete" do
        expect(@job).to receive(:signal).with(:snapshot_complete)
        expect(@job).not_to receive(:create_snapshot)
        @job.call_snapshot_create
      end

      context "if snapshot for scan required" do
        before do
          allow(@vm).to receive(:require_snapshot_for_scan?).and_return(true)
        end

        it "logs user event and sends signal :snapshot_complete" do
          expect(@job).not_to receive(:signal).with(:broker_unavailable)
          expect(@job).to receive(:signal).with(:snapshot_complete)
          expect(@job).to receive(:log_user_event)
          @job.call_snapshot_create
        end
      end

      context "if snapshot for scan not required" do
        it "logs user events: Initializing and sends signal :snapshot_complete" do
          allow(@vm).to receive(:require_snapshot_for_scan?).and_return(false)
          event_message = @job.start_user_event_message
          expect(@job).to receive(:signal).with(:snapshot_complete)
          expect(@job).to receive(:log_user_event).with(event_message, any_args)
          @job.call_snapshot_create
        end
      end
    end

    describe "#call_scan" do
      before do
        @job.miq_server_id = @server.id
        allow(VmOrTemplate).to receive(:find).with(@vm.id).and_return(@vm)
        allow(MiqServer).to receive(:find).with(@server.id).and_return(@server)
      end

      it "calls #scan_metadata on target VM and as result " do
        expect(@vm).to receive(:scan_metadata)
        @job.call_scan
      end

      it "triggers adding MiqServer#scan_metada to MiqQueue" do
        @job.call_scan
        queue_item = MiqQueue.where(:class_name => "MiqServer", :queue_name => "smartproxy").first
        expect(@server.id).to eq queue_item.instance_id
        expect(queue_item.args[0].vm_guid).to eq @vm.guid
      end

      it "updates job message" do
        allow(@vm).to receive(:scan_metadata)
        @job.call_scan
        expect(@job.message).to eq "Scanning for metadata from VM"
      end

      it "sends signal :abort if there is any error" do
        allow(@vm).to receive(:scan_metadata).and_raise("Any Error")
        expect(@job).to receive(:signal).with(:abort, any_args)
        @job.call_scan
      end
    end

    describe "#call_synchronize" do
      before do
        @job.miq_server_id = @server.id
        allow(VmOrTemplate).to receive(:find).with(@vm.id).and_return(@vm)
        allow(MiqServer).to receive(:find).with(@server.id).and_return(@server)
      end

      it "calls VmOrTemlate#synch_metadata with correct parameters" do
        expect(@vm).to receive(:sync_metadata).with(any_args, "taskid" => @job.jobid, "host" => @server)
        @job.call_synchronize
      end

      it "sends signal :abort if there is any error" do
        allow(@vm).to receive(:sync_metadata).and_raise("Any Error")
        expect(@job).to receive(:signal).with(:abort, any_args)
        @job.call_synchronize
      end

      it "does not updates job status" do
        expect(@job).to receive(:set_status).with("Synchronizing metadata from VM")
        @job.call_synchronize
      end

      it "executes Job#dispatch_finish" do
        expect(@job).to receive(:dispatch_finish)
        @job.call_synchronize
      end
    end

    describe "#call_snapshot_delete" do
      let(:snapshot_description) { "Snapshot description" }
      before do
        allow(VmOrTemplate).to receive(:find).with(@vm.id).and_return(@vm)
        @job.update(:state => 'snapshot_delete')
        @job.context[:snapshot_mor] = snapshot_description
        # always sent 'snapshot_complete'
        expect(@job).to receive(:signal).with(:snapshot_complete)
      end

      it "does not call 'delete_snapshot' if there is no provider this VM belongs to" do
        allow(@vm).to receive(:ext_management_system).and_return(false)
        expect(@job).not_to receive(:delete_snapshot)
        @job.call_snapshot_delete
        expect(@job.message).to eq "No Providers available to delete snapshot, skipping"
      end

      it "calls 'delete_snapshot'" do
        allow(@vm).to receive(:ext_management_system).and_return(true)
        expect(@job).to receive(:delete_snapshot)
        @job.call_snapshot_delete
        expect(@job.message).to eq "Snapshot deleted: reference: [#{snapshot_description}]"
      end
    end
  end

  private

  def assign_smartproxy_role_to_server(server)
    server_role = FactoryBot.create(
      :server_role,
      :name              => "smartproxy",
      :description       => "SmartProxy",
      :max_concurrent    => 1,
      :external_failover => false,
      :role_scope        => "zone"
    )
    FactoryBot.create(
      :assigned_server_role,
      :miq_server_id  => server.id,
      :server_role_id => server_role.id,
      :active         => true,
      :priority       => AssignedServerRole::DEFAULT_PRIORITY
    )
  end
end
