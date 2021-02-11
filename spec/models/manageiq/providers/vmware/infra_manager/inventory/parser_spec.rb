describe ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser do
  let(:ems)       { FactoryBot.create(:ems_vmware) }
  let(:saver)     { ManageIQ::Providers::Vmware::InfraManager::Inventory::Saver.new(:threaded => false) }
  let(:collector) { ManageIQ::Providers::Vmware::InfraManager::Inventory::Collector.new(ems, saver) }
  let(:persister) { ManageIQ::Providers::Vmware::InfraManager::Inventory::Persister::Targeted.new(ems) }
  let(:parser)    { described_class.new(collector, persister) }

  context "#parse_virtual_machine" do
    let(:rbvmomi_vm) do
      require "rbvmomi"
      RbVmomi::VIM::VirtualMachine(nil, "vm-1")
    end
    let(:vm_name)      { "my-vm" }
    let(:vm_uuid)      { "eaa1c3e0-e3b4-4811-8929-2fe40929051b" }
    let(:ipv4_address) { "127.0.1.1" }
    let(:ipv6_address) { "::ffff:127.0.0.1" }
    let(:vm_props) do
      {
        :config  => {},
        :guest   => {
          :ipStack => [],
          :net     => [
            RbVmomi::VIM::GuestNicInfo(
              :ipAddress => [ipv4_address, ipv6_address].compact,
              :ipConfig  => RbVmomi::VIM::NetIpConfigInfo(
                :ipAddress => [].tap do |addrs|
                  addrs << RbVmomi::VIM::NetIpConfigInfoIpAddress(:ipAddress => ipv4_address, :prefixLength => 22) if ipv4_address
                  addrs << RbVmomi::VIM::NetIpConfigInfoIpAddress(:ipAddress => ipv6_address, :prefixLength => 64) if ipv6_address
                end
              )
            )
          ]
        },
        :name    => vm_name,
        :summary => {
          :config => {
            :uuid       => vm_uuid,
            :vmPathName => "[Datastore] #{vm_name}/#{vm_name}.vmx"
          },
          :guest  => {
            :ipAddress => ipv4_address || ipv6_address
          }
        },
      }
    end

    context "with an ipv4 embedded ipv6 address" do
      let(:ipv4_address) { nil }

      it "sets the subnet_mask" do
        parser.parse_virtual_machine(rbvmomi_vm, "enter", vm_props)

        expect(persister.networks.data.first.data).to include(
          :ipaddress   => ipv4_address,
          :ipv6address => ipv6_address,
          :subnet_mask => "ffff:ffff:ffff:ffff::"
        )
      end
    end
  end
end
