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

  def self.intervals(ems, vim_hist)
    phr = perf_history_results
    results = phr.fetch_path(:intervals, ems.id)
    return results unless results.nil?

    begin
      results = vim_hist.intervals
    rescue Handsoap::Fault, StandardError => err
      _log.error("EMS: [#{ems.hostname}] The following error occurred: [#{err}]")
      raise
    end

    _log.debug { "EMS: [#{ems.hostname}] Available sampling intervals: [#{results.length}]" }
    phr.store_path(:intervals, ems.id, results)
  end

  def self.realtime_interval(ems, vim_hist, mor)
    phr = perf_history_results
    results = phr.fetch_path(:realtime_interval, ems.id, mor)
    return results unless results.nil?

    begin
      summary = vim_hist.queryProviderSummary(mor)
    rescue Handsoap::Fault, StandardError => err
      _log.error("EMS: [#{ems.hostname}] The following error occurred: [#{err}]")
      raise
    end

    if summary.kind_of?(Hash) && summary['currentSupported'].to_s == "true"
      interval = summary['refreshRate'].to_s
      _log.debug { "EMS: [#{ems.hostname}] Found realtime interval: [#{interval}] for mor: [#{mor}]" }
    else
      interval = nil
      _log.debug { "EMS: [#{ems.hostname}] Realtime is not supported for mor: [#{mor}], summary: [#{summary.inspect}]" }
    end

    phr.store_path(:realtime_interval, ems.id, mor, interval)
  end

  def self.hourly_interval(ems, vim_hist)
    phr = perf_history_results
    results = phr.fetch_path(:hourly_interval, ems.id)
    return results unless results.nil?

    # Using the reporting value of 'hourly', get the vim interval 'Past Month'
    #   and look for that in the intervals data
    vim_interval = VIM_INTERVAL_NAME_BY_MIQ_INTERVAL_NAME['hourly']

    intervals = self.intervals(ems, vim_hist)

    interval = intervals.detect { |i| i['name'].to_s.downcase == vim_interval.downcase }
    if interval.nil?
      _log.debug { "EMS: [#{ems.hostname}] Unable to find hourly interval [#{vim_interval}] in intervals: #{intervals.collect { |i| i['name'] }.inspect}" }
    else
      interval = interval['samplingPeriod'].to_s
      _log.debug { "EMS: [#{ems.hostname}] Found hourly interval: [#{interval}] for vim interval: [#{vim_interval}]" }
    end

    phr.store_path(:hourly_interval, ems.id, interval)
  end

  def self.counter_info_by_counter_id(ems, vim_hist)
    phr = perf_history_results
    results = phr.fetch_path(:counter_info_by_id, ems.id)
    return results unless results.nil?

    begin
      counter_info = vim_hist.id2Counter
    rescue Handsoap::Fault, StandardError => err
      _log.error("EMS: [#{ems.hostname}] The following error occurred: [#{err}]")
      raise
    end

    # TODO: Move this to some generic parsing class, such as
    # ManageIQ::Providers::Vmware::InfraManager::RefreshParser
    results = counter_info.each_with_object({}) do |(id, c), h|
      group    = c.fetch_path('groupInfo', 'key').to_s.downcase
      name     = c.fetch_path('nameInfo', 'key').to_s.downcase
      rollup   = c['rollupType'].to_s.downcase
      stats    = c['statsType'].to_s.downcase
      unit_key = c.fetch_path('unitInfo', 'key').to_s.downcase

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
    # Query perf with single instance single entity
    return [{:results => data}] if single_instance_and_entity?(data)

    # Query perf composite or Query perf with multiple instances, single entity
    return process_entity(data) if composite_or_multi_instance_and_single_entity?(data)

    # Query perf multi (multiple entities, instance(s))
    return data.collect { |base| process_entity(base) }.flatten if single_or_multi_instance_and_multi_entity?(data)
  end

  def self.single_instance_and_entity?(data)
    data.respond_to?(:first) && data.first.kind_of?(DateTime)
  end

  def self.composite_or_multi_instance_and_single_entity?(data)
    data.respond_to?(:has_key?) && data.key?('entity')
  end

  def self.single_or_multi_instance_and_multi_entity?(data)
    !single_instance_and_entity?(data) && data.respond_to?(:first)
  end

  def self.process_entity(data, parent = nil)
    mor = data['entity']

    # Set up the common attributes for each value in the result array
    base = {
      :mor      => mor,
      :children => []
    }
    base[:parent] = parent unless parent.nil?

    if data.key?('childEntity')
      raise 'composite is not supported yet'
    end

    values = Array.wrap(data['value'])
    samples = parse_csv_safe(data['sampleInfoCSV'].to_s)

    ret = []
    values.each do |v|
      id, v = v.values_at('id', 'value')
      v = parse_csv_safe(v.to_s)

      nh = {}.merge!(base)
      nh[:counter_id] = id['counterId']
      nh[:instance]   = id['instance']

      nh[:results] = []
      samples.each_slice(2).with_index do |(interval, timestamp), i|
        nh[:interval] ||= interval
        nh[:results] << timestamp
        nh[:results] << v[i].to_i
      end

      ret << nh
    end
    ret
  end

  alias targets target
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
      @perf_vim      = ems.connect
      @perf_vim_hist = @perf_vim.getVimPerfHistory
    rescue => err
      _log.error("Failed to initialize performance history from EMS: [#{ems.hostname}]: [#{err}]")
      perf_release_vim
      raise
    end
  end

  def perf_release_vim
    @perf_vim_hist.release if @perf_vim_hist rescue nil
    @perf_vim.disconnect   if @perf_vim      rescue nil
    @perf_vim_hist = @perf_vim = nil
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
      counter_info,    = Benchmark.realtime_block(:counter_info)       { self.class.counter_info_by_counter_id(ems, @perf_vim_hist) }
      interval_by_mor, = Benchmark.realtime_block(:capture_intervals)  { perf_capture_intervals(targets_by_mor.keys, interval_name) }
      query_params,    = Benchmark.realtime_block(:build_query_params) { perf_build_query_params(interval_by_mor, counter_info, start_time, end_time) }
      counters_by_mor, counter_values_by_mor_and_ts = perf_query(query_params, counter_info, interval_name)

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
                 when 'realtime' then self.class.realtime_interval(ems, @perf_vim_hist, mor)
                 when 'hourly'   then self.class.hourly_interval(ems, @perf_vim_hist)
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

  def perf_query(params, counter_info, interval_name)
    counters_by_mor = {}
    counter_values_by_mor_and_ts = {}
    return counter_values_by_mor_and_ts if params.blank?

    Benchmark.current_realtime[:num_vim_queries] = params.length
    _log.debug { "Total item(s) to be requested: [#{params.length}], #{params.inspect}" }

    query_size = Metric::Capture.concurrent_requests(interval_name)
    vim_trips = 0
    params.each_slice(query_size) do |query|
      vim_trips += 1

      _log.debug { "Starting request for [#{query.length}] item(s), #{query.inspect}" }
      data, = Benchmark.realtime_block(:vim_execute_time) { @perf_vim_hist.queryPerfMulti(query) }
      _log.debug { "Finished request for [#{query.length}] item(s)" }

      Benchmark.realtime_block(:perf_processing) do
        self.class.preprocess_data(data, counter_info, counters_by_mor, counter_values_by_mor_and_ts)
      end
    end
    Benchmark.current_realtime[:num_vim_trips] = vim_trips

    return counters_by_mor, counter_values_by_mor_and_ts
  end

  private

  def log_targets
    if targets.size == 1
      "[#{targets.first.class.name}], [#{targets.first.id}], [#{targets.first.name}]"
    else
      "[#{targets.map { |obj| obj.class.name }.uniq.join(", ")}], [#{targets.size} targets]"
    end
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
