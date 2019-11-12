module ManageIQ::Providers::Vmware::InfraManager::VmOrTemplateShared::Operations::Power
  extend ActiveSupport::Concern

  def raw_start
    run_command_via_parent(:vm_start)
  end

  def raw_stop
    run_command_via_parent(:vm_stop)
  end

  def raw_suspend
    run_command_via_parent(:vm_suspend)
  end
end
