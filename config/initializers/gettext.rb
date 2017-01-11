Vmdb::Gettext::Domains.add_domain(
  'ManageIQ_Providers_Vmware',
  ManageIQ::Providers::Vmware::Engine.root.join('locale').to_s,
  :po
)
