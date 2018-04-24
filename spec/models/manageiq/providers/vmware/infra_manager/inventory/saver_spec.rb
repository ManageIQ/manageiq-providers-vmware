describe ManageIQ::Providers::Vmware::InfraManager::Inventory::Saver do
  let(:subject) { described_class.new }

  context "#start_thread" do
    before { subject.start_thread }
    after  { subject.send(:thread).try(:terminate) }

    it "creates a thread" do
      thread = subject.send(:thread)

      expect(thread).not_to be_nil
      expect(thread.alive?).to be_truthy
    end
  end

  context "#stop_thread" do
    context "without a running thread" do
      it "doesn't crash" do
        subject.stop_thread
      end
    end

    context "with a running thread" do
      before { subject.start_thread }

      it "stops a thread" do
        thread = subject.send(:thread)
        subject.stop_thread
        expect(thread.alive?).to be_falsy
      end
    end
  end

  context "#queue_save_inventory" do
  end
end
