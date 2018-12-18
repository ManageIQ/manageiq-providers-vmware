FactoryBot.define do
  factory :vm_vcloud, :class => "ManageIQ::Providers::Vmware::CloudManager::Vm", :parent => :vm_cloud do
    location        { |x| "[storage] #{x.name}/#{x.name}.vmx" }
    vendor          "vmware"
    raw_power_state "poweredOn"
  end
end
