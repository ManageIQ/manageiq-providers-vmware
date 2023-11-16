require ManageIQ::Providers::Vmware::Engine.root.join("workers/event_catcher/event_parser.rb").to_s

RSpec.describe EventParser do
  require "rbvmomi"

  context "with a general user event" do
    let(:event) { load_event("user_login_session_event") }

    it "parses the event" do
      expect(described_class.parse_event(event)).to include(
        :chain_id   => 13_782_694,
        :event_type => "UserLoginSessionEvent",
        :source     => "VC",
        :is_task    => false,
        :message    => a_string_including("User root logged in"),
        :username   => "root",
        :full_data  => hash_including(
          :chainId   => 13_782_694,
          :changeTag => "",
          :key       => 13_782_694,
          :locale    => "en",
          :sessionId => "52cbdd94-bf4a-ed81-2a2f-698e5bd83fe6",
          :userAgent => "HTTPClient/1.0 (2.8.3, ruby 2.7.6 (2022-04-12))",
          :userName  => "root"
        )
      )
    end
  end

  context "with a VM event" do
    let(:event) { load_event("virtual_machine_power_off_task_event") }

    it "sets vm_ems_ref, vm_name, host_ems_ref, and host_name" do
      expect(described_class.parse_event(event)).to include(
        :event_type   => "PowerOffVM_Task",
        :vm_ems_ref   => "vm-67544",
        :vm_name      => "event_test",
        :host_ems_ref => "host-6528",
        :host_name    => "esx1"
      )
    end
  end

  context "with an EventEx event" do
    context "with an eventTypeId" do
      let(:event) { load_event("virtual_machine_event_ex") }

      it "sets the event_type to the EventTypeId" do
        expect(described_class.parse_event(event)).to include(
          :event_type => "com.vmware.vc.HA.VmUnprotectedEvent",
          :message    => "Virtual machine event_test in cluster Cluster1 in DC1 is not vSphere HA Protected."
        )
      end
    end

    context "without an eventTypeId" do
      let(:event) { load_event("event_ex") }

      it "sets the event_type to EventEx" do
        expect(described_class.parse_event(event)).to include(
          :event_type => "EventEx",
          :message    => ""
        )
      end
    end
  end

  context "with a TaskEvent" do
    let(:event) { load_event("virtual_machine_power_on_task_event") }

    it "set is_task to true" do
      expect(described_class.parse_event(event)).to include(
        :is_task => true
      )
    end
  end

  # TODO: add events with sourceVm, srcTemplate, destName, destHost

  private

  def load_event(event_name)
    YAML.unsafe_load(File.read(event_data_dir.join("#{event_name}.yml")))
  end

  def event_data_dir
    @event_data_dir ||= Pathname.new(__dir__).join("data")
  end
end
