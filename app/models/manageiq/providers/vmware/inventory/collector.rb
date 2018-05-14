class ManageIQ::Providers::Vmware::Inventory::Collector < ManagerRefresh::Inventory::Collector
  require_nested :CloudManager
  require_nested :NetworkManager

  def initialize(_manager, _target)
    super

    initialize_inventory_sources
  end

  def initialize_inventory_sources
    @orgs                 = []
    @vdcs                 = []
    @vapps                = []
    @vms                  = []
    @vapp_templates       = []
    @images               = []
    @vdc_networks         = []
    @vapp_networks        = []
    @nics                 = []
    @network_routers      = []
    @vdc_networks_idx     = {}
    @network_name_mapping = {}
  end

  def connection
    @connection ||= manager.connect
  end

  def public_images?
    options.try(:get_public_images)
  end
end
