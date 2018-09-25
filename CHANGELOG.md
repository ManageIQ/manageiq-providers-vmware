# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)


## Unreleased as of Sprint 95 ending 2018-09-24

### Added
- Shift fog-vcloud-director version to 0.3.0 [(#321)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/321)

### Fixed
- Don't require cloud tenant upon vApp instantiation [(#322)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/322)

## Unreleased as of Sprint 94 ending 2018-09-10

### Added
- Moving Inventory Builder functionality to Inventory [(#316)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/316)

## Gaprindashvili-5 - Released 2018-09-07

### Fixed
- Try to get VM UUID from summary.config or config [(#246)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/246)
- Use the full URI for the broker connection [(#305)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/305)

## Unreleased as of Sprint 93 ending 2018-08-27

### Added
- Add plugin display name [(#312)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/312)
- Don't run EmsRefresh if using streaming refresh [(#284)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/284)

## Unreleased as of Sprint 92 ending 2018-08-13

### Fixed
- Fix for broken customization(sysprep) during vm provisioning [(#308)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/308)

## Unreleased as of Sprint 91 ending 2018-07-30

### Added
- Change custom_attributes hosts_guest_devices and host_system_services according to core [(#303)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/303)

### Fixed
- Fix setting the last_refresh_date on error [(#301)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/301)

## Unreleased as of Sprint 90 ending 2018-07-16

### Added
- Log error and backtrace if save_inventory fails [(#297)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/297)
- Set the ems last_refresh error/time attributes [(#296)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/296)
- Allow streaming refresh to be enabled dynamically [(#295)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/295)
- Add debug logging for object updates from the VC [(#293)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/293)

## Gaprindashvili-4 - Released 2018-07-16

### Added
- Enhance disk and CPU inventoring [(#261)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/261)
- Shift fog-vcloud-director gem version [(#267)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/267)
- Support CPU/MEM/HDD reconfiguration [(#231)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/231)
- Reconfigure VM network connectivity aka. NICs [(#272)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/272)
- Resize disk from reconfigure screen [(#164)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/164)
- Reconfigure VM: Add / Remove Network Adapters [(#163)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/163)
- Inventory VM's hostname as part of name [(#281)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/281)
- Recognize deployed vApp even if not powered on [(#273)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/273)
- Split vApp provisioning customization into three tabs [(#242)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/242)
- Implement graph inventory refresh for cloud manager [(#217)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/217)

### Fixed
- Bump version of vmware_web_service [(#247)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/247)

## Unreleased as of Sprint 89 ending 2018-07-02

### Added
- Add the ability to rename a VM [(#291)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/291)
- Add alias for vm_remove_disk_by_file [(#290)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/290)
- Add method vm_move_into_folder. [(#285)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/285)
- Finish parsing of host properties [(#280)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/280)

## Unreleased as of Sprint 88 ending 2018-06-18

### Fixed
- Change expected partial refresh error expection [(#286)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/286)

## Unreleased as of Sprint 87 ending 2018-06-04

### Added
- Parse the VirtualEthernetCard model type [(#279)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/279)
- Don't cache host config.storageDevice [(#278)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/278)
- Add ems_ref_obj to streaming refresh parser [(#275)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/275)
- Parse the lan from a guest_device [(#266)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/266)

## Unreleased as of Sprint 86 ending 2018-05-21

### Added
- Parse VM Snapshots [(#270)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/270)
- Improve streaming refresh in a Refresh Worker [(#265)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/265)
- Set the root folder's parent and set hidden/is_default for folders and resource pools [(#263)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/263)
- Make nested lazy find with secondary ref work [(#262)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/262)
- Set api_version and uid_ems in streaming refresh [(#259)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/259)
- Use new interface for targeted_scope [(#258)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/258)
- Fix storage parsing to use datastore url [(#256)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/256)
- Add spec test for deleting a VM [(#255)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/255)
- Save ems cluster for a vm [(#254)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/254)
- Parse parent for most collections [(#251)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/251)
- Add support for reconfigure cdrom [(#244)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/244)

### Fixed
- Fixes ProvisionWorkflow#available_vlans_and_hosts [(#269)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/269)

## Unreleased as of Sprint 85 ending 2018-05-07

### Added
- Parse Switches for Streaming Refresh [(#236)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/236)

### Fixed
- Don't save_inventory when WaitForUpdates times out [(#248)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/248)

## Unreleased as of Sprint 84 ending 2018-04-26

### Added
- Add save inventory thread for streaming refresh [(#233)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/233)
- Update driven refresh [(#186)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/186)

### Fixed
- Add supports revert to snapshot [(#230)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/230)

## Unreleased as of Sprint 83 ending 2018-04-09

### Added
- Shift fog-vcloud-director version to 0.1.10 [(#224)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/224)
- Actually apply CloudManager's api_version [(#219)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/219)
- Add support for vCloud console access via WebMKS [(#218)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/218)
- Add guest customization field to service catalog order form [(#215)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/215)
- Add Distributed and Host VirtualSwitch models [(#212)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/212)

### Fixed
- Sort unitNumber as an integer not a string [(#223)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/223)
- VMware provider IP discovery fix [(#221)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/221)

## Unreleased as of Sprint 82 ending 2018-03-26

### Added
- Prevent vapp templates from being duplicated [(#209)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/209)
- Update disk's controller type parsing [(#207)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/207)
- Support update VM snapshot [(#205)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/205)

### Fixed
- Fix update driven vm refresh operating systems [(#214)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/214)
- Fix WebMKS/VNC console access [(#211)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/211)

## Unreleased as of Sprint 81 ending 2018-03-12

### Added
- Completely stop/suspend VM not just partially [(#206)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/206)
- Use utility function vm_powered_on? instead manual comparison [(#204)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/204)
- Don't run EventCatcher when "none" was selected on GUI [(#199)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/199)
- Allow user to pick administrator password upon vApp provisioning [(#196)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/196)
- Render hostname for vm [(#193)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/193)
- Support revert to snapshot for vm [(#192)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/192)
- Support delete snapshot for VM [(#191)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/191)
- Render snapshot for VM [(#190)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/190)
- Allow vApp customization prior provisioning [(#185)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/185)

### Fixed
- Skip "none" vApp network when inventoring [(#198)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/198)

## Gaprindashvili-2 released 2018-03-06

### Added
- Update gettext catalogs for Gaprindashvili update release [(#188)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/188)

## Unreleased as of Sprint 80 ending 2018-02-26

### Added
- Support create snapshot for VM [(#189)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/189)
- Added support for VM delete [(#184)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/184)

## Unreleased as of Sprint 79 ending 2018-02-12

### Fixed
- Add VM uuid as the vm_uid_ems to the event payload [(#179)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/179)

## Gaprindashvili-1 - Release 2018-01-31

### Added
- Proxy WebMKS connections through the WebSocket worker [(#140)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/140)
- Inventory host serial number [(#139)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/139)
- Allow type of controller to be passed in disk opts [(#117)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/117)
- Fix the issue where dvs prefix is removed from :vlan in provision's options hash. [(#100)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/100)
- If there is no vnicDev passed in don't call edit_vlan_device [(#96)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/96)
- Add a batch inventory persister [(#93)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/93)
- Only collect storage profile datastores on full refresh [(#83)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/83)
- Configurably use the RbVmomi Inventory Collector [(#76)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/76)
- Don't update ems attributes in refresh parser [(#62)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/62)
- Parser methods for RbVmomi Inventory Collector [(#74)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/74)
- Rbvmomi inventory collector [(#72)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/72)
- Add VMware inventory collections [(#71)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/71)
- Decrypt and validate credentials in raw_connect  [(#69)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/69)
- Lookup SCSI Controller Device Type from Hardware  [(#51)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/51)
- Login with console authentication if available [(#125)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/125)
- Route VMware vCD logs into its own file [(#153)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/153)

### Fixed
- Added supported_catalog_types [(#151)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/151)
- Properly update network hash when the first array element is nil [(#132)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/132)
- Fix storage location parsing for update collector [(#135)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/135)
- Move saving of ems.api_version back to parser [(#136)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/136)
- Fix RefreshWorker before_exit arguments [(#138)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/138)
- Fix the parent collections for hardwares/disks [(#116)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/116)
- Fix update driven refresh initialization [(#108)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/108)
- Return true if credentials have been verified [(#111)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/111)
- Add benchmark and logging around storage profiles [(#81)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/81)
- Dealing with disks which have no controller key [(#77)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/77)
- Don't queue a refresh on RefreshWorker start [(#75)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/75)
- Fix the VM Provisioning issue with auto replacement in selected dvPortGroup network. [(#78)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/78)
- Decode slashes in more VMware inventory type names [(#53)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/53)
- Update vmware_web_service for smartstate fix [(#165)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/165)
- SSA connect to use :hostname or :ipaddress instead of :address [(#143)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/143)
- Refresh datastore files through EMS [(#170)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/170)

## Unreleased as of Sprint 78 ending 2018-01-29

### Fixed
- Migrate model display names from locale/en.yml to plugin [(#174)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/174)
- Fix the event parser for a new folder refresh [(#166)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/166)
- Collect IP and MAC address properly [(#161)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/161)

## Unreleased as of Sprint 72 ending 2017-10-30

### Added
- Add a method to return all valid SCSI Controller Types [(#126)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/126)

## Fine-3

### Fixed
- Vm restart guest check fixed [(#64)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/64)

## Fine-1

### Added
- Allow folder as refresh target [(#32)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/32)
- Add a simple event history script [(#21)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/21)
- Add support for WebMKS remote consoles accessible from the UI [(#13)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/13)
- Add vm_acquire_ticket for webmks console types [(#9)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/9)
- Implements OrchestrationTemplate#deployment_options [(#8)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/8)

### Changed
- Removed supports_snapshots? methods defined independently without using supportsFeatureMixin plugin [(#14)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/14)

### Fixed
- Queue initial refresh if the Broker is available [(#41)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/41)
- Changes sysprep field to be a hash [(#35)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/35)
- Comment out GlobalVars to prevent it from breaking the rubocop config [(#38)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/38)
- Skip clusters with invalid configuration [(#36)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/36)
- Don't allow memory snapshot for powered off vms [(#30)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/30)
- Handle all DVPortGroups in the VMware Provision Workflow [(#25)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/25)
- Validate deviceMode on a VirtualDisk Backing before reconfigure [(#24)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/24)
- Allow changing the device type of an existing vnic [(#10)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/10)
- Fix issue provisioning to a VM Network from a DVS [(#11)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/11)
- Use the dvportgroup config.key for the uid_ems [(#5)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/5)
- Fix wrong number of arguments error when opening MKS console [(#15)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/15)
- Decode the dvSwitch and dvPortgroup name [(#4)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/4)
- Fix issue where EmsEvent.add_vc and add_vmware_vcloud methods no longer exists [(#7)](https://github.com/ManageIQ/manageiq-providers-vmware/pull/7)

## Initial changelog added
