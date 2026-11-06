package parser_test

import (
	"testing"
	"time"

	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/parser"
	"github.com/vmware/govmomi/vim25/types"
)

func vmArg(name, ref string) *types.VmEventArgument {
	return &types.VmEventArgument{
		EntityEventArgument: types.EntityEventArgument{Name: name},
		Vm:                  types.ManagedObjectReference{Type: "VirtualMachine", Value: ref},
	}
}

func hostArg(name, ref string) *types.HostEventArgument {
	return &types.HostEventArgument{
		EntityEventArgument: types.EntityEventArgument{Name: name},
		Host:                types.ManagedObjectReference{Type: "HostSystem", Value: ref},
	}
}

// TestParseEventType verifies that the correct EventType and IsTask values are
// produced for the three distinct event categories.
func TestParseEventType(t *testing.T) {
	t.Run("standard event uses struct type name", func(t *testing.T) {
		p := parser.Parse(&types.VmPoweredOnEvent{})
		if p.EventType != "VmPoweredOnEvent" {
			t.Errorf("EventType = %q, want VmPoweredOnEvent", p.EventType)
		}
		if p.IsTask {
			t.Error("IsTask = true, want false")
		}
	})

	t.Run("EventEx uses EventTypeId", func(t *testing.T) {
		p := parser.Parse(&types.EventEx{EventTypeId: "com.vmware.vc.HA.VmUnprotectedEvent"})
		if p.EventType != "com.vmware.vc.HA.VmUnprotectedEvent" {
			t.Errorf("EventType = %q, want com.vmware.vc.HA.VmUnprotectedEvent", p.EventType)
		}
	})

	t.Run("EventEx with blank EventTypeId falls back to type name", func(t *testing.T) {
		p := parser.Parse(&types.EventEx{EventTypeId: "   "})
		if p.EventType != "EventEx" {
			t.Errorf("EventType = %q, want EventEx", p.EventType)
		}
	})
}

// TestResolveTaskEventType covers every branch of resolveTaskEventType via TaskEvent inputs.
func TestResolveTaskEventType(t *testing.T) {
	cases := []struct {
		name          string
		taskName      string
		descriptionID string
		message       string
		wantType      string
	}{
		{
			name:     "named task returns name directly",
			taskName: "MigrateVM_Task",
			wantType: "MigrateVM_Task",
		},
		{
			name:          "Rename_Task on VirtualMachine",
			taskName:      "Rename_Task",
			descriptionID: "VirtualMachine.rename",
			wantType:      "RenameVM_Task",
		},
		{
			name:          "Rename_Task on ClusterComputeResource",
			taskName:      "Rename_Task",
			descriptionID: "ClusterComputeResource.rename",
			wantType:      "RenameCluster_Task",
		},
		{
			name:          "Destroy_Task on VirtualMachine",
			taskName:      "Destroy_Task",
			descriptionID: "VirtualMachine.destroy",
			wantType:      "DestroyVM_Task",
		},
		{
			name:          "Destroy_Task on ClusterComputeResource",
			taskName:      "Destroy_Task",
			descriptionID: "ClusterComputeResource.destroy",
			wantType:      "DestroyCluster_Task",
		},
		{
			name:          "Rename_Task on unknown entity passes entity through",
			taskName:      "Rename_Task",
			descriptionID: "Datacenter.rename",
			wantType:      "RenameDatacenter_Task",
		},
		{
			name:     "no name, PowerOn message",
			message:  "Task: Power On Virtual Machine",
			wantType: "PowerOnVM_Task",
		},
		{
			name:          "no name, DRS vMotion descriptionId",
			descriptionID: "Drm.ExecuteVMotionLRO",
			wantType:      "DrsMigrateVM_Task",
		},
		{
			name:     "no name, no recognized signal falls back to TaskEvent",
			wantType: "TaskEvent",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			evt := &types.TaskEvent{
				Event: types.Event{FullFormattedMessage: tc.message},
				Info:  types.TaskInfo{Name: tc.taskName, DescriptionId: tc.descriptionID},
			}
			p := parser.Parse(evt)
			if p.EventType != tc.wantType {
				t.Errorf("EventType = %q, want %q", p.EventType, tc.wantType)
			}
			if !p.IsTask {
				t.Error("IsTask = false, want true")
			}
		})
	}
}

// TestParseTimestamp verifies UTC formatting and the zero-time edge case.
func TestParseTimestamp(t *testing.T) {
	t.Run("non-zero time is formatted as UTC", func(t *testing.T) {
		evt := &types.VmPoweredOnEvent{}
		evt.CreatedTime = time.Date(2024, 1, 2, 3, 4, 5, 0, time.UTC)
		p := parser.Parse(evt)
		if p.Timestamp != "2024-01-02 03:04:05 UTC" {
			t.Errorf("Timestamp = %q, want '2024-01-02 03:04:05 UTC'", p.Timestamp)
		}
	})

	t.Run("zero time produces empty timestamp", func(t *testing.T) {
		p := parser.Parse(&types.VmPoweredOnEvent{})
		if p.Timestamp != "" {
			t.Errorf("Timestamp = %q, want empty string", p.Timestamp)
		}
	})
}

// TestParseUsername verifies the username omit-if-blank behaviour.
func TestParseUsername(t *testing.T) {
	t.Run("non-blank username is set", func(t *testing.T) {
		evt := &types.VmPoweredOnEvent{}
		evt.UserName = "root"
		p := parser.Parse(evt)
		if p.Username != "root" {
			t.Errorf("Username = %q, want root", p.Username)
		}
	})

	t.Run("blank username is omitted", func(t *testing.T) {
		evt := &types.VmPoweredOnEvent{}
		evt.UserName = "   "
		p := parser.Parse(evt)
		if p.Username != "" {
			t.Errorf("Username = %q, want empty", p.Username)
		}
	})
}

// TestParseVM covers VM ref/name extraction including CGI decoding, the
// SrcTemplate override for VmDeployedEvent, and dest fields for clone/migrate.
func TestParseVM(t *testing.T) {
	t.Run("standard event extracts VM ref and CGI-decodes name", func(t *testing.T) {
		evt := &types.VmPoweredOnEvent{}
		evt.Vm = vmArg("my+vm%20name", "vm-1")
		p := parser.Parse(evt)
		if p.VMEmsRef != "vm-1" {
			t.Errorf("VMEmsRef = %q, want vm-1", p.VMEmsRef)
		}
		if p.VMName != "my vm name" {
			t.Errorf("VMName = %q, want 'my vm name'", p.VMName)
		}
	})

	t.Run("VmDeployedEvent overrides VM ref with SrcTemplate", func(t *testing.T) {
		evt := &types.VmDeployedEvent{}
		evt.Vm = vmArg("deployed-vm", "vm-99")
		evt.SrcTemplate = types.VmEventArgument{
			EntityEventArgument: types.EntityEventArgument{Name: "template%2Fname"},
			Vm:                  types.ManagedObjectReference{Value: "vm-template-1"},
		}
		p := parser.Parse(evt)
		if p.VMEmsRef != "vm-template-1" {
			t.Errorf("VMEmsRef = %q, want vm-template-1", p.VMEmsRef)
		}
		if p.VMName != "template/name" {
			t.Errorf("VMName = %q, want 'template/name'", p.VMName)
		}
	})

	t.Run("VmBeingClonedEvent sets DestVMName and DestHost", func(t *testing.T) {
		evt := &types.VmBeingClonedEvent{}
		evt.Vm = vmArg("src-vm", "vm-2")
		evt.DestName = "cloned-vm"
		evt.DestHost = types.HostEventArgument{
			EntityEventArgument: types.EntityEventArgument{Name: "esx-dest"},
			Host:                types.ManagedObjectReference{Value: "host-dest-1"},
		}
		p := parser.Parse(evt)
		if p.DestVMName != "cloned-vm" {
			t.Errorf("DestVMName = %q, want cloned-vm", p.DestVMName)
		}
		if p.DestHostEmsRef != "host-dest-1" {
			t.Errorf("DestHostEmsRef = %q, want host-dest-1", p.DestHostEmsRef)
		}
		if p.DestHostName != "esx-dest" {
			t.Errorf("DestHostName = %q, want esx-dest", p.DestHostName)
		}
	})

	t.Run("VmBeingHotMigratedEvent sets DestHost", func(t *testing.T) {
		evt := &types.VmBeingHotMigratedEvent{}
		evt.Vm = vmArg("live-vm", "vm-3")
		evt.DestHost = types.HostEventArgument{
			EntityEventArgument: types.EntityEventArgument{Name: "esx-migrated"},
			Host:                types.ManagedObjectReference{Value: "host-migrated-1"},
		}
		p := parser.Parse(evt)
		if p.DestHostEmsRef != "host-migrated-1" {
			t.Errorf("DestHostEmsRef = %q, want host-migrated-1", p.DestHostEmsRef)
		}
		if p.DestHostName != "esx-migrated" {
			t.Errorf("DestHostName = %q, want esx-migrated", p.DestHostName)
		}
	})
}

// TestParseHost verifies that host name and ref are extracted from the base event.
func TestParseHost(t *testing.T) {
	evt := &types.VmPoweredOnEvent{}
	evt.Host = hostArg("esx1", "host-456")
	p := parser.Parse(evt)
	if p.HostName != "esx1" {
		t.Errorf("HostName = %q, want esx1", p.HostName)
	}
	if p.HostEmsRef != "host-456" {
		t.Errorf("HostEmsRef = %q, want host-456", p.HostEmsRef)
	}
}
