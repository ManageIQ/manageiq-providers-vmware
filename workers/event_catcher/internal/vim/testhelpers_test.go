package vim

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/pem"
	"log/slog"
	"net"
	"net/url"
	"slices"
	"strconv"
	"sync"
	"testing"

	"github.com/vmware/govmomi/property"
	"github.com/vmware/govmomi/simulator"
	"github.com/vmware/govmomi/vim25"
	"github.com/vmware/govmomi/vim25/methods"
	"github.com/vmware/govmomi/vim25/mo"
	"github.com/vmware/govmomi/vim25/soap"
	"github.com/vmware/govmomi/vim25/types"

	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/parser"
)

const (
	methodLogin          = "Login"
	methodLogout         = "Logout"
	methodCreateCollect  = "CreateCollectorForEvents"
	methodSetPageSize    = "SetCollectorPageSize"
	methodCreateFilter   = "CreateFilter"
	methodWait           = "WaitForUpdatesEx"
	methodDestroyFilter  = "DestroyPropertyFilter"
	methodDestroyCollect = "DestroyCollector"
)

// logSink is a goroutine-safe io.Writer that lets tests assert on log output.
type logSink struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (l *logSink) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.Write(p)
}

func (l *logSink) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.String()
}

func newTestLogger() (*slog.Logger, *logSink) {
	sink := &logSink{}
	return slog.New(slog.NewTextHandler(sink, &slog.HandlerOptions{Level: slog.LevelDebug})), sink
}

// rtStep is one scripted WaitForUpdatesEx response; a zero value models a timeout.
type rtStep struct {
	set       *types.UpdateSet
	err       error
	cancelCtx bool
}

// scriptedRT replays scripted steps; cancels the context when exhausted to terminate the loop.
type scriptedRT struct {
	t      *testing.T
	steps  []rtStep
	reqs   []types.WaitForUpdatesEx
	cancel context.CancelFunc
}

func (s *scriptedRT) RoundTrip(_ context.Context, req, res soap.HasFault) error {
	body, ok := req.(*methods.WaitForUpdatesExBody)
	if !ok {
		s.t.Fatalf("scriptedRT: unexpected request %T", req)
	}
	s.reqs = append(s.reqs, *body.Req)

	if len(s.steps) == 0 {
		s.cancel()
		return context.Canceled
	}
	step := s.steps[0]
	s.steps = s.steps[1:]

	if step.cancelCtx {
		s.cancel()
	}
	if step.err != nil {
		return step.err
	}
	res.(*methods.WaitForUpdatesExBody).Res = &types.WaitForUpdatesExResponse{Returnval: step.set}
	return nil
}

// harness drives Session.loop without a network via a scriptedRT.
type harness struct {
	sess   *Session
	rt     *scriptedRT
	client *vim25.Client
	pc     *property.Collector
	logs   *logSink
	ctx    context.Context
	events []*parser.Event

	beats   int
	beatErr error
}

func newHarness(t *testing.T, cfg Config, steps ...rtStep) *harness {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	logger, logs := newTestLogger()
	rt := &scriptedRT{t: t, steps: steps, cancel: cancel}
	client := &vim25.Client{RoundTripper: rt}

	h := &harness{
		sess:   New(cfg, logger),
		rt:     rt,
		client: client,
		pc:     property.DefaultCollector(client),
		logs:   logs,
		ctx:    ctx,
	}
	h.sess.OnBeat = func() error {
		h.beats++
		return h.beatErr
	}
	return h
}

func (h *harness) collect(_ context.Context, e *parser.Event) error {
	h.events = append(h.events, e)
	return nil
}

func (h *harness) run() error { return h.runWith(h.collect) }

func (h *harness) runWith(onEvent EventHandler) error {
	return h.sess.loop(h.ctx, h.client, h.pc, onEvent)
}

func (h *harness) eventTypes() []string {
	names := make([]string, 0, len(h.events))
	for _, e := range h.events {
		names = append(names, e.EventType)
	}
	return names
}

func scriptedConfig(blacklist ...string) Config {
	return Config{
		Host:                  "vcenter.invalid",
		Port:                  443,
		EmsID:                 []byte("42"),
		BlacklistedEventNames: blacklist,
		MaxWaitSecs:           7,
	}
}

const latestPage = "latestPage"

const (
	typePoweredOn  = "VmPoweredOnEvent"
	typePoweredOff = "VmPoweredOffEvent"
	typeLogin      = "UserLoginSessionEvent"
)

func poweredOn() types.BaseEvent  { return &types.VmPoweredOnEvent{} }
func poweredOff() types.BaseEvent { return &types.VmPoweredOffEvent{} }
func login() types.BaseEvent      { return &types.UserLoginSessionEvent{} }

func page(evts ...types.BaseEvent) types.ArrayOfEvent { return types.ArrayOfEvent{Event: evts} }

func truncated(us *types.UpdateSet) *types.UpdateSet {
	us.Truncated = types.NewBool(true)
	return us
}

func change(name string, val any) types.PropertyChange {
	return types.PropertyChange{Name: name, Val: val}
}

func objUpdate(kind types.ObjectUpdateKind, changes ...types.PropertyChange) types.ObjectUpdate {
	return types.ObjectUpdate{Kind: kind, ChangeSet: changes}
}

func updateSet(version string, objs ...types.ObjectUpdate) *types.UpdateSet {
	return &types.UpdateSet{
		Version:   version,
		FilterSet: []types.PropertyFilterUpdate{{ObjectSet: objs}},
	}
}

// callLog intercepts vcsim SOAP dispatch: records call order, counts, and can inject faults.
type callLog struct {
	mu     sync.Mutex
	order  []string
	counts map[string]int
	faults map[string]bool
	hook   func(method string, n int)
}

func (c *callLog) handle(_ *simulator.Context, m *simulator.Method) (mo.Reference, types.BaseMethodFault) {
	c.mu.Lock()
	c.order = append(c.order, m.Name)
	c.counts[m.Name]++
	n, fault, hook := c.counts[m.Name], c.faults[m.Name], c.hook
	c.mu.Unlock()

	if hook != nil {
		hook(m.Name, n)
	}
	if fault {
		return nil, &types.InvalidRequest{}
	}
	return nil, nil
}

func (c *callLog) count(method string) int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.counts[method]
}

// sequenceOf returns the dispatched methods, in order, restricted to the given names.
func (c *callLog) sequenceOf(names ...string) []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	var out []string
	for _, m := range c.order {
		if slices.Contains(names, m) {
			out = append(out, m)
		}
	}
	return out
}

func (c *callLog) setHook(fn func(method string, n int)) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.hook = fn
}

type simOptions struct {
	TLS    bool
	Faults []string // SOAP method names that always fail with InvalidRequest
}

type simEnv struct {
	server *simulator.Server
	calls  *callLog
}

// simBuild serializes vcsim construction; govmomi has package-level state that races on concurrent NewServer calls.
var simBuild sync.Mutex

func newSim(t *testing.T, opts simOptions) *simEnv {
	t.Helper()
	simBuild.Lock()
	defer simBuild.Unlock()

	model := simulator.VPX()
	if err := model.Create(); err != nil {
		t.Fatalf("model.Create: %v", err)
	}
	if opts.TLS {
		model.Service.TLS = &tls.Config{}
	}

	calls := &callLog{counts: map[string]int{}, faults: map[string]bool{}}
	for _, f := range opts.Faults {
		calls.faults[f] = true
	}
	model.Service.Context.Map.Handler = calls.handle

	server := model.Service.NewServer()
	t.Cleanup(func() {
		server.Close()
		model.Remove()
	})
	return &simEnv{server: server, calls: calls}
}

func (e *simEnv) config(t *testing.T) Config {
	t.Helper()
	u := e.server.URL
	password, _ := u.User.Password()
	return Config{
		Host:        u.Hostname(),
		Port:        mustPort(t, u),
		VerifySSL:   0,
		Scheme:      u.Scheme,
		Username:    u.User.Username(),
		Password:    password,
		EmsID:       []byte("42"),
		MaxWaitSecs: 1,
	}
}

func (e *simEnv) caPEM() string {
	return string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: e.server.Certificate().Raw}))
}

type runResult struct {
	events []*parser.Event
	logs   *logSink
	err    error
}

func (e *simEnv) run(ctx context.Context, cfg Config) runResult {
	logger, logs := newTestLogger()
	res := runResult{logs: logs}

	sess := New(cfg, logger)
	res.err = sess.Run(ctx, func(_ context.Context, ev *parser.Event) error {
		res.events = append(res.events, ev)
		return nil
	})
	return res
}

// runUntilIdle stops the session after its second WaitForUpdatesEx, ensuring the initial snapshot is delivered.
func (e *simEnv) runUntilIdle(t *testing.T, cfg Config) runResult {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	stopAt := e.calls.count(methodWait) + 2
	e.calls.setHook(func(method string, n int) {
		if method == methodWait && n == stopAt {
			cancel()
		}
	})
	return e.run(ctx, cfg)
}

func mustPort(t *testing.T, u *url.URL) int {
	t.Helper()
	p, err := strconv.Atoi(u.Port())
	if err != nil {
		t.Fatalf("port of %q: %v", u, err)
	}
	return p
}

func closedAddr(t *testing.T) (string, int) {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("net.Listen: %v", err)
	}
	addr := l.Addr().(*net.TCPAddr)
	if err := l.Close(); err != nil {
		t.Fatalf("close listener: %v", err)
	}
	return addr.IP.String(), addr.Port
}
