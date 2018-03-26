class ManageIQ::Providers::Vmware::Inventory::Collector::CloudManager < ManageIQ::Providers::Vmware::Inventory::Collector
  VAPP_TEMPLATE_STATUS_READY = "8".freeze

  def orgs
    return @orgs if @orgs.any?
    @orgs = connection.organizations
  end

  def vdcs
    return @vdcs if @vdcs.any?
    @vdcs = orgs.each_with_object([]) do |org, res|
      res.concat(org.vdcs.all)
    end
  end

  def vapps
    return @vapps if @vapps.any?
    @vapps = vdcs.each_with_object([]) do |vdc, res|
      res.concat(vdc.vapps.all)
    end
  end

  def vms
    return @vms if @vms.any?
    @vms = vapps.each_with_object([]) do |vapp, res|
      # Remove this each loop, once fog api will be updated to send hostname and snapshot together with vms
      vapp.vms.each do |vm|
        res << {
          :vm       => vm,
          :hostname => vm.customization.try(:computer_name),
          :snapshot => connection.get_snapshot_section(vm.id).try(:data)
        }
      end
    end
  end

  def vapp_templates
    return @vapp_templates if @vapp_templates.any?
    @vapp_templates = orgs.each_with_object([]) do |org, res|
      org.catalogs.each do |catalog|
        next if !public_images? && catalog.is_published

        catalog.catalog_items.each do |item|
          # Skip all Catalog Items which are not vApp Templates (e.g. Media & Other)
          next unless item.vapp_template_id.starts_with?('vappTemplate-')
          next unless (t = item.vapp_template) && t.status == VAPP_TEMPLATE_STATUS_READY

          res << {
            :vapp_template => t,
            :is_published  => catalog.is_published,
            :content       => connection.get_vapp_template_ovf_descriptor(t.id).try(:body)
          }
        end
      end
    end
  end

  def images
    return @images if @images.any?
    @images = vapp_templates.each_with_object([]) do |template_obj, res|
      res.concat(template_obj[:vapp_template].vms.map { |image| { :image => image, :is_published => template_obj[:is_published] } })
    end
  end
end
