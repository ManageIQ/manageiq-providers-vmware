require ManageIQ::Providers::Vmware::Engine.root.join("workers/event_catcher/event_catcher.rb").to_s

RSpec.describe EventCatcher do
  require "logger"

  let(:ems) { {"name" => "vcenter", "type" => "ManageIQ::Providers::Vmware::InfraManager"} }
  let(:endpoint) { {"role" => "default"} }
  let(:authentication) { {"role" => "default"} }
  let(:messaging) { {:host => "localhost", :port => 9092, :protocol => "Kafka", :encoding => "json", :username => "admin", :password => "smartvm"} }
  let(:settings) { {"ems" => {"ems_vmware" => {"blacklisted_event_names" => blacklisted_event_names}}}}
  let(:logger) { Logger.new(nil) }
  let(:blacklisted_event_names) { %w[UserLoginSessionEvent UserLogoutSessionEvent] }
  let(:subject) { described_class.new(ems, endpoint, authentication, settings, messaging, logger) }

  describe "#filtered? (private)" do
    let(:parsed_event) { {:event_type => event_type} }

    context "with an event that isn't filtered" do
      let(:event_type) { "TaskEvent" }

      it "returns falsey" do
        expect(subject.send(:filtered?, parsed_event)).to be_falsey
      end
    end

    context "with a filtered event" do
      let(:event_type) { "UserLoginSessionEvent" }

      it "returns truthy" do
        expect(subject.send(:filtered?, parsed_event)).to be_truthy
      end
    end
  end
end
