describe ManageIQ::Providers::Vmware::InfraManager::SelectorSpec do
  it ".selected_property?" do
    selector_spec = {
      :ems_refresh_vm => [
        "config.extraConfig[*].key",
        "config.hardware.device[*].backing.compatibilityMode",
        "summary.guest.hostName",
        "summary.runtime.powerState"
      ]
    }

    stub_const('ManageIQ::Providers::Vmware::InfraManager::SelectorSpec::VIM_SELECTOR_SPEC', selector_spec)

    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "summary.runtime.powerState")).to be_truthy
    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "summary.runtime")).to be_truthy
    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "summary")).to be_truthy

    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "summary.runtime.power")).to be_falsey
    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "summary.run")).to be_falsey
    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "sum")).to be_falsey

    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "config.hardware.device[2000].backing.compatibilityMode"))
      .to be_truthy
    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "config.hardware.device[2000].backing")).to be_truthy
    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "config.hardware.device[2000]")).to be_truthy
    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "config.hardware.device")).to be_truthy

    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "config.hardware.device[2000].back")).to be_falsey
    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "config.hardware.dev")).to be_falsey

    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "config.extraConfig[\"vmsafe.enable\"].key")).to be_truthy
    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "config.extraConfig[\"vmsafe.enable\"]")).to be_truthy
    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "config.extraConfig")).to be_truthy

    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "summary.guest")).to be_truthy
    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:vm, "summary.guest.disk")).to be_falsey

    expect(ManageIQ::Providers::Vmware::InfraManager::SelectorSpec.selected_property?(:other, "does.not.matter")).to be_falsey
  end
end
