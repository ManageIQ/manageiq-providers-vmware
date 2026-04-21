describe ManageIQ::Providers::Vmware::InfraManager::MetricsCapture do
  let(:zone) { EvmSpecHelper.local_miq_server.zone }
  let(:ems)  { FactoryBot.create(:ems_vmware, :zone => zone) }

  describe "#perf_capture_object" do
    it "returns the correct class" do
      expect(ems.perf_capture_object.class).to eq(described_class)
    end
  end

  describe "#initialize" do
    context "with an active vm" do
      let(:vm) { FactoryBot.create(:vm_perf, :ext_management_system => ems) }

      it "passes" do
        expect { described_class.new(vm) }.not_to raise_exception
      end
    end

    context "with a disconnected vm" do
      let(:vm) { FactoryBot.create(:vm_perf, :ext_management_system => nil) }

      it "raises an exception" do
        expect { described_class.new(vm) }.to raise_exception(ArgumentError, "All targets must be connected to an EMS")
      end
    end

    context "with a vms on different EMSs" do
      let(:vm1) { FactoryBot.create(:vm_perf, :ext_management_system => ems) }
      let(:vm2) { FactoryBot.create(:vm_perf, :ext_management_system => FactoryBot.create(:ems_vmware)) }

      it "raises an exception" do
        expect { described_class.new([vm1, vm2]) }.to raise_exception(ArgumentError, "All targets must be on the same EMS")
      end
    end

    context "with no targets" do
      it "raises an exception" do
        expect { described_class.new([]) }.to raise_exception(ArgumentError, "At least one target must be passed")
      end
    end

    context "with an ems" do
      it "passes" do
        expect { described_class.new(nil, ems) }.not_to raise_exception
      end
    end
  end

  describe "#perf_collect_metrics" do
    let(:cassette_name) { "#{described_class.name}::#{interval_name}".underscore }
    let(:vm)            { FactoryBot.create(:vm_perf, :ext_management_system => ems, :ems_ref => "vm-1085") }
    let(:ems) do
      secrets = VcrSecrets.vmware_infra
      FactoryBot.create(:ems_vmware_with_authentication, :hostname => secrets.hostname, :verify_ssl => false, :zone => zone).tap do |ems|
        ems.update_authentication(:default => {:userid => secrets.username, :password => secrets.password})
      end
    end

    context "interval_name=realtime" do
      let(:interval_name) { "realtime" }
      let(:start_time)    { "2026-05-05T18:41:00Z" }

      it "should have collected counters and values" do
        counters_by_mor, counter_values_by_mor_and_ts = nil, nil

        VCR.use_cassette(cassette_name, :match_requests_on => [:body]) do
          counters_by_mor, counter_values_by_mor_and_ts = vm.perf_collect_metrics(interval_name, Time.parse(start_time).utc)
        end

        expect(counters_by_mor.length).to eq(1)
        expect(counter_values_by_mor_and_ts.length).to eq(1)

        counters = counters_by_mor[vm.ems_ref_obj]
        expect(counters.length).to eq(28)

        expected = [
          ["realtime", "cpu_ready_delta_summation",               ""],
          ["realtime", "cpu_ready_delta_summation",               "0"],
          ["realtime", "cpu_system_delta_summation",              ""],
          ["realtime", "cpu_usage_rate_average",                  ""],
          ["realtime", "cpu_usagemhz_rate_average",               "0"],
          ["realtime", "cpu_usagemhz_rate_average",               ""],
          ["realtime", "cpu_used_delta_summation",                ""],
          ["realtime", "cpu_used_delta_summation",                "0"],
          ["realtime", "cpu_wait_delta_summation",                ""],
          ["realtime", "cpu_wait_delta_summation",                "0"],
          ["realtime", "disk_totalreadlatency_absolute_average",  "scsi0:0"],
          ["realtime", "disk_totalwritelatency_absolute_average", "scsi0:0"],
          ["realtime", "disk_usage_rate_average",                 ""],
          ["realtime", "mem_swapin_absolute_average",             ""],
          ["realtime", "mem_swapout_absolute_average",            ""],
          ["realtime", "mem_swapped_absolute_average",            ""],
          ["realtime", "mem_swaptarget_absolute_average",         ""],
          ["realtime", "mem_usage_absolute_average",              ""],
          ["realtime", "mem_vmmemctl_absolute_average",           ""],
          ["realtime", "mem_vmmemctltarget_absolute_average",     ""],
          ["realtime", "net_usage_rate_average",                  "vmnic3"],
          ["realtime", "net_usage_rate_average",                  "vmnic1"],
          ["realtime", "net_usage_rate_average",                  ""],
          ["realtime", "net_usage_rate_average",                  "vmnic0"],
          ["realtime", "net_usage_rate_average",                  "vmnic4"],
          ["realtime", "net_usage_rate_average",                  "vmnic2"],
          ["realtime", "net_usage_rate_average",                  "4000"],
          ["realtime", "sys_uptime_absolute_latest",              ""]
        ]

        selected = counters.values.collect { |c| c.values_at(:capture_interval_name, :counter_key, :instance) }
        expect(selected).to match_array(expected)

        counter_values = counter_values_by_mor_and_ts[vm.ems_ref_obj]
        timestamps     = counter_values.keys.sort
        expect(timestamps.first).to eq("2026-05-05T18:41:00Z")
        expect(timestamps.last).to  eq("2026-05-05T19:40:40Z")

        # Check every timestamp is present
        expect(counter_values.length).to eq(180)

        ts = timestamps.first
        until ts > timestamps.last
          expect(counter_values.key?(ts)).to be_truthy
          ts = (Time.parse(ts).utc + 20.seconds).iso8601
        end

        # Check a few specific values

        # Since the key for each counter value is a vim counter id, we have to
        #   remove that from the comparison.  The format is:
        #   [[ts, sorted_values], [ts, sorted_values], ...]
        expected = [
          ["2026-05-05T18:45:40Z", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 27, 27, 34, 39, 173, 281, 281, 299, 19_692, 19_692, 4_894_531]],
          ["2026-05-05T18:50:40Z", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 29, 30, 30, 35, 99, 152, 259, 259, 19_710, 19_710, 4_894_831]],
          ["2026-05-05T18:55:40Z", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 35, 35, 40, 50, 217, 299, 355, 355, 19_612, 19_612, 4_895_131]]
        ]
        selected = expected.transpose[0].collect { |k| [k, counter_values[k].values.sort] }

        expect(selected).to match_array(expected)
      end

      it "should have collected performances" do
        VCR.use_cassette(cassette_name, :match_requests_on => [:body]) do
          vm.perf_capture(interval_name, Time.parse(start_time).utc)
        end

        # Check Vm record was updated
        expect(vm.reload.last_perf_capture_on.utc.iso8601).to eq("2026-05-05T19:40:40Z")

        # Check performances
        expect(Metric.count).to eq(180)

        # Check every timestamp is present; performance realtime timestamps
        #   are to the nearest 20 second interval
        ts = start_time
        Metric.order(:timestamp).each do |p|
          p_ts = p.timestamp.utc
          expect(p_ts.iso8601).to eq(ts)
          ts = (p_ts + 20.seconds).iso8601
        end

        # Check a few specific values
        expected = [
          {"timestamp" => Time.parse("2026-05-05T18:41:00Z").utc, "capture_interval" => 20, "resource_type" => "VmOrTemplate", "mem_swapin_absolute_average" => 0.0, "sys_uptime_absolute_latest" => 4_894_251.0, "disk_usage_rate_average" => 0.0, "cpu_usagemhz_rate_average" => 39.0, "cpu_wait_delta_summation" => 19_712.0, "cpu_used_delta_summation" => 256.0, "capture_interval_name" => "realtime", "mem_vmmemctl_absolute_average" => 0.0, "mem_swapped_absolute_average" => 0.0, "mem_swaptarget_absolute_average" => 0.0, "mem_swapout_absolute_average" => 0.0, "resource_name" => "MIQ-WEBSVR1", "net_usage_rate_average" => 0.0, "mem_vmmemctltarget_absolute_average" => 0.0},
          {"timestamp" => Time.parse("2026-05-05T18:42:00Z").utc, "capture_interval" => 20, "resource_type" => "VmOrTemplate", "mem_swapin_absolute_average" => 0.0, "sys_uptime_absolute_latest" => 4_894_311.0, "disk_usage_rate_average" => 0.0, "cpu_usagemhz_rate_average" => 49.0, "cpu_wait_delta_summation" => 19_637.0, "cpu_used_delta_summation" => 331.0, "capture_interval_name" => "realtime", "mem_vmmemctl_absolute_average" => 0.0, "mem_swapped_absolute_average" => 0.0, "mem_swaptarget_absolute_average" => 0.0, "mem_swapout_absolute_average" => 0.0, "resource_name" => "MIQ-WEBSVR1", "net_usage_rate_average" => 0.0, "mem_vmmemctltarget_absolute_average" => 0.0},
          {"timestamp" => Time.parse("2026-05-05T18:43:00Z").utc, "capture_interval" => 20, "resource_type" => "VmOrTemplate", "mem_swapin_absolute_average" => 0.0, "sys_uptime_absolute_latest" => 4_894_371.0, "disk_usage_rate_average" => 0.0, "cpu_usagemhz_rate_average" => 37.0, "cpu_wait_delta_summation" => 19_698.0, "cpu_used_delta_summation" => 278.0, "capture_interval_name" => "realtime", "mem_vmmemctl_absolute_average" => 0.0, "mem_swapped_absolute_average" => 0.0, "mem_swaptarget_absolute_average" => 0.0, "mem_swapout_absolute_average" => 0.0, "resource_name" => "MIQ-WEBSVR1", "net_usage_rate_average" => 0.0, "mem_vmmemctltarget_absolute_average" => 0.0}
        ]

        selected = Metric.where(:timestamp => ["2026-05-05T18:41:00Z", "2026-05-05T18:42:00Z", "2026-05-05T18:43:00Z"]).order(:timestamp)
        selected.each_with_index do |p, i|
          expected[i].each do |k, v|
            if v.kind_of?(Float)
              expect(p.send(k)).to be_within(0.00001).of(v), "ts=#{p.timestamp} key=#{k} val=#{p.send(k)}"
            else
              expect(p.send(k)).to eq(v), "ts=#{p.timestamp} key=#{k} val=#{p.send(k)}"
            end
          end
        end
      end
    end

    context "interval_name=hourly" do
      let(:interval_name) { "hourly" }
      let(:start_time)    { "2026-04-21T012:00:00Z" }

      it "should have collected hourly metrics" do
        VCR.use_cassette(cassette_name, :match_requests_on => [:body]) do
          vm.perf_capture(interval_name, Time.parse(start_time).utc)
        end

        expect(vm.reload.last_perf_capture_on).to eq("2026-04-21T14:00:00Z")
        expect(vm.metric_rollups.count).to eq(5)

        expect(MetricRollup.order(:timestamp).pluck(:cpu_usage_rate_average)).to     match_array([2.42, 2.37, 2.45, 2.395, 2.41])
        expect(MetricRollup.order(:timestamp).pluck(:cpu_usagemhz_rate_average)).to  match_array([55.0, 54.0, 56.0, 54.5, 55.0])
        expect(MetricRollup.order(:timestamp).pluck(:mem_usage_absolute_average)).to match_array([0.99, 0.99, 0.99, 0.99, 0.99])
      end
    end
  end
end
