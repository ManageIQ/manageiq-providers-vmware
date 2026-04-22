require "csv"

class ManageIQ::Providers::Vmware::InfraManager::MetricsCapture < ManageIQ::Providers::InfraManager::MetricsCapture
  VIM_INTERVAL_NAME_BY_MIQ_INTERVAL_NAME = {'hourly' => 'Past Month'}
  MIQ_INTERVAL_NAME_BY_VIM_INTERVAL_NAME = VIM_INTERVAL_NAME_BY_MIQ_INTERVAL_NAME.invert

  # Per VMware Documentation Large-Scale Performance Data Retrieval:
  # For the instance property, specify an asterisk ("*") to retrieve instance and aggregate data
  VIM_PERF_METRIC_ALL_INSTANCES = "*".freeze

  #
  # MiqVimPerfHistory methods (with caching)
  #

  cache_with_timeout(:perf_history_results,
                     -> { ::Settings.performance.vim_cache_ttl.to_i_with_method }
                    ) { Hash.new }

  def self.intervals(ems, perf_manager)
    phr = perf_history_results
    results = phr.fetch_path(:intervals, ems.id)
    return results unless results.nil?

    begin
      # Query historical intervals from perfManager
      results = perf_manager.historicalInterval.map do |interval|
        {
          'key'            => interval.key.to_s,
          'name'           => interval.name,
          'samplingPeriod' => interval.samplingPeriod.to_s,
          'length'         => interval.length.to_s,
          'level'          => interval.level.to_s,
          'enabled'        => interval.enabled.to_s
        }
      end
    rescue => err
      _log.error("EMS: [#{ems.hostname}] The following error occurred: [#{err}]")
      raise
    end

    _log.debug { "EMS: [#{ems.hostname}] Available sampling intervals: [#{results.length}]" }
    phr.store_path(:intervals, ems.id, results)
  end

  def self.realtime_interval(ems, perf_manager, mor)
    phr = perf_history_results
    results = phr.fetch_path(:realtime_interval, ems.id, mor)
    return results unless results.nil?

    begin
      # QueryPerfProviderSummary returns a PerfProviderSummary object
      summary = perf_manager.QueryPerfProviderSummary(:entity => mor)
    rescue => err
      _log.error("EMS: [#{ems.hostname}] The following error occurred: [#{err}]")
      raise
    end

    if summary&.currentSupported
      interval = summary.refreshRate.to_s
      _log.debug { "EMS: [#{ems.hostname}] Found realtime interval: [#{interval}] for mor: [#{mor}]" }
    else
      interval = nil
      _log.debug { "EMS: [#{ems.hostname}] Realtime is not supported for mor: [#{mor}], summary: [#{summary.inspect}]" }
    end

    phr.store_path(:realtime_interval, ems.id, mor, interval)
  end

  def self.hourly_interval(ems, perf_manager)
    phr = perf_history_results
    results = phr.fetch_path(:hourly_interval, ems.id)
    return results unless results.nil?

    # Using the reporting value of 'hourly', get the vim interval 'Past Month'
    #   and look for that in the intervals data
    vim_interval = VIM_INTERVAL_NAME_BY_MIQ_INTERVAL_NAME['hourly']

    intervals = self.intervals(ems, perf_manager)

    interval = intervals.detect { |i| i['name'].to_s.downcase == vim_interval.downcase }
    if interval.nil?
      _log.debug { "EMS: [#{ems.hostname}] Unable to find hourly interval [#{vim_interval}] in intervals: #{intervals.collect { |i| i['name'] }.inspect}" }
    else
      interval = interval['samplingPeriod'].to_s
      _log.debug { "EMS: [#{ems.hostname}] Found hourly interval: [#{interval}] for vim interval: [#{vim_interval}]" }
    end

    phr.store_path(:hourly_interval, ems.id, interval)
  end

  def self.counter_info_by_counter_id(ems, perf_manager)
    phr = perf_history_results
    results = phr.fetch_path(:counter_info_by_id, ems.id)
    return results unless results.nil?

    begin
      # perfManager.perfCounter returns an array of PerfCounterInfo objects
      counter_info = perf_manager.perfCounter
    rescue => err
      _log.error("EMS: [#{ems.hostname}] The following error occurred: [#{err}]")
      raise
    end

    # TODO: Move this to some generic parsing class, such as
    # ManageIQ::Providers::Vmware::InfraManager::RefreshParser
    results = counter_info.each_with_object({}) do |c, h|
      id       = c.key
      group    = c.groupInfo.key.to_s.downcase
      name     = c.nameInfo.key.to_s.downcase
      rollup   = c.rollupType.to_s.downcase
      stats    = c.statsType.to_s.downcase
      unit_key = c.unitInfo.key.to_s.downcase

      # VM disk info is primarily in the "virtualdisk" group where hosts use the
      # "disk" group.
      group = "disk" if group == "virtualdisk"

      counter_key = "#{group}_#{name}_#{stats}_#{rollup}"

      # Filter the metrics for only the cols we will use
      next unless Metric::Capture.capture_cols.include?(counter_key.to_sym)

      h[id] = {
        :counter_key => counter_key,
        :group       => group,
        :name        => name,
        :rollup      => rollup,
        :stats       => stats,
        :unit_key    => unit_key,
        :precision   => (unit_key == 'percent') ? 0.01 : 1,
      }
    end

    phr.store_path(:counter_info_by_id, ems.id, results)
  end

  #
  # Processing/Converting methods
  #

  def self.preprocess_data(data, counter_info = {}, counters_by_mor = {}, counter_values_by_mor_and_ts = {})
    # First process the results into a format we can consume
    processed_res = perf_raw_data_to_hashes(data)
    return unless processed_res.kind_of?(Array)

    # Next process each of the those results
    processed_res.each do |res|
      full_vim_key = "#{res[:counter_id]}_#{res[:instance]}"
      _log.debug { "Processing [#{res[:results].length / 2}] results for MOR: [#{res[:mor]}], instance: [#{res[:instance]}], capture interval [#{res[:interval]}], counter vim key: [#{res[:counter_id]}]" }

      counter = counter_info[res[:counter_id]]
      next if counter.nil?

      counter_data = {
        :counter_key           => counter[:counter_key],
        :rollup                => counter[:rollup],
        :precision             => counter[:precision],
        :unit_key              => counter[:unit_key],
        :vim_key               => res[:counter_id].to_s,
        :instance              => res[:instance],
        :capture_interval      => res[:interval],
        :capture_interval_name => res[:interval] == "20" ? "realtime" : "hourly"
      }

      counters_by_mor.store_path(res[:mor], full_vim_key, counter_data)

      hashes = perf_vim_data_to_hashes(res[:results])
      next if hashes.nil?
      hashes.each { |h| counter_values_by_mor_and_ts.store_path(res[:mor], h[:timestamp], full_vim_key, h[:counter_value]) }
    end
  end

  def self.perf_vim_data_to_hashes(vim_data)
    ret = []

    # The data is organized in an array such as [timestamp1, value1, timestamp2, value2, ...]
    Array.wrap(vim_data).each_slice(2) do |t, v|
      if t.kind_of?(String) # VimString
        t = t.to_s
      else
        _log.warn("Discarding unexpected time value in results: ts: [#{t.class.name}] [#{t}], value: #{v}")
        next
      end
      ret << {:timestamp => t, :counter_value => v}
    end
    ret
  end

  def self.perf_raw_data_to_hashes(data)
    # RbVmomi returns an array of PerfEntityMetric objects
    return [] unless data.kind_of?(Array)

    data.flat_map { |entity_metric| process_entity_metric(entity_metric) }
  end

  def self.process_entity_metric(entity_metric)
    mor = entity_metric.entity._ref

    # Parse CSV sample info: "interval,timestamp,interval,timestamp,..."
    sample_info_csv = parse_csv_safe(entity_metric.sampleInfoCSV.to_s)

    ret = []

    # Process each metric value series
    Array.wrap(entity_metric.value).each do |metric_series|
      counter_id = metric_series.id.counterId
      instance = metric_series.id.instance || ""

      # Get the interval from the first sample (first element in CSV)
      interval = sample_info_csv[0]

      # Parse CSV values
      values = metric_series.value.to_s.split(',').map(&:to_i)

      # Build results array with alternating timestamps and values
      results = values.each_with_index.flat_map do |value, idx|
        # CSV format: interval,timestamp pairs
        timestamp_idx = (idx * 2) + 1
        [sample_info_csv[timestamp_idx], value]
      end

      ret << {
        :mor        => mor,
        :counter_id => counter_id,
        :instance   => instance,
        :interval   => interval,
        :results    => results
      }
    end

    ret
  end

  def initialize(target, ems = nil)
    super(Array(target), ems || Array(target).first&.ext_management_system)

    raise ArgumentError, "At least one target must be passed"      if self.ems.nil? && targets.empty?
    raise ArgumentError, "All targets must be connected to an EMS" if self.ems.nil?
    raise ArgumentError, "All targets must be on the same EMS"     if targets.map(&:ems_id).any? { |ems_id| ems_id != self.ems.id }
  end

  #
  # Connect / Disconnect / Intialize methods
  #

  def perf_init_vim
    begin
      @perf_vim     = ems.vim_connect_rbvmomi
      @perf_manager = @perf_vim.serviceContent.perfManager
    rescue => err
      _log.error("Failed to initialize performance history from EMS: [#{ems.hostname}]: [#{err}]")
      perf_release_vim
      raise
    end
  end

  def perf_release_vim
    @perf_vim&.close
  rescue
    nil
  ensure
    @perf_manager = @perf_vim = nil
  end

  #
  # Capture methods
  #

  def perf_collect_metrics(interval_name, start_time = nil, end_time = nil)
    log_header = "[#{interval_name}] for: #{log_targets}"

    require 'httpclient'

    begin
      Benchmark.realtime_block(:vim_connect) { perf_init_vim }

      @perf_intervals = {}

      targets_by_mor   = targets.each_with_object({}) { |t, h| h[t.ems_ref_obj] = t }
      counter_info,    = Benchmark.realtime_block(:counter_info)       { self.class.counter_info_by_counter_id(ems, @perf_manager) }
      interval_by_mor, = Benchmark.realtime_block(:capture_intervals)  { perf_capture_intervals(targets_by_mor.keys, interval_name) }
      query_params,    = Benchmark.realtime_block(:build_query_params) { perf_build_query_params(interval_by_mor, counter_info, start_time, end_time) }
      counters_by_mor, counter_values_by_mor_and_ts = perf_query(query_params, counter_info)

      return counters_by_mor, counter_values_by_mor_and_ts
    rescue HTTPClient::ReceiveTimeoutError => err
      attempts ||= 0
      msg = "#{log_header} Timeout Error during metrics data collection: [#{err}], class: [#{err.class}]"
      if attempts < 3
        attempts += 1
        _log.warn("#{msg}...Retry attempt [#{attempts}]")
        _log.warn("#{log_header}   Timings before retry: #{Benchmark.current_realtime.inspect}")
        perf_release_vim
        retry
      end

      _log.error("#{msg}...Failed after [#{attempts}] retry attempts")
      _log.error("#{log_header}   Timings at time of error: #{Benchmark.current_realtime.inspect}")
      raise MiqException::MiqCommunicationsTimeoutError, err.message
    rescue Timeout::Error
      _log.error("#{log_header} Timeout Error during metrics data collection")
      _log.error("#{log_header}   Timings at time of error: #{Benchmark.current_realtime.inspect}")
      raise MiqException::MiqTimeoutError, err.message
    rescue Errno::ECONNREFUSED => err
      _log.error("#{log_header} Communications Error during metrics data collection: [#{err}], class: [#{err.class}]")
      _log.error("#{log_header}   Timings at time of error: #{Benchmark.current_realtime.inspect}")
      raise MiqException::MiqConnectionRefusedError, err.message
    rescue Exception => err
      _log.error("#{log_header} Unhandled exception during metrics data collection: [#{err}], class: [#{err.class}]")
      _log.error("#{log_header}   Timings at time of error: #{Benchmark.current_realtime.inspect}")
      _log.log_backtrace(err)
      raise
    ensure
      perf_release_vim
    end
  end

  def perf_capture_intervals(mors, interval_name)
    interval_by_mor = {}
    mors.each do |mor|
      interval = case interval_name
                 when 'realtime' then self.class.realtime_interval(ems, @perf_manager, mor)
                 when 'hourly'   then self.class.hourly_interval(ems, @perf_manager)
                 end

      @perf_intervals[interval] = interval_name
      interval_by_mor[mor] = interval
    end

    _log.debug { "Mapping of MOR to Intervals: #{interval_by_mor.inspect}" }
    interval_by_mor
  end

  def perf_build_query_params(interval_by_mor, counter_info, start_time, end_time)
    _log.info("Building query parameters...")

    perf_metric_id_set = counter_info.map do |counter_id, _counter_info|
      {
        :counterId => counter_id.to_s,
        :instance  => VIM_PERF_METRIC_ALL_INSTANCES,
      }
    end

    params = []
    interval_by_mor.each do |mor, interval|
      st, et = Metric::Helper.sanitize_start_end_time(interval, @perf_intervals[interval.to_s], start_time, end_time)

      param = {
        :entity     => mor,
        :intervalId => interval,
        :startTime  => st,
        :endTime    => et,
        :format     => "csv",
        :metricId   => perf_metric_id_set,
      }
      _log.debug { "Adding query params: #{param.inspect}" }
      params << param
    end

    _log.info("Building query parameters...Complete")

    params
  end

  def perf_query(params, counter_info)
    counters_by_mor = {}
    counter_values_by_mor_and_ts = {}
    return counters_by_mor, counter_values_by_mor_and_ts if params.blank?

    Benchmark.current_realtime[:num_vim_queries] = params.length

    _log.debug { "Starting request for [#{params.length}] item(s), #{params.inspect}" }

    # Convert params to RbVmomi PerfQuerySpec format and execute queries
    data, = Benchmark.realtime_block(:vim_execute_time) do
      query_specs = params.map do |param|
        RbVmomi::VIM.PerfQuerySpec(
          :entity     => param[:entity],
          :intervalId => param[:intervalId].to_i,
          :startTime  => param[:startTime],
          :endTime    => param[:endTime],
          :format     => param[:format],
          :metricId   => param[:metricId].map do |metric|
            RbVmomi::VIM.PerfMetricId(
              :counterId => metric[:counterId].to_i,
              :instance  => metric[:instance]
            )
          end
        )
      end

      @perf_manager.QueryPerf(:querySpec => query_specs)
    end

    _log.debug { "Finished request for [#{params.length}] item(s)" }

    Benchmark.realtime_block(:perf_processing) do
      self.class.preprocess_data(data, counter_info, counters_by_mor, counter_values_by_mor_and_ts)
    end

    return counters_by_mor, counter_values_by_mor_and_ts
  end

  class << self
    private

    def parse_csv_safe(str)
      if str.include?("\"")
        Array.wrap(CSV.parse(str).first)
      else
        str.split(",")
      end
    end
  end
end
