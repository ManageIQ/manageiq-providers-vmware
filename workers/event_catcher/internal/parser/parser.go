package parser

import (
	"encoding/json"
	"reflect"
	"strings"
	"unicode/utf8"

	"github.com/vmware/govmomi/vim25/types"
)

// Event is the parsed event published to the manageiq.ems topic.
type Event struct {
	EventType string          `json:"event_type"`
	ChainID   int32           `json:"chain_id"`
	IsTask    bool            `json:"is_task"`
	Source    string          `json:"source"`
	Message   string          `json:"message"`
	Timestamp string          `json:"timestamp"`
	FullData  types.BaseEvent `json:"full_data"`

	Username       string          `json:"username,omitempty"`
	VMEmsRef       string          `json:"vm_ems_ref,omitempty"`
	VMName         string          `json:"vm_name,omitempty"`
	DestVMName     string          `json:"dest_vm_name,omitempty"`
	HostName       string          `json:"host_name,omitempty"`
	HostEmsRef     string          `json:"host_ems_ref,omitempty"`
	DestHostEmsRef string          `json:"dest_host_ems_ref,omitempty"`
	DestHostName   string          `json:"dest_host_name,omitempty"`
	EmsID          json.RawMessage `json:"ems_id,omitempty"`
}

// Parse converts a govmomi BaseEvent into the published ManageIQ representation.
func Parse(base types.BaseEvent) *Event {
	e := base.GetEvent()
	eventType, isTask := resolveEventType(base)

	timestamp := ""
	if !e.CreatedTime.IsZero() {
		timestamp = e.CreatedTime.UTC().Format("2006-01-02 15:04:05 UTC")
	}

	out := &Event{
		EventType: eventType,
		ChainID:   e.ChainId,
		IsTask:    isTask,
		Source:    "VC",
		Message:   e.FullFormattedMessage,
		Timestamp: timestamp,
		FullData:  base,
	}

	if strings.TrimSpace(e.UserName) != "" {
		out.Username = e.UserName
	}

	out.parseVM(base, e)
	out.parseHost(base, e)

	return out
}

func resolveEventType(base types.BaseEvent) (string, bool) {
	e := base.GetEvent()
	typeName := reflect.TypeOf(base).Elem().Name()

	if taskEvent, ok := base.(*types.TaskEvent); ok {
		return resolveTaskEventType(taskEvent), true
	}

	if eventEx, ok := base.(*types.EventEx); ok {
		if strings.TrimSpace(eventEx.EventTypeId) != "" {
			return eventEx.EventTypeId, false
		}
	}

	// Fallback if base is a generic Event
	if typeName == "Event" && strings.TrimSpace(e.FullFormattedMessage) != "" {
		return "Event", false
	}

	return typeName, false
}

func resolveTaskEventType(event *types.TaskEvent) string {
	name := ""
	descID := ""
	if event.Info.Name != "" {
		name = event.Info.Name
	}
	if event.Info.DescriptionId != "" {
		descID = event.Info.DescriptionId
	}

	switch {
	case name == "":
		if strings.EqualFold(event.FullFormattedMessage, "task: power on virtual machine") {
			return "PowerOnVM_Task"
		}
		if descID == "Drm.ExecuteVMotionLRO" {
			return "DrsMigrateVM_Task"
		}
		return "TaskEvent"
	case name == "Rename_Task" || name == "Destroy_Task":
		entity, _, _ := strings.Cut(descID, ".")
		switch entity {
		case "VirtualMachine":
			entity = "VM"
		case "ClusterComputeResource":
			entity = "Cluster"
		}
		return strings.ReplaceAll(name, "_", entity+"_")
	default:
		return name
	}
}

func (e *Event) parseVM(base types.BaseEvent, evt *types.Event) {
	// Source VM
	if evt.Vm != nil {
		e.VMEmsRef = evt.Vm.Vm.Value
		if evt.Vm.Name != "" {
			e.VMName = cgiUnescape(evt.Vm.Name)
		}
	}

	// Deploy / clone events with SrcTemplate or SourceVm
	if deployed, ok := base.(*types.VmDeployedEvent); ok {
		if deployed.SrcTemplate.Vm.Value != "" {
			e.VMEmsRef = deployed.SrcTemplate.Vm.Value
			e.VMName = cgiUnescape(deployed.SrcTemplate.Name)
		}
	}

	// Destination VM / Host
	if beingCloned, ok := base.(*types.VmBeingClonedEvent); ok {
		if beingCloned.DestName != "" {
			e.DestVMName = beingCloned.DestName
		}
		if beingCloned.DestHost.Host.Value != "" {
			e.DestHostEmsRef = beingCloned.DestHost.Host.Value
			e.DestHostName = beingCloned.DestHost.Name
		}
	} else if beingMigrated, ok := base.(*types.VmBeingHotMigratedEvent); ok {
		if beingMigrated.DestHost.Host.Value != "" {
			e.DestHostEmsRef = beingMigrated.DestHost.Host.Value
			e.DestHostName = beingMigrated.DestHost.Name
		}
	}
}

func (e *Event) parseHost(base types.BaseEvent, evt *types.Event) {
	if evt.Host != nil {
		e.HostName = evt.Host.Name
		e.HostEmsRef = evt.Host.Host.Value
	}
}

// cgiUnescape decodes vCenter CGI-encoded object names ('+' → space, %XX → byte).
func cgiUnescape(s string) string {
	s = strings.ReplaceAll(s, "+", " ")
	if !strings.Contains(s, "%") {
		return s
	}

	out := make([]byte, 0, len(s))
	for i := 0; i < len(s); i++ {
		if s[i] == '%' && i+2 < len(s) {
			hi, okHi := fromHex(s[i+1])
			lo, okLo := fromHex(s[i+2])
			if okHi && okLo {
				out = append(out, hi<<4|lo)
				i += 2
				continue
			}
		}
		out = append(out, s[i])
	}

	if !utf8.Valid(out) {
		return s
	}
	return string(out)
}

func fromHex(c byte) (byte, bool) {
	switch {
	case c >= '0' && c <= '9':
		return c - '0', true
	case c >= 'a' && c <= 'f':
		return c - 'a' + 10, true
	case c >= 'A' && c <= 'F':
		return c - 'A' + 10, true
	}
	return 0, false
}
