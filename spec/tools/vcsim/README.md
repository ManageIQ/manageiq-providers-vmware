# Setup a VC Simulator for Recording EmsRefresh Specs

ManageIQ::Providers::Vmware uses VCR cassettes for EmsRefresh specs recorded from a VC Simulator.

You can create your own simulator for spec tests by deploying a VMware vSphere Virtual Center 5.5 and configuring it as a simulator.

The config files for the simulator are vcsim.cfg and initInventory.cfg in this directory.

Steps to turn a vCenter into a simulator:
1. scp vcsim.cfg initInventory.cfg user@vcenter:/etc/vmware-vpx/vcsim/model
2. ssh user@vcenter
3. vmware-vcsim-stop && vmware-vcsim-start /etc/vmware-vpx/vcsim/model/vcsim.cfg

This will restart the vpx daemon and start populating the vc database with simulated inventory.

Once this process is complete it will be able to be used for spec tests.

Then you just need to set vmware_infra.hostname in VcrSecrets to the ip address or hostname of your simulator, `rm -r spec/vcr_cassettes/manageiq/providers/vmware/infra_manager/inventory` and re-run the specs.
