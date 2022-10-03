FactoryBot.define do
  factory :snapshot_vmware, :class => "ManageIQ::Providers::Vmware::InfraManager::Snapshot", :parent => :snapshot do
    sequence(:ems_ref) { |n| "snapshot-#{seq_padded_for_sorting(n)}" }
    ems_ref_type { "Snapshot" }
  end
end
