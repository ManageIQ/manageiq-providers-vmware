# Change Log

All notable changes to this project will be documented in this file.

## Unreleased - as of Sprint 55 end 2017-02-27

### Added
- Add support for WebMKS remote consoles accessible from the UI [(#13)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/13)
- Add vm_acquire_ticket for webmks console types [(#9)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/9)

### Changed
- Removed supports_snapshots? methods defined independently without using supportsFeatureMixin plugin [(#14)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/14)


### Fixed
- Use the dvportgroup config.key for the uid_ems [(#5)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/5)
- Fix wrong number of arguments error when opening MKS console [(#15)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/15)

## Unreleased - as of Sprint 54 end 2017-02-13

### Added
- Implements OrchestrationTemplate#deployment_options [(#8)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/8)

### Fixed
- Decode the dvSwitch and dvPortgroup name [(#4)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/4)
- Fix issue where EmsEvent.add_vc and add_vmware_vcloud methods no longer exists [(#7)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/7)
