package vim

import (
	"context"
	"errors"
	"reflect"
	"slices"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/vmware/govmomi/vim25/types"

	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/parser"
)

var errBoom = errors.New("boom")

func TestNew(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name          string
		cfg           Config
		wantScheme    string
		wantInsecure  bool
		wantMaxWait   int32
		wantBlacklist []string
	}{
		{name: "defaults", cfg: Config{}, wantScheme: "https", wantInsecure: true, wantMaxWait: 60},
		{name: "verify_ssl 1 verifies", cfg: Config{VerifySSL: 1}, wantScheme: "https", wantMaxWait: 60},
		{name: "scheme override", cfg: Config{Scheme: "http"}, wantScheme: "http", wantInsecure: true, wantMaxWait: 60},
		{name: "max wait override", cfg: Config{MaxWaitSecs: 5}, wantScheme: "https", wantInsecure: true, wantMaxWait: 5},
		{name: "negative max wait falls back to default", cfg: Config{MaxWaitSecs: -1}, wantScheme: "https", wantInsecure: true, wantMaxWait: 60},
		{
			name:          "blacklist is de-duplicated",
			cfg:           Config{BlacklistedEventNames: []string{"B", "A", "B"}},
			wantScheme:    "https",
			wantInsecure:  true,
			wantMaxWait:   60,
			wantBlacklist: []string{"A", "B"},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			s := New(tc.cfg, nil)

			if s.scheme != tc.wantScheme {
				t.Errorf("scheme = %q, want %q", s.scheme, tc.wantScheme)
			}
			if s.insecure != tc.wantInsecure {
				t.Errorf("insecure = %v, want %v", s.insecure, tc.wantInsecure)
			}
			if s.maxWaitSecs != tc.wantMaxWait {
				t.Errorf("maxWaitSecs = %d, want %d", s.maxWaitSecs, tc.wantMaxWait)
			}
			got := make([]string, 0, len(s.blacklist))
			for name := range s.blacklist {
				got = append(got, name)
			}
			sort.Strings(got)
			if !slices.Equal(got, tc.wantBlacklist) {
				t.Errorf("blacklist = %v, want %v", got, tc.wantBlacklist)
			}
		})
	}

	t.Run("connection fields are copied verbatim", func(t *testing.T) {
		t.Parallel()
		cfg := Config{
			Host: "vc.example.com", Port: 8443, CertificateAuthority: "PEM",
			Username: "admin", Password: "secret", EmsID: []byte("42"),
		}
		s := New(cfg, nil)

		got := []any{s.host, s.port, s.caPEM, s.username, s.password, string(s.emsID)}
		want := []any{"vc.example.com", 8443, "PEM", "admin", "secret", "42"}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("fields = %v, want %v", got, want)
		}
	})
}

// steps turns UpdateSets into scripted responses. A nil UpdateSet models a MaxWaitSeconds
// timeout.
func steps(sets ...*types.UpdateSet) []rtStep {
	out := make([]rtStep, len(sets))
	for i, s := range sets {
		out[i] = rtStep{set: s}
	}
	return out
}

func TestLoop_Dispatch(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name      string
		blacklist []string
		steps     []rtStep
		want      []string
	}{
		// Happy path.
		{
			name:  "enter delivers the initial snapshot in order",
			steps: steps(updateSet("1", objUpdate(types.ObjectUpdateKindEnter, change(latestPage, page(poweredOn(), poweredOff()))))),
			want:  []string{typePoweredOn, typePoweredOff},
		},
		{
			name:  "modify delivers subsequent changes",
			steps: steps(updateSet("1", objUpdate(types.ObjectUpdateKindModify, change(latestPage, page(poweredOn()))))),
			want:  []string{typePoweredOn},
		},
		{
			name:  "latestPage sub-paths match by prefix",
			steps: steps(updateSet("1", objUpdate(types.ObjectUpdateKindModify, change("latestPage[0]", page(poweredOn()))))),
			want:  []string{typePoweredOn},
		},
		{
			name: "order is preserved across filters, objects, changes and events",
			steps: steps(&types.UpdateSet{Version: "1", FilterSet: []types.PropertyFilterUpdate{
				{ObjectSet: []types.ObjectUpdate{
					objUpdate(types.ObjectUpdateKindEnter, change(latestPage, page(poweredOn()))),
					objUpdate(types.ObjectUpdateKindModify,
						change(latestPage, page(poweredOff())),
						change(latestPage, page(login()))),
				}},
				{ObjectSet: []types.ObjectUpdate{
					objUpdate(types.ObjectUpdateKindModify, change(latestPage, page(poweredOn()))),
				}},
			}}),
			want: []string{typePoweredOn, typePoweredOff, typeLogin, typePoweredOn},
		},
		{
			name:  "events arrive after an empty timeout",
			steps: steps(nil, updateSet("1", objUpdate(types.ObjectUpdateKindModify, change(latestPage, page(poweredOn()))))),
			want:  []string{typePoweredOn},
		},
		{
			name:  "truncated updates are delivered like any other",
			steps: steps(truncated(updateSet("1", objUpdate(types.ObjectUpdateKindModify, change(latestPage, page(poweredOn())))))),
			want:  []string{typePoweredOn},
		},

		// Skipped update kinds and properties.
		{
			name: "a skipped object does not stop later objects",
			steps: steps(updateSet("1",
				objUpdate(types.ObjectUpdateKindLeave, change(latestPage, page(poweredOff()))),
				objUpdate(types.ObjectUpdateKindModify, change(latestPage, page(poweredOn()))))),
			want: []string{typePoweredOn},
		},
		{
			name: "a skipped change does not stop later changes",
			steps: steps(updateSet("1", objUpdate(types.ObjectUpdateKindModify,
				change("filter", page(poweredOff())),
				change(latestPage, "not a page"),
				change(latestPage, nil),
				change(latestPage, page(poweredOn()))))),
			want: []string{typePoweredOn},
		},
		// Partial updates: after the initial page, vCenter sends one nested change per event.
		{
			name: "nested latestPage changes carry one event each",
			steps: steps(updateSet("1", objUpdate(types.ObjectUpdateKindModify,
				change("latestPage[101]", poweredOn()),
				change("latestPage[102]", poweredOff())))),
			want: []string{typePoweredOn, typePoweredOff},
		},
		{
			name: "initial page followed by a nested single event",
			steps: steps(
				updateSet("1", objUpdate(types.ObjectUpdateKindEnter, change(latestPage, page(poweredOn())))),
				updateSet("2", objUpdate(types.ObjectUpdateKindModify, change("latestPage[103]", poweredOff())))),
			want: []string{typePoweredOn, typePoweredOff},
		},
		{
			name:      "blacklist applies to nested single events",
			blacklist: []string{typeLogin},
			steps: steps(updateSet("1", objUpdate(types.ObjectUpdateKindModify,
				change("latestPage[104]", login()),
				change("latestPage[105]", poweredOn())))),
			want: []string{typePoweredOn},
		},
		{
			// vCenter sends nested events as plain structs, not pointers; BaseEvent is implemented
			// on the pointer, so these must be converted.
			name: "nested changes carrying non-pointer structs are delivered",
			steps: steps(updateSet("1", objUpdate(types.ObjectUpdateKindModify,
				change("latestPage[107]", types.VmPoweredOnEvent{}),
				change("latestPage[108]", types.VmPoweredOffEvent{})))),
			want: []string{typePoweredOn, typePoweredOff},
		},
		{
			name:      "blacklist applies to non-pointer nested events",
			blacklist: []string{typeLogin},
			steps: steps(updateSet("1", objUpdate(types.ObjectUpdateKindModify,
				change("latestPage[109]", types.UserLoginSessionEvent{}),
				change("latestPage[110]", types.VmPoweredOnEvent{})))),
			want: []string{typePoweredOn},
		},
		{
			name: "nested remove changes (nil value) are ignored",
			steps: steps(updateSet("1", objUpdate(types.ObjectUpdateKindModify,
				change("latestPage[100]", nil),
				change("latestPage[106]", poweredOn())))),
			want: []string{typePoweredOn},
		},
		// Empty shapes.
		{name: "nil FilterSet", steps: steps(&types.UpdateSet{Version: "1"})},
		{name: "empty ObjectSet", steps: steps(&types.UpdateSet{Version: "1", FilterSet: []types.PropertyFilterUpdate{{}}})},
		{name: "empty ChangeSet", steps: steps(updateSet("1", objUpdate(types.ObjectUpdateKindModify)))},
		{
			name:  "empty event page",
			steps: steps(updateSet("1", objUpdate(types.ObjectUpdateKindModify, change(latestPage, page())))),
		},

		// Blacklist.
		{
			name:      "blacklisted types are dropped, others kept",
			blacklist: []string{typeLogin},
			steps:     steps(updateSet("1", objUpdate(types.ObjectUpdateKindModify, change(latestPage, page(poweredOn(), login(), poweredOff()))))),
			want:      []string{typePoweredOn, typePoweredOff},
		},
		{
			name:      "blacklisting EventEx drops EventEx events with an EventTypeId",
			blacklist: []string{"EventEx"},
			steps: steps(updateSet("1", objUpdate(types.ObjectUpdateKindModify, change(latestPage,
				page(&types.EventEx{EventTypeId: "com.vmware.vc.authorization.NoPermission"}, poweredOn()))))),
			want: []string{typePoweredOn},
		},
		{
			name:      "blacklisting an EventTypeId drops that EventEx event",
			blacklist: []string{"com.vmware.vc.authorization.NoPermission"},
			steps: steps(updateSet("1", objUpdate(types.ObjectUpdateKindModify, change(latestPage,
				page(&types.EventEx{EventTypeId: "com.vmware.vc.authorization.NoPermission"}, poweredOn()))))),
			want: []string{typePoweredOn},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			h := newHarness(t, scriptedConfig(tc.blacklist...), tc.steps...)

			if err := h.run(); err != nil {
				t.Fatalf("loop returned %v, want nil", err)
			}

			if got := h.eventTypes(); !slices.Equal(got, tc.want) {
				t.Errorf("delivered = %v, want %v", got, tc.want)
			}
			for _, e := range h.events {
				if string(e.EmsID) != "42" {
					t.Errorf("EmsID = %q, want %q", e.EmsID, "42")
				}
			}
			if h.beats != len(tc.steps) {
				t.Errorf("heartbeats = %d, want one per wait return (%d)", h.beats, len(tc.steps))
			}
		})
	}
}

func TestLoop_WaitRequestAndVersionToken(t *testing.T) {
	t.Parallel()

	h := newHarness(t, scriptedConfig(), steps(
		truncated(updateSet("t1")), // truncated: the token must be sent back to resume
		updateSet("v1"),
		nil, // timeout: the version token must survive it
		updateSet("v2"),
	)...)
	if err := h.run(); err != nil {
		t.Fatalf("loop returned %v, want nil", err)
	}

	var versions []string
	for _, r := range h.rt.reqs {
		versions = append(versions, r.Version)
		if r.This != h.pc.Reference() {
			t.Errorf("request targets %v, want the property collector %v", r.This, h.pc.Reference())
		}
		if r.Options == nil || r.Options.MaxWaitSeconds == nil || *r.Options.MaxWaitSeconds != 7 {
			t.Errorf("request options = %+v, want MaxWaitSeconds=7", r.Options)
		}
	}
	// The 5th request is the one the exhausted script cancels.
	if want := []string{"", "t1", "v1", "v1", "v2"}; !slices.Equal(versions, want) {
		t.Errorf("version tokens sent = %v, want %v", versions, want)
	}
}

func TestLoop_Errors(t *testing.T) {
	t.Parallel()

	t.Run("wait failure is wrapped and returned", func(t *testing.T) {
		t.Parallel()
		h := newHarness(t, scriptedConfig(), rtStep{err: errBoom})

		err := h.run()
		if !errors.Is(err, errBoom) {
			t.Fatalf("err = %v, want it to wrap errBoom", err)
		}
		if !strings.HasPrefix(err.Error(), "WaitForUpdatesEx: ") {
			t.Errorf("err = %q, want WaitForUpdatesEx prefix", err)
		}
		if h.beats != 0 {
			t.Errorf("heartbeats = %d, want 0 (no successful wait)", h.beats)
		}
	})

	t.Run("wait failure after cancellation is a clean exit", func(t *testing.T) {
		t.Parallel()
		h := newHarness(t, scriptedConfig(), rtStep{err: errBoom, cancelCtx: true})

		if err := h.run(); err != nil {
			t.Fatalf("err = %v, want nil on cancellation", err)
		}
	})

	t.Run("wait failure after deadline expiry is a clean exit", func(t *testing.T) {
		t.Parallel()
		h := newHarness(t, scriptedConfig(), rtStep{err: context.DeadlineExceeded})
		ctx, cancel := context.WithDeadline(context.Background(), time.Unix(0, 0))
		t.Cleanup(cancel)
		h.ctx = ctx

		if err := h.run(); err != nil {
			t.Fatalf("err = %v, want nil on deadline", err)
		}
	})

	t.Run("handler error stops the loop and is returned unwrapped", func(t *testing.T) {
		t.Parallel()
		h := newHarness(t, scriptedConfig(), steps(
			updateSet("1", objUpdate(types.ObjectUpdateKindModify, change(latestPage, page(poweredOn(), poweredOff(), login())))),
			updateSet("2"),
		)...)

		var calls int
		err := h.runWith(func(_ context.Context, e *parser.Event) error {
			calls++
			h.events = append(h.events, e)
			if calls == 2 {
				return errBoom
			}
			return nil
		})

		if err != errBoom {
			t.Fatalf("err = %v, want errBoom returned as-is", err)
		}
		if got, want := h.eventTypes(), []string{typePoweredOn, typePoweredOff}; !slices.Equal(got, want) {
			t.Errorf("delivered = %v, want %v (stop mid-page)", got, want)
		}
		if len(h.rt.steps) != 1 {
			t.Errorf("unconsumed steps = %d, want 1 (loop must not poll again)", len(h.rt.steps))
		}
	})

	t.Run("handler receives the loop context", func(t *testing.T) {
		t.Parallel()
		h := newHarness(t, scriptedConfig(), steps(updateSet("1", objUpdate(types.ObjectUpdateKindModify, change(latestPage, page(poweredOn())))))...)

		var got context.Context
		_ = h.runWith(func(ctx context.Context, _ *parser.Event) error { got = ctx; return nil })
		if got != h.ctx {
			t.Error("onEvent did not receive the loop's context")
		}
	})
}

func TestLoop_Heartbeat(t *testing.T) {
	t.Parallel()

	t.Run("nil OnBeat is safe", func(t *testing.T) {
		t.Parallel()
		h := newHarness(t, scriptedConfig(), steps(nil, updateSet("1", objUpdate(types.ObjectUpdateKindModify, change(latestPage, page(poweredOn())))))...)
		h.sess.OnBeat = nil

		if err := h.run(); err != nil {
			t.Fatalf("loop returned %v, want nil", err)
		}
		if len(h.events) != 1 {
			t.Errorf("delivered %d events, want 1", len(h.events))
		}
	})

	t.Run("heartbeat failure is logged and does not stop the loop", func(t *testing.T) {
		t.Parallel()
		h := newHarness(t, scriptedConfig(), steps(nil, updateSet("1", objUpdate(types.ObjectUpdateKindModify, change(latestPage, page(poweredOn())))))...)
		h.beatErr = errBoom

		if err := h.run(); err != nil {
			t.Fatalf("loop returned %v, want nil", err)
		}
		if h.beats != 2 || len(h.events) != 1 {
			t.Errorf("beats=%d events=%d, want 2 and 1", h.beats, len(h.events))
		}
		if !strings.Contains(h.logs.String(), "heartbeat failed") {
			t.Errorf("log %q does not mention the heartbeat failure", h.logs.String())
		}
	})
}

func TestRun_HappyPath(t *testing.T) {
	t.Parallel()
	sim := newSim(t, simOptions{})

	res := sim.runUntilIdle(t, sim.config(t))

	if res.err != nil {
		t.Fatalf("Run returned %v, want nil", res.err)
	}
	if len(res.events) == 0 {
		t.Fatal("no events delivered from the initial latestPage snapshot")
	}

	// Setup order, exactly two polls, then teardown in reverse order.
	want := []string{
		methodLogin, methodCreateCollect, methodSetPageSize, methodCreateFilter,
		methodWait, methodWait,
		methodDestroyFilter, methodDestroyCollect, methodLogout,
	}
	if got := sim.calls.sequenceOf(want...); !slices.Equal(got, want) {
		t.Errorf("SOAP call order = %v, want %v", got, want)
	}
}

func TestRun_SetupFailures(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		fault   string
		wantErr string
		// Resources that exist when the failure happens must be destroyed; others must not be.
		wantDestroyCollect int
		wantDestroyFilter  int
	}{
		{name: "collector creation", fault: methodCreateCollect, wantErr: "CreateCollectorForEvents: "},
		{name: "page size", fault: methodSetPageSize, wantErr: "SetCollectorPageSize: ", wantDestroyCollect: 1},
		{name: "filter creation", fault: methodCreateFilter, wantErr: "CreateFilter: ", wantDestroyCollect: 1},
		{name: "first poll", fault: methodWait, wantErr: "WaitForUpdatesEx: ", wantDestroyCollect: 1, wantDestroyFilter: 1},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			sim := newSim(t, simOptions{Faults: []string{tc.fault}})

			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			t.Cleanup(cancel)
			res := sim.run(ctx, sim.config(t))

			if res.err == nil || !strings.Contains(res.err.Error(), tc.wantErr) {
				t.Fatalf("err = %v, want it to contain %q", res.err, tc.wantErr)
			}
			if got := sim.calls.count(methodLogout); got != 1 {
				t.Errorf("Logout calls = %d, want 1 (always log out once connected)", got)
			}
			if got := sim.calls.count(methodDestroyCollect); got != tc.wantDestroyCollect {
				t.Errorf("DestroyCollector calls = %d, want %d", got, tc.wantDestroyCollect)
			}
			if got := sim.calls.count(methodDestroyFilter); got != tc.wantDestroyFilter {
				t.Errorf("DestroyPropertyFilter calls = %d, want %d", got, tc.wantDestroyFilter)
			}
		})
	}
}

func TestRun_TeardownFailuresAreLoggedNotReturned(t *testing.T) {
	t.Parallel()

	tests := []struct {
		fault   string
		wantLog string
	}{
		{fault: methodDestroyFilter, wantLog: "DestroyPropertyFilter failed"},
		{fault: methodDestroyCollect, wantLog: "DestroyCollector failed"},
		{fault: methodLogout, wantLog: "Logout failed"},
	}
	for _, tc := range tests {
		t.Run(tc.fault, func(t *testing.T) {
			t.Parallel()
			sim := newSim(t, simOptions{Faults: []string{tc.fault}})

			res := sim.runUntilIdle(t, sim.config(t))

			if res.err != nil {
				t.Fatalf("Run returned %v, want nil (teardown errors are best-effort)", res.err)
			}
			if !strings.Contains(res.logs.String(), tc.wantLog) {
				t.Errorf("log %q does not contain %q", res.logs.String(), tc.wantLog)
			}
			// A failing step must not prevent the remaining steps.
			for _, m := range []string{methodDestroyFilter, methodDestroyCollect, methodLogout} {
				if got := sim.calls.count(m); got != 1 {
					t.Errorf("%s calls = %d, want 1", m, got)
				}
			}
		})
	}
}

func TestRun_Connect(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		tweak   func(t *testing.T, sim *simEnv, cfg *Config)
		wantErr string // empty means the session must connect and run
	}{
		{
			name:  "insecure ignores the CA setting",
			tweak: func(_ *testing.T, _ *simEnv, c *Config) { c.CertificateAuthority = "not a pem" },
		},
		{
			name:  "verification succeeds with the trusted CA",
			tweak: func(_ *testing.T, s *simEnv, c *Config) { c.VerifySSL, c.CertificateAuthority = 1, s.caPEM() },
		},
		{
			name:    "verification rejects an untrusted self-signed certificate",
			tweak:   func(_ *testing.T, _ *simEnv, c *Config) { c.VerifySSL = 1 },
			wantErr: "vSphere connect: vim25.NewClient: ",
		},
		{
			name:    "unparsable CA PEM",
			tweak:   func(_ *testing.T, _ *simEnv, c *Config) { c.VerifySSL, c.CertificateAuthority = 1, "not a pem" },
			wantErr: "vSphere connect: failed to parse certificate_authority PEM",
		},
		{
			name:    "unreachable host",
			tweak:   func(t *testing.T, _ *simEnv, c *Config) { c.Host, c.Port = closedAddr(t) },
			wantErr: "vSphere connect: vim25.NewClient: ",
		},
		{
			// vcsim's default login accepts any non-empty credentials; empty is rejected.
			name:    "rejected credentials",
			tweak:   func(_ *testing.T, _ *simEnv, c *Config) { c.Password = "" },
			wantErr: "vSphere connect: Login: ",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			sim := newSim(t, simOptions{TLS: true})
			cfg := sim.config(t)
			tc.tweak(t, sim, &cfg)

			var res runResult
			if tc.wantErr == "" {
				res = sim.runUntilIdle(t, cfg)
				if res.err != nil {
					t.Fatalf("Run returned %v, want nil", res.err)
				}
				return
			}

			// The timeout only bounds a regression where connect wrongly succeeds.
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			t.Cleanup(cancel)
			res = sim.run(ctx, cfg)
			if res.err == nil || !strings.Contains(res.err.Error(), tc.wantErr) {
				t.Fatalf("err = %v, want it to contain %q", res.err, tc.wantErr)
			}
			for _, m := range []string{methodCreateCollect, methodCreateFilter, methodLogout} {
				if got := sim.calls.count(m); got != 0 {
					t.Errorf("%s calls = %d, want 0 after a failed connect", m, got)
				}
			}
		})
	}
}
