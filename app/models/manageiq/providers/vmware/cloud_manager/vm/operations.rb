module ManageIQ::Providers::Vmware::CloudManager::Vm::Operations
  extend ActiveSupport::Concern

  include_concern 'Power'
  include_concern 'Snapshot'

  included do
    supports :terminate do
      unsupported_reason_add(:terminate, "The VM is powered on") if vm_powered_on?
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
