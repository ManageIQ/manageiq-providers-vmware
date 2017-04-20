FactoryGirl.define do
  factory :vim_broker_worker, :class => 'ManageIQ::Providers::Vmware::InfraManager::VimBrokerWorker' do
  end
end
