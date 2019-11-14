module ManageIQ::Providers::Vmware::InfraManager::EmsRefObjMixin
  extend ActiveSupport::Concern

  def ems_ref_obj
    @ems_ref_obj ||= VimString.new(ems_ref, ems_ref_type, :ManagedObjectReference)
  end
end
