FactoryGirl.define do
  factory :ems_vmware_with_vcr_authentication, :parent => :ems_vmware_cloud do
    zone do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      zone
    end

    after(:build) do |ems|
      ems.hostname = Rails.application.secrets.vmware_cloud.try(:[], 'host') || 'vmwarecloudhost'
    end

    after(:create) do |ems|
      userid   = Rails.application.secrets.vmware_cloud.try(:[], 'userid') || 'VMWARE_CLOUD_USERID'
      password = Rails.application.secrets.vmware_cloud.try(:[], 'password') || 'VMWARE_CLOUD_PASSWORD'

      cred = {
        :userid   => userid,
        :password => password
      }

      ems.authentications << FactoryGirl.create(:authentication, cred)
    end
  end

  factory :ems_vmware_cloud_with_amqp_authentication, :parent => :ems_vmware_cloud do
    after(:create) do |x|
      x.authentications << FactoryGirl.create(:authentication, :authtype => 'amqp')
      x.endpoints       << FactoryGirl.create(:endpoint, :role => 'amqp')
    end
  end
end
