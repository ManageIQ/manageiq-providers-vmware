class ManageIQ::Providers::Vmware::Inventory::Parser::CloudManager < ManageIQ::Providers::Vmware::Inventory::Parser
  def parse
    vdcs
    vapps
    vms
    vapp_templates
    images
  end
end
