class ManageIQ::Providers::Vmware::CloudManager::RefreshParser < ManageIQ::Providers::CloudManager::RefreshParser
  include ManageIQ::Providers::Vmware::RefreshHelperMethods

  # While parsing the VMWare catalog only those vapp templates whose status
  # is reported to be "8" are ready to be used. The documentation says this
  # status is POWERED_OFF, however the cloud director shows it as "Ready"
  VAPP_TEMPLATE_STATUS_READY = "8".freeze

  def initialize(ems, options = nil)
    @ems        = ems
    @connection = ems.connect
    @options    = options || {}
    @data       = {}
    @data_index = {}
    @inv        = Hash.new { |h, k| h[k] = [] }
  end

  def ems_inv_to_hashes
    log_header = "MIQ(#{self.class.name}.#{__method__}) Collecting data for EMS name: [#{@ems.name}] id: [#{@ems.id}]"

    $vcloud_log.info("#{log_header}...")

    get_ems
    get_orgs
    get_vdcs
    get_vapps
    get_vms
    get_vapp_templates
    get_images

    $vcloud_log.info("#{log_header}...Complete")

    @data
  end

  private

  def get_ems
    @ems.api_version = @connection.api_version
  end

  def get_orgs
    @inv[:orgs] = @connection.organizations.all.to_a
  end

  def get_vdcs
    @inv[:orgs].each do |org|
      @inv[:vdcs] += org.vdcs.all
    end

    process_collection(@inv[:vdcs], :availability_zones) { |vdc| parse_vdc(vdc) }
  end

  def get_vapps
    @inv[:vdcs].each do |vdc|
      @inv[:vapps] += vdc.vapps.all
    end

    process_collection(@inv[:vapps], :orchestration_stacks) { |vapp| parse_stack(vapp) }
  end

  def get_vms
    @inv[:vapps].each do |vapp|
      @inv[:vms] += vapp.vms.all
    end

    process_collection(@inv[:vms], :vms) { |vm| parse_vm(vm) }
  end

  def get_vapp_templates
    @inv[:orgs].each do |org|
      org.catalogs.each do |catalog|
        next if catalog.is_published && !@options.get_public_images

        catalog.catalog_items.each do |item|
          # Skip all Catalog Items which are not vApp Templates (e.g. Media & Other)
          next unless item.vapp_template_id.starts_with?('vappTemplate-')

          @inv[:vapp_templates] << {
            :vapp_template => item.vapp_template,
            :is_published  => catalog.is_published
          } if item.vapp_template.status == VAPP_TEMPLATE_STATUS_READY
        end
      end
    end

    process_collection(@inv[:vapp_templates], :orchestration_templates) { |vapp_template_obj| parse_vapp_template(vapp_template_obj[:vapp_template]) }
  end

  def get_images
    @inv[:vapp_templates].each do |template_obj|
      @inv[:images] += template_obj[:vapp_template].vms.map { |image| { :image => image, :is_published => template_obj[:is_published] } }
    end

    process_collection(@inv[:images], :vms) { |image_obj| parse_image(image_obj[:image], image_obj[:is_published]) }
  end

  def parse_vdc(vdc)
    id = vdc.id

    new_result = {
      :type    => "ManageIQ::Providers::Vmware::CloudManager::AvailabilityZone",
      :ems_ref => id,
      :name    => vdc.name
    }

    return id, new_result
  end

  def parse_vm(vm)
    status           = vm.status
    uid              = vm.id
    name             = vm.name
    hostname         = vm.customization.try(:computer_name)
    guest_os         = vm.operating_system
    bitness          = vm.operating_system =~ /64-bit/ ? 64 : 32
    cpus             = vm.cpu
    cores_per_socket = vm.cores_per_socket
    memory_mb        = vm.memory
    vapp_uid         = vm.vapp_id
    stack            = @data_index.fetch_path(:orchestration_stacks, vapp_uid)
    disk_capacity    = vm.hard_disks.inject(0) { |sum, x| sum + x.values[0] } * 1.megabyte
    cpu_hot_add      = vm.cpu_hot_add
    mem_hot_add      = vm.memory_hot_add

    disks = vm.disks.all.select { |d| hdd? d.bus_type }.each_with_index.map do |disk, i|
      {
        :device_name     => "Disk #{i}",
        :device_type     => "disk",
        :disk_type       => controller_description(disk.bus_sub_type).sub(' controller', ''),
        :controller_type => controller_description(disk.bus_sub_type),
        :size            => disk.capacity * 1.megabyte,
        :location        => "#{vm.id}/#{disk.address}/#{disk.address_on_parent}/#{disk.id}",
        :filename        => "Disk #{i}"
      }
    end

    new_result = {
      :type                   => ManageIQ::Providers::Vmware::CloudManager::Vm.name,
      :uid_ems                => uid,
      :ems_ref                => uid,
      :name                   => name,
      :hostname               => hostname,
      :location               => uid,
      :vendor                 => "vmware",
      :connection_state       => "connected",
      :raw_power_state        => status,
      :snapshots              => [parse_snapshot(vm)].compact,
      :cpu_hot_add_enabled    => cpu_hot_add,
      :memory_hot_add_enabled => mem_hot_add,

      :hardware            => {
        :guest_os             => guest_os,
        :guest_os_full_name   => guest_os,
        :bitness              => bitness,
        :cpu_sockets          => cpus / cores_per_socket,
        :cpu_cores_per_socket => cores_per_socket,
        :cpu_total_cores      => cpus,
        :memory_mb            => memory_mb,
        :disk_capacity        => disk_capacity,
        :disks                => disks,
      },

      :operating_system    => {
        :product_name => guest_os,
      },

      :orchestration_stack => stack,
    }

    return uid, new_result
  end

  def parse_stack(vapp)
    status   = vapp.human_status
    uid      = vapp.id
    name     = vapp.name

    new_result = {
      :type        => ManageIQ::Providers::Vmware::CloudManager::OrchestrationStack.name,
      :ems_ref     => uid,
      :name        => name,
      :description => name,
      :status      => status,
    }
    return uid, new_result
  end

  def parse_image(image, is_public)
    uid  = image.id
    name = image.name

    new_result = {
      :type               => ManageIQ::Providers::Vmware::CloudManager::Template.name,
      :uid_ems            => uid,
      :ems_ref            => uid,
      :name               => name,
      :location           => uid,
      :vendor             => "vmware",
      :raw_power_state    => "never",
      :publicly_available => is_public
    }

    return uid, new_result
  end

  def parse_vapp_template(vapp_template)
    uid = vapp_template.id

    # The content of the template is the OVF specification of the vApp template
    content = @connection.get_vapp_template_ovf_descriptor(uid).body
    # Prepend comment containing template uid which is then used istead of MD5 checksum.
    content = "<!-- #{uid} -->\n#{content}"

    new_result = {
      :type        => ManageIQ::Providers::Vmware::CloudManager::OrchestrationTemplate.name,
      :ems_ref     => uid,
      :name        => vapp_template.name,
      :description => vapp_template.description,
      :orderable   => true,
      :content     => content,
      # By default #save_orchestration_templates_inventory does not set the EMS
      # ID because templates are not EMS specific. We are setting the EMS
      # explicitly here, because vapps are specific to concrete EMS.
      :ems_id      => @ems.id
    }

    return uid, new_result
  end

  def parse_snapshot(vm)
    resp = @connection.get_snapshot_section(vm.id).data
    if (snapshot_resp = resp.fetch_path(:body, :Snapshot))
      {
        :name        => "#{vm.name} (snapshot)",
        :uid         => "#{vm.id}_#{snapshot_resp[:created]}",
        :ems_ref     => "#{vm.id}_#{snapshot_resp[:created]}",
        :parent_id   => vm.id,
        :parent_uid  => vm.id,
        :create_time => snapshot_resp[:created],
        :total_size  => snapshot_resp[:size]
      }
    else
      return nil
    end
  end

  # See https://pubs.vmware.com/vcd-80/index.jsp#com.vmware.vcloud.api.sp.doc_90/GUID-E1BA999D-87FA-4E2C-B638-24A211AB8160.html
  def controller_description(bus_subtype)
    case bus_subtype
    when 'buslogic'
      'BusLogic Parallel SCSI controller'
    when 'lsilogic'
      'LSI Logic Parallel SCSI controller'
    when 'lsilogicsas'
      'LSI Logic SAS SCSI controller'
    when 'VirtualSCSI'
      'Paravirtual SCSI controller'
    when 'vmware.sata.ahci'
      'SATA controller'
    else
      'IDE controller'
    end
  end

  # See https://pubs.vmware.com/vcd-80/index.jsp#com.vmware.vcloud.api.sp.doc_90/GUID-E1BA999D-87FA-4E2C-B638-24A211AB8160.html
  def hdd?(bus_type)
    [5, 6, 20].include?(bus_type)
  end
end
