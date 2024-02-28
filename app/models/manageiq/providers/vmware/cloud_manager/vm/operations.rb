module ManageIQ::Providers::Vmware::CloudManager::Vm::Operations
  extend ActiveSupport::Concern
  include Power
  include Snapshot

  included do
    supports :terminate do
      if vm_powered_on?
        _("The VM is powered on")
      else
        unsupported_reason(:control)
      end
    end
  end

  def raw_destroy
    raise "VM has no #{ui_lookup(:table => "ext_management_systems")}, unable to destroy VM" unless ext_management_system
    ext_management_system.with_provider_connection do |service|
      response = service.delete_vapp(ems_ref)
      service.process_task(response.body)
    end
    update!(:raw_power_state => "off")
  end
end
