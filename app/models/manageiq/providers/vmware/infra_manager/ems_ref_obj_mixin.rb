module ManageIQ::Providers::Vmware::InfraManager::EmsRefObjMixin
  extend ActiveSupport::Concern

  def ems_ref_obj
    @ems_ref_obj ||= begin
      require "VMwareWebService/VimTypes"
      VimString.new(ems_ref, ems_ref_type, :ManagedObjectReference) if ems_ref.present? && ems_ref_type.present?
    end
  end

  def ems_ref=(val)
    @ems_ref_obj = nil
    super
  end
end
