package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/url"
	"strconv"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/vmware/govmomi"
	"github.com/vmware/govmomi/find"
	"github.com/vmware/govmomi/simulator"

	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/parser"
	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/vim"
)

type fakePublisher struct {
	mu         sync.Mutex
	events     []*parser.Event
	publishErr error
}

func (f *fakePublisher) Publish(_ context.Context, e *parser.Event) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.publishErr != nil {
		return f.publishErr
	}
	f.events = append(f.events, e)
	return nil
}

func (f *fakePublisher) Close() {}

func (f *fakePublisher) getEvents() []*parser.Event {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := make([]*parser.Event, len(f.events))
	copy(out, f.events)
	return out
}

func newVCSim(t *testing.T) *url.URL {
	t.Helper()
	model := simulator.VPX()
	if err := model.Create(); err != nil {
		t.Fatalf("model.Create: %v", err)
	}
	server := model.Service.NewServer()
	t.Cleanup(func() {
		server.Close()
		model.Remove()
	})
	return server.URL
}

func portFromURL(t *testing.T, u *url.URL) int {
	t.Helper()
	portStr := u.Port()
	if portStr == "" {
		return 443
	}
	p, err := strconv.Atoi(portStr)
	if err != nil {
		t.Fatalf("portFromURL: %v", err)
	}
	return p
}

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, &slog.HandlerOptions{Level: slog.LevelError}))
}

func containsPowerOnEvent(events []*parser.Event) bool {
	for _, e := range events {
		if e.EventType == "VmPoweredOnEvent" || e.EventType == "TaskEvent" {
			return true
		}
	}
	return false
}

func newVimCfg(t *testing.T, serverURL *url.URL, extra ...func(*vim.Config)) vim.Config {
	t.Helper()
	pw, _ := serverURL.User.Password()
	cfg := vim.Config{
		Host:        serverURL.Hostname(),
		Port:        portFromURL(t, serverURL),
		VerifySSL:   0,
		Scheme:      serverURL.Scheme,
		Username:    serverURL.User.Username(),
		Password:    pw,
		EmsID:       []byte("99"),
		MaxWaitSecs: 1,
	}
	for _, fn := range extra {
		fn(&cfg)
	}
	return cfg
}

// waitForPowerOnAndIdle waits for a power-on event then two idle beats to avoid a vcsim teardown race.
func waitForPowerOnAndIdle(t *testing.T, pub *fakePublisher, beats <-chan struct{}) []*parser.Event {
	t.Helper()
	idleBeats := 0
	timeout := time.After(10 * time.Second)
	for idleBeats < 2 {
		select {
		case <-beats:
		case <-timeout:
			t.Fatal("timed out waiting for the power-on event and two idle heartbeats")
		}
		if containsPowerOnEvent(pub.getEvents()) {
			idleBeats++
		}
	}
	return pub.getEvents()
}

func powerOnVM(t *testing.T, ctx context.Context, serverURL *url.URL, name string) {
	t.Helper()
	client, err := govmomi.NewClient(ctx, serverURL, true)
	if err != nil {
		t.Fatalf("govmomi.NewClient: %v", err)
	}
	finder := find.NewFinder(client.Client, false)
	dc, err := finder.DefaultDatacenter(ctx)
	if err != nil {
		t.Fatalf("DefaultDatacenter: %v", err)
	}
	finder.SetDatacenter(dc)
	vm, err := finder.VirtualMachine(ctx, name)
	if err != nil {
		t.Fatalf("VirtualMachine(%q): %v", name, err)
	}
	task, err := vm.PowerOn(ctx)
	if err != nil {
		t.Fatalf("vm.PowerOn: %v", err)
	}
	_ = task.Wait(ctx)
}

func powerOffVM(t *testing.T, ctx context.Context, serverURL *url.URL, name string) {
	t.Helper()
	client, err := govmomi.NewClient(ctx, serverURL, true)
	if err != nil {
		t.Fatalf("govmomi.NewClient: %v", err)
	}
	finder := find.NewFinder(client.Client, false)
	dc, err := finder.DefaultDatacenter(ctx)
	if err != nil {
		t.Fatalf("DefaultDatacenter: %v", err)
	}
	finder.SetDatacenter(dc)
	vm, err := finder.VirtualMachine(ctx, name)
	if err != nil {
		t.Fatalf("VirtualMachine(%q): %v", name, err)
	}
	task, err := vm.PowerOff(ctx)
	if err != nil {
		t.Fatalf("vm.PowerOff: %v", err)
	}
	_ = task.Wait(ctx)
}

func startMainLoop(ctx context.Context, log *slog.Logger, sess *vim.Session, pub *fakePublisher) <-chan int {
	ch := make(chan int, 1)
	go func() { ch <- mainLoop(ctx, log, sess, pub) }()
	return ch
}

// wireHeartbeat installs an OnBeat hook; must be called before startMainLoop.
func wireHeartbeat(sess *vim.Session) (beats <-chan struct{}, beatCount *atomic.Int64) {
	var count atomic.Int64
	ch := make(chan struct{}, 1)
	sess.OnBeat = func() error {
		count.Add(1)
		select {
		case ch <- struct{}{}:
		default:
		}
		return nil
	}
	return ch, &count
}

// waitStarted blocks until the first heartbeat fires or the context expires.
func waitStarted(t *testing.T, ctx context.Context, beats <-chan struct{}) {
	t.Helper()
	select {
	case <-beats:
	case <-ctx.Done():
		t.Fatal("timed out waiting for the session to start")
	}
}

func TestEndToEnd_EventPipeline(t *testing.T) {
	serverURL := newVCSim(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	log := testLogger()
	pub := &fakePublisher{}

	cfg := newVimCfg(t, serverURL, func(c *vim.Config) {
		c.EmsID = []byte("99")
		c.BlacklistedEventNames = []string{"VmPoweredOffEvent", "UserLoginSessionEvent"}
	})
	sess := vim.New(cfg, log)

	beats, beatCount := wireHeartbeat(sess)
	doneCh := startMainLoop(ctx, log, sess, pub)
	waitStarted(t, ctx, beats)

	powerOnVM(t, ctx, serverURL, "DC0_H0_VM0")
	powerOffVM(t, ctx, serverURL, "DC0_H0_VM0")

	events := waitForPowerOnAndIdle(t, pub, beats)

	// Stop the loop cleanly before asserting so cancel never races with vcsim.
	cancel()
	select {
	case exitCode := <-doneCh:
		t.Run("mainLoop exits with code 0 on context cancel", func(t *testing.T) {
			if exitCode != 0 {
				t.Errorf("exitCode = %d, want 0", exitCode)
			}
		})
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for mainLoop to stop")
	}

	t.Run("at least one event was published", func(t *testing.T) {
		if len(events) == 0 {
			t.Fatal("expected published events, got none")
		}
	})

	t.Run("VmPoweredOnEvent for DC0_H0_VM0 is present with vm_ems_ref and timestamp", func(t *testing.T) {
		var found bool
		for _, e := range events {
			if e.EventType == "VmPoweredOnEvent" && e.VMName == "DC0_H0_VM0" {
				found = true
				if e.VMEmsRef == "" {
					t.Error("VmPoweredOnEvent has empty vm_ems_ref")
				}
				if e.Timestamp == "" {
					t.Error("VmPoweredOnEvent has empty timestamp")
				}
			}
		}
		if !found {
			t.Error("VmPoweredOnEvent for DC0_H0_VM0 was not published")
		}
	})

	t.Run("EmsID is forwarded on every event", func(t *testing.T) {
		for _, e := range events {
			if string(e.EmsID) != "99" {
				t.Errorf("event %q: EmsID = %q, want 99", e.EventType, string(e.EmsID))
			}
		}
	})

	t.Run("blacklisted events are not published", func(t *testing.T) {
		for _, e := range events {
			if e.EventType == "VmPoweredOffEvent" {
				t.Errorf("blacklisted event VmPoweredOffEvent was published")
			}
			if e.EventType == "UserLoginSessionEvent" {
				t.Errorf("blacklisted event UserLoginSessionEvent was published")
			}
		}
	})

	t.Run("every event serialises to valid JSON with required fields", func(t *testing.T) {
		for _, e := range events {
			raw, err := json.Marshal(e)
			if err != nil {
				t.Fatalf("json.Marshal(%q): %v", e.EventType, err)
			}
			var wire map[string]interface{}
			if err := json.Unmarshal(raw, &wire); err != nil {
				t.Fatalf("json.Unmarshal: %v", err)
			}
			for _, field := range []string{"event_type", "ems_id", "full_data"} {
				if _, ok := wire[field]; !ok {
					t.Errorf("event %q JSON missing field %q", e.EventType, field)
				}
			}
		}
	})

	t.Run("heartbeat fires at least twice", func(t *testing.T) {
		if n := beatCount.Load(); n < 2 {
			t.Errorf("beatCount = %d, want >= 2", n)
		}
	})
}

func TestMainLoop_PublisherError(t *testing.T) {
	serverURL := newVCSim(t)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pub := &fakePublisher{publishErr: errors.New("kafka broker unavailable")}

	// Power on a VM before starting the loop so an event is ready immediately.
	powerOnVM(t, ctx, serverURL, "DC0_H0_VM0")

	cfg := newVimCfg(t, serverURL, func(c *vim.Config) { c.EmsID = []byte("1") })
	sess := vim.New(cfg, testLogger())

	exitCode := mainLoop(ctx, testLogger(), sess, pub)
	if exitCode != 1 {
		t.Errorf("exitCode = %d, want 1 on publisher error", exitCode)
	}
}
