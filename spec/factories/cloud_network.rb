FactoryBot.define do
  factory :cloud_network_vmware_vdc,
          :class  => "ManageIQ::Providers::Vmware::NetworkManager::CloudNetwork::OrgVdcNet",
          :parent => :cloud_network
  factory :cloud_network_vmware_vapp,
          :class  => "ManageIQ::Providers::Vmware::NetworkManager::CloudNetwork::VappNet",
          :parent => :cloud_network
end
