class ManageIQ::Providers::Vmware::InfraManager::MetricsCollectorWorker::Runner < ManageIQ::Providers::BaseManager::MetricsCollectorWorker::Runner
  def after_initialize
    @ems = ExtManagementSystem.find(@cfg[:ems_id])
    do_exit("Unable to find instance for EMS ID [#{@cfg[:ems_id]}].", 1) if @ems.nil?
    do_exit("EMS ID [#{@cfg[:ems_id]}] failed authentication check.", 1) unless @ems.authentication_check.first

    @metrics_capture = @ems.class::MetricsCapture.new(@ems)
    @metrics_capture.perf_counters_to_collect
    @start_time = Time.now - 5.minutes
  end

  def do_work
    metrics = @metrics_capture.perf_collect_metrics(@start_time)

    @start_time = Time.now
  end
end
