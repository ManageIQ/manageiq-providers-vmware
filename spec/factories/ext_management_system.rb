FactoryBot.define do
  factory :ems_vmware_with_vcr_authentication, :parent => :ems_vmware_cloud do
    zone { EvmSpecHelper.local_miq_server.zone }

    after(:build) do |ems|
      ems.hostname = "vmwarecloudhost"
    end

    after(:create) do |ems|
      userid   = "VMWARE_CLOUD_USERID"
      password = "VMWARE_CLOUD_PASSWORD"

      cred = {
        :userid   => userid,
        :password => password
      }

      ems.authentications << FactoryBot.create(:authentication, cred)
    end
  end

  factory :ems_vmware_cloud_with_amqp_authentication, :parent => :ems_vmware_cloud do
    after(:create) do |x|
      x.authentications << FactoryBot.create(:authentication, :authtype => 'amqp')
      x.endpoints       << FactoryBot.create(:endpoint, :role => 'amqp')
    end
  end

  factory :ems_vmware_tanzu, :class => "ManageIQ::Providers::Vmware::ContainerManager", :parent => :ems_container

  factory :ems_vmware_tanzu_with_vcr_authentication, :parent => :ems_vmware_tanzu do
    after(:create) do |ems|
      userid   = "VMWARE_TANZU_USERID"
      password = "VMWARE_TANZU_PASSWORD"

      ems.default_endpoint.update!(
        :hostname   => "vmware-tanzu-hostname",
        :verify_ssl => OpenSSL::SSL::VERIFY_NONE
      )

      ems.authentications << FactoryBot.create(
        :authentication,
        :authtype => "default",
        :userid   => userid,
        :password => password
      )
    end
  end
end
