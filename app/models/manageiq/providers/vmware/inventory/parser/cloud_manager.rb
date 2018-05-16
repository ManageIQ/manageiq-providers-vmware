class ManageIQ::Providers::Vmware::Inventory::Parser::CloudManager < ManageIQ::Providers::Vmware::Inventory::Parser
  def parse
    vdcs
    vapps
    vms
    vapp_templates
    images
  end

  private

  def vdcs
    collector.vdcs.each do |vdc|
      persister.availability_zones.find_or_build(vdc.id).assign_attributes(
        :name => vdc.name
      )
    end
  end

  def vapps
    collector.vapps.each do |vapp|
      persister.orchestration_stacks.find_or_build(vapp.id).assign_attributes(
        :name        => vapp.name,
        :description => vapp.name,
        :status      => vapp.human_status,
      )
    end
  end

  def vms
    collector.vms.each do |vm|
      parsed_vm = persister.vms.find_or_build(vm[:vm].id).assign_attributes(
        :uid_ems                => vm[:vm].id,
        :name                   => vm[:vm].name,
        :hostname               => vm[:hostname],
        :vendor                 => 'vmware',
        :raw_power_state        => vm[:vm].status,
        :orchestration_stack    => persister.orchestration_stacks.lazy_find(vm[:vm].vapp_id),
        :snapshots              => [],
        :cpu_hot_add_enabled    => vm[:vm].cpu_hot_add,
        :memory_hot_add_enabled => vm[:vm].memory_hot_add,
      )

      if (resp = vm[:snapshot]) && (snapshot = resp.fetch_path(:body, :Snapshot))
        uid = "#{vm[:vm].id}_#{snapshot[:created]}"
        persister.snapshots.find_or_build_by(:vm_or_template => parsed_vm, :ems_ref => uid).assign_attributes(
          :name        => "#{vm[:vm].name} (snapshot)",
          :uid         => uid,
          :parent_uid  => vm[:vm].id,
          :create_time => Time.zone.parse(snapshot[:created]),
          :total_size  => snapshot[:size]
        )
      end

      hardware = persister.hardwares.find_or_build(parsed_vm).assign_attributes(
        :guest_os             => vm[:vm].operating_system,
        :guest_os_full_name   => vm[:vm].operating_system,
        :bitness              => vm[:vm].operating_system =~ /64-bit/ ? 64 : 32,
        :cpu_sockets          => vm[:vm].cpu / vm[:vm].cores_per_socket,
        :cpu_cores_per_socket => vm[:vm].cores_per_socket,
        :cpu_total_cores      => vm[:vm].cpu,
        :memory_mb            => vm[:vm].memory,
        :disk_capacity        => vm[:vm].hard_disks.inject(0) { |sum, x| sum + x.values[0] } * 1.megabyte,
      )

      vm[:vm].disks.all.select { |d| hdd? d.bus_type }.each_with_index do |disk, i|
        device_name = "Disk #{i}"
        persister.disks.find_or_build_by(:hardware => hardware, :device_name => device_name).assign_attributes(
          :device_name     => device_name,
          :device_type     => "disk",
          :disk_type       => controller_description(disk.bus_sub_type).sub(' controller', ''),
          :controller_type => controller_description(disk.bus_sub_type),
          :size            => disk.capacity * 1.megabyte,
          :location        => "#{vm[:vm].id}/#{disk.address}/#{disk.address_on_parent}/#{disk.id}",
          :filename        => "Disk #{i}"
        )
      end

      persister.operating_systems.find_or_build(parsed_vm).assign_attributes(
        :product_name => vm[:vm].operating_system,
      )
    end
  end

  def vapp_templates
    collector.vapp_templates.each do |vapp_template|
      persister.orchestration_templates.find_or_build(vapp_template[:vapp_template].id).assign_attributes(
        :name        => vapp_template[:vapp_template].name,
        :description => vapp_template[:vapp_template].description,
        :orderable   => true,
        :content     => "<!-- #{vapp_template[:vapp_template].id} -->\n#{vapp_template[:content]}",
      )
    end
  end

  def images
    collector.images.each do |image|
      persister.miq_templates.find_or_build(image[:image].id).assign_attributes(
        :uid_ems            => image[:image].id,
        :name               => image[:image].name,
        :vendor             => 'vmware',
        :raw_power_state    => 'never',
        :publicly_available => image[:is_published]
      )
    end
  end
end
