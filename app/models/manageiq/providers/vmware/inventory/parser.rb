class ManageIQ::Providers::Vmware::Inventory::Parser < ManageIQ::Providers::Inventory::Parser
  require_nested :CloudManager
  require_nested :NetworkManager

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
