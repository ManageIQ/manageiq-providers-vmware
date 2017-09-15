class ManageIQ::Providers::Vmware::InfraManager::MetricsCapture < ManageIQ::Providers::BaseManager::MetricsCapture
  include RbvmomiConnectMixin

  attr_accessor :perf_counters_to_collect, :perf_counters_by_id
  def initialize(ems, options = {})
    super ems

    @options = options

    @collect_interval   = options[:collect_interval] || 60
    @query_size         = options[:perf_query_size] || 250
    @format             = options[:format] || "csv"
    @interval           = options[:interval] || "20"
    @interval_name      = capture_interval_to_interval_name(interval)

    @perf_counters_to_collect = []
    @perf_counters_by_id = {}
  end

  def perf_counters_to_collect
    perf_counter_names = METRIC_CAPTURE_COUNTERS

    all_counters = perf_counter_info

    hash = perf_counters_by_name(all_counters)
    perf_counters_to_collect = perf_counter_names.map do |counter_name|
      hash[counter_name]
    end

    perf_counters_to_collect.each do |counter|
      perf_counters_by_id[counter.key] = counter
    end
  end

  def perf_collect_metrics(start_time, end_time = nil)
    _log.info("Collecting performance counters...")

    perf_query_options = {
      :interval   => interval,
      :format     => format,
      :start_time => start_time,
      :end_time   => end_time
    }

    _log.info("Capturing targets...")
    targets = capture_targets(target_options)
    _log.info("Capturing targets...Complete - Count [#{targets.count}]")

    _log.info("Collecting metrics...")
    entity_metrics = []
    targets.each_slice(query_size) do |vms|
      entity_metrics.concat(perf_query(perf_counters_to_collect, vms, perf_query_options))
    end
    _log.info("Collecting metrics...Complete")

    _log.info("Parsing metrics...")
    metrics_payload = entity_metrics.collect do |metric|
      counters       = {}
      counter_values = Hash.new { |h, k| h[k] = {} }

      processed_res = parse_metric(metric)
      processed_res.each do |res|
        full_vim_key = "#{res[:counter_id]}_#{res[:instance]}"

        counter_info = perf_counters_by_id[res[:counter_id]]

        counters[full_vim_key] = {
          :counter_key           => perf_counter_key(counter_info),
          :rollup                => counter_info.rollupType,
          :precision             => counter_info.unitInfo.key == "percent" ? 0.1 : 1,
          :unit_key              => counter_info.unitInfo.key,
          :vim_key               => res[:counter_id].to_s,
          :instance              => res[:instance],
          :capture_interval      => res[:interval],
          :capture_interval_name => capture_interval_to_interval_name(res[:interval]),
        }

        Array(res[:results]).each_slice(2) do |timestamp, value|
          counter_values[timestamp][full_vim_key] = value
        end
      end

      {
        :ems_id         => target.id,
        :ems_ref        => metric.entity._ref,
        :ems_klass      => vim_entity_to_miq_model(metric.entity),
        :interval_name  => interval_name,
        :start_range    => start_time,
        :end_range      => end_time,
        :counters       => counters,
        :counter_values => counter_values
      }
    end
    _log.info("Parsing metrics...Complete")

    _log.info("Collecting performance counters...Complete")

    metrics_payload
  end

  private

  attr_reader :collect_interval, :query_size, :options
  attr_reader :format, :interval, :interval_name

  METRIC_CAPTURE_COUNTERS = [
    :cpu_usage_rate_average,
    :cpu_usagemhz_rate_average,
    :mem_usage_absolute_average,
    :disk_usage_rate_average,
    :net_usage_rate_average,
    :sys_uptime_absolute_latest,
    :cpu_ready_delta_summation,
    :cpu_system_delta_summation,
    :cpu_wait_delta_summation,
    :cpu_used_delta_summation,
    :mem_vmmemctl_absolute_average,
    :mem_vmmemctltarget_absolute_average,
    :mem_swapin_absolute_average,
    :mem_swapout_absolute_average,
    :mem_swapped_absolute_average,
    :mem_swaptarget_absolute_average,
    :disk_devicelatency_absolute_average,
    :disk_kernellatency_absolute_average,
    :disk_queuelatency_absolute_average
  ].freeze

  def connection
    @connection ||= connect(ems_options)
  end

  def capture_interval_to_interval_name(interval)
    case interval
    when "20"
      "realtime"
    else
      "hourly"
    end
  end

  def vim_entity_to_miq_model(entity)
    case entity.class.wsdl_name
    when "VirtualMachine"
      "Vm"
    when "HostSystem"
      "Host"
    when "ClusterComputeResource"
      "EmsCluster"
    when "Datastore"
      "Storage"
    when "ResourcePool"
      "ResourcePool"
    end
  end

  def perf_counter_key(counter)
    group  = counter.groupInfo.key.downcase
    name   = counter.nameInfo.key.downcase
    rollup = counter.rollupType.downcase
    stats  = counter.statsType.downcase

    "#{group}_#{name}_#{stats}_#{rollup}".to_sym
  end

  def perf_counters_by_name(all_perf_counters)
    all_perf_counters.to_a.each_with_object({}) do |counter, hash|
      hash[perf_counter_key(counter)] = counter
    end
  end

  def perf_counter_info
    spec_set = [
      RbVmomi::VIM.PropertyFilterSpec(
        :objectSet => [
          RbVmomi::VIM.ObjectSpec(
            :obj => connection.serviceContent.perfManager,
          )
        ],
        :propSet   => [
          RbVmomi::VIM.PropertySpec(
            :type    => connection.serviceContent.perfManager.class.wsdl_name,
            :pathSet => ["perfCounter"]
          )
        ],
      )
    ]
    options = RbVmomi::VIM.RetrieveOptions()

    result = connection.propertyCollector.RetrievePropertiesEx(
      :specSet => spec_set, :options => options
    )

    return if result.nil? || result.objects.nil?

    object_content = result.objects.detect { |oc| oc.obj == connection.serviceContent.perfManager }
    return if object_content.nil?

    perf_counters = object_content.propSet.to_a.detect { |prop| prop.name == "perfCounter" }
    Array(perf_counters.try(:val))
  end

  def perf_query(perf_counters, entities, interval: "20", start_time: nil, end_time: nil, format: "normal", max_sample: nil)
    format = RbVmomi::VIM.PerfFormat(format)

    metrics = perf_counters.map do |counter|
      RbVmomi::VIM::PerfMetricId(:counterId => counter.key, :instance  => "*")
    end

    perf_query_spec_set = entities.collect do |entity|
      RbVmomi::VIM::PerfQuerySpec(
        :entity     => entity,
        :intervalId => interval,
        :format     => format,
        :metricId   => metrics,
        :startTime  => start_time,
        :endTime    => end_time,
        :maxSample  => max_sample,
      )
    end

    entity_metrics = connection.serviceContent.perfManager.QueryPerf(:querySpec => perf_query_spec_set)

    entity_metrics
  end

  def capture_targets(target_options = {})
    select_set = []
    prop_set   = []
    targets    = []

    unless target_options[:exclude_vms]
      select_set.concat(vm_traversal_specs)
      prop_set << vm_prop_spec
    end

    unless target_options[:exclude_hosts]
      select_set.concat(host_traversal_specs)
      prop_set << host_prop_spec
    end

    selection_spec_names = select_set.collect { |selection_spec| selection_spec.name }
    select_set << child_entity_traversal_spec(selection_spec_names)

    object_spec = RbVmomi::VIM.ObjectSpec(
      :obj       => connection.rootFolder,
      :selectSet => select_set
    )

    filter_spec = RbVmomi::VIM.PropertyFilterSpec(
      :objectSet => [object_spec],
      :propSet   => prop_set
    )

    options = RbVmomi::VIM.RetrieveOptions()

    result = connection.propertyCollector.RetrievePropertiesEx(
      :specSet => [filter_spec], :options => options
    )

    while result
      token = result.token

      result.objects.each do |object_content|
        case object_content.obj
        when RbVmomi::VIM::VirtualMachine
          vm_props = Array(object_content.propSet)
          next if vm_props.empty?

          vm_power_state = vm_props.detect { |prop| prop.name == "runtime.powerState" }
          next if vm_power_state.nil?

          next unless vm_power_state.val == "poweredOn"
        when RbVmomi::VIM::HostSystem
          host_props = Array(object_content.propSet)
          next if host_props.empty?

          host_connection_state = host_props.detect { |prop| prop.name == "runtime.connectionState" }
          next if host_connection_state.nil?

          next unless host_connection_state.val == "connected"
        end

        targets << object_content.obj
      end

      break if token.nil?

      result = connection.propertyCollector.ContinueRetrievePropertiesEx(:token => token)
    end

    targets
  end

  def datacenter_folder_traversal_spec(path)
    RbVmomi::VIM.TraversalSpec(
      :name => "tsDatacenter#{path}",
      :type => "Datacenter",
      :path => path,
      :skip => false,
      :selectSet => [
        RbVmomi::VIM.SelectionSpec(:name => "tsFolder")
      ]
    )
  end

  def vm_traversal_specs
    [datacenter_folder_traversal_spec("vmFolder")]
  end

  def compute_resource_to_host_traversal_spec
    RbVmomi::VIM.TraversalSpec(
      :name => "tsComputeResourceToHost",
      :type => "ComputeResource",
      :path => "host",
      :skip => false,
    )
  end

  def host_traversal_specs
    [
      datacenter_folder_traversal_spec("hostFolder"),
      compute_resource_to_host_traversal_spec
    ]
  end

  def child_entity_traversal_spec(selection_spec_names = [])
    select_set = selection_spec_names.map do |name|
      RbVmomi::VIM.SelectionSpec(:name => name)
    end

    RbVmomi::VIM.TraversalSpec(
      :name => 'tsFolder',
      :type => 'Folder',
      :path => 'childEntity',
      :skip => false,
      :selectSet => select_set,
    )
  end

  def vm_prop_spec
    RbVmomi::VIM.PropertySpec(
      :type    => "VirtualMachine",
      :pathSet => ["runtime.powerState"],
    )
  end

  def host_prop_spec
    RbVmomi::VIM.PropertySpec(
      :type    => "HostSystem",
      :pathSet => ["runtime.connectionState"],
    )
  end

  def parse_metric(metric)
    base = {
      :mor      => metric.entity._ref,
      :children => []
    }

    samples = CSV.parse(metric.sampleInfoCSV.to_s).first.to_a

    metric.value.to_a.collect do |value|
      id = value.id
      val = CSV.parse(value.value.to_s).first.to_a

      nh = {}.merge!(base)
      nh[:counter_id] = id.counterId
      nh[:instance]   = id.instance

      nh[:results] = []
      samples.each_slice(2).with_index do |(interval, timestamp), i|
        nh[:interval] ||= interval
        nh[:results] << timestamp
        nh[:results] << val[i].to_i
      end

      nh
    end
  end

  def ems_options
    {
      :ems      => @target,
      :host     => @target.address,
      :user     => @target.authentication_userid,
      :password => @target.authentication_password,
    }
  end

  def target_options
    {
      :exclude_hosts => @options[:exclude_hosts],
      :exclude_vms   => @options[:exclude_vms],
    }
  end
end
