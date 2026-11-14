// Package vim implements the vSphere layer: session management, event collector,
// property filter, and the WaitForUpdatesEx loop.
//
// See README.md for the behavior being preserved.
package vim

import (
	"context"
	"crypto/x509"
	"fmt"
	"log/slog"
	"net/url"
	"reflect"
	"strings"

	"github.com/vmware/govmomi/event"
	"github.com/vmware/govmomi/property"
	"github.com/vmware/govmomi/session"
	"github.com/vmware/govmomi/vim25"
	"github.com/vmware/govmomi/vim25/methods"
	"github.com/vmware/govmomi/vim25/soap"
	"github.com/vmware/govmomi/vim25/types"

	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/parser"
)

const (
	collectorPageSize  = 20
	defaultMaxWaitSecs = 60
)

// EventHandler is called for every event extracted from a WaitForUpdatesEx response.
// Returning a non-nil error stops the loop and causes Run to return that error.
type EventHandler func(ctx context.Context, e *parser.Event) error

// Session holds a live vSphere connection and drives the event loop.
type Session struct {
	scheme             string
	host               string
	port               int
	insecure           bool
	caPEM              string
	username, password string
	emsID              []byte
	blacklist          map[string]struct{}
	maxWaitSecs        int32

	log *slog.Logger

	// OnBeat is called after every WaitForUpdatesEx return (including empty timeouts).
	// Typically wired to (*heartbeat.Beater).Beat. nil is safe.
	OnBeat func() error
}

// Config is the minimal connection config that Session needs from internal/config.
type Config struct {
	Host                  string
	Port                  int
	VerifySSL             int    // 0 → insecure, anything else → verify
	CertificateAuthority  string // PEM text (not a path); empty → system roots
	Username, Password    string
	EmsID                 []byte // raw JSON, e.g. "42"
	BlacklistedEventNames []string
	Scheme                string // overrides URL scheme; default "https"
	MaxWaitSecs           int32  // overrides WaitForUpdatesEx MaxWaitSeconds; default 60
}

func New(cfg Config, log *slog.Logger) *Session {
	bl := make(map[string]struct{}, len(cfg.BlacklistedEventNames))
	for _, name := range cfg.BlacklistedEventNames {
		bl[name] = struct{}{}
	}
	scheme := cfg.Scheme
	if scheme == "" {
		scheme = "https"
	}
	maxWait := cfg.MaxWaitSecs
	if maxWait <= 0 {
		maxWait = defaultMaxWaitSecs
	}
	return &Session{
		scheme:      scheme,
		host:        cfg.Host,
		port:        cfg.Port,
		insecure:    cfg.VerifySSL == 0,
		caPEM:       cfg.CertificateAuthority,
		username:    cfg.Username,
		password:    cfg.Password,
		emsID:       cfg.EmsID,
		blacklist:   bl,
		maxWaitSecs: maxWait,
		log:         log,
	}
}

// Run connects, subscribes to events, and loops until ctx is cancelled or a fatal error.
// Teardown always runs on a fresh context so a cancelled ctx does not block cleanup.
func (s *Session) Run(ctx context.Context, onEvent EventHandler) error {
	vimClient, sm, err := s.connect(ctx)
	if err != nil {
		return fmt.Errorf("vSphere connect: %w", err)
	}

	var filter *property.Filter
	var collector *event.HistoryCollector

	defer func() {
		bg := context.Background()
		if filter != nil {
			if err := filter.Destroy(bg); err != nil {
				s.log.Warn("DestroyPropertyFilter failed", "err", err)
			}
		}
		if collector != nil {
			if err := collector.Destroy(bg); err != nil {
				s.log.Warn("DestroyCollector failed", "err", err)
			}
		}
		if err := sm.Logout(bg); err != nil {
			s.log.Warn("Logout failed", "err", err)
		}
	}()

	eventMgr := event.NewManager(vimClient)
	collector, err = eventMgr.CreateCollectorForEvents(ctx, types.EventFilterSpec{})
	if err != nil {
		return fmt.Errorf("CreateCollectorForEvents: %w", err)
	}
	if err := collector.SetPageSize(ctx, collectorPageSize); err != nil {
		return fmt.Errorf("SetCollectorPageSize: %w", err)
	}

	pc := property.DefaultCollector(vimClient)
	collectorType := collector.Reference().Type
	filter, err = pc.CreateFilter(ctx, types.CreateFilter{
		Spec: types.PropertyFilterSpec{
			ObjectSet: []types.ObjectSpec{{
				Obj: collector.Reference(),
			}},
			PropSet: []types.PropertySpec{{
				Type:    collectorType,
				All:     types.NewBool(false),
				PathSet: []string{"latestPage"},
			}},
		},
		PartialUpdates: true,
	})
	if err != nil {
		return fmt.Errorf("CreateFilter: %w", err)
	}

	return s.loop(ctx, vimClient, pc, onEvent)
}

func (s *Session) loop(
	ctx context.Context,
	vimClient *vim25.Client,
	pc *property.Collector,
	onEvent EventHandler,
) error {
	version := ""

	for {
		req := types.WaitForUpdatesEx{
			This:    pc.Reference(),
			Version: version,
			Options: &types.WaitOptions{MaxWaitSeconds: types.NewInt32(s.maxWaitSecs)},
		}

		res, err := methods.WaitForUpdatesEx(ctx, vimClient, &req)
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return fmt.Errorf("WaitForUpdatesEx: %w", err)
		}

		if s.OnBeat != nil {
			if hbErr := s.OnBeat(); hbErr != nil {
				s.log.Warn("heartbeat failed", "err", hbErr)
			}
		}

		if res.Returnval == nil {
			continue
		}

		version = res.Returnval.Version

		if err := s.handleUpdateSet(ctx, res.Returnval, onEvent); err != nil {
			return err
		}
	}
}

func (s *Session) handleUpdateSet(ctx context.Context, us *types.UpdateSet, onEvent EventHandler) error {
	for _, fs := range us.FilterSet {
		for _, obj := range fs.ObjectSet {
			if err := s.handleObjectUpdate(ctx, obj, onEvent); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *Session) handleObjectUpdate(ctx context.Context, obj types.ObjectUpdate, onEvent EventHandler) error {
	if obj.Kind != types.ObjectUpdateKindModify && obj.Kind != types.ObjectUpdateKindEnter {
		return nil
	}

	for _, cs := range obj.ChangeSet {
		if err := s.handleChange(ctx, cs, onEvent); err != nil {
			return err
		}
	}
	return nil
}

func (s *Session) handleChange(ctx context.Context, cs types.PropertyChange, onEvent EventHandler) error {
	if !strings.HasPrefix(cs.Name, "latestPage") {
		return nil
	}

	// The initial update assigns the whole page as an ArrayOfEvent.
	var events []types.BaseEvent
	if page, ok := cs.Val.(types.ArrayOfEvent); ok {
		events = page.Event
	} else if evt, ok := asBaseEvent(cs.Val); ok {
		events = []types.BaseEvent{evt}
	} else {
		return nil
	}

	for _, rawEvt := range events {
		evt := parser.Parse(rawEvt)
		evt.EmsID = s.emsID

		if s.isBlacklisted(rawEvt, evt.EventType) {
			continue
		}

		if err := onEvent(ctx, evt); err != nil {
			return err
		}
	}
	return nil
}

// isBlacklisted matches either the resolved event type or the raw vim type name (e.g. "EventEx").
func (s *Session) isBlacklisted(raw types.BaseEvent, resolvedType string) bool {
	if _, ok := s.blacklist[resolvedType]; ok {
		return true
	}
	_, ok := s.blacklist[reflect.Indirect(reflect.ValueOf(raw)).Type().Name()]
	return ok
}

// asBaseEvent converts a nested-change value to a types.BaseEvent. vCenter sends these as plain
// structs (types.UserLoginSessionEvent), but BaseEvent is implemented on the pointer type, so a
// plain type assertion fails. It returns false for nil and for anything that is not an event.
func asBaseEvent(v any) (types.BaseEvent, bool) {
	if e, ok := v.(types.BaseEvent); ok {
		return e, true
	}
	rv := reflect.ValueOf(v)
	if !rv.IsValid() || rv.Kind() != reflect.Struct {
		return nil, false
	}
	ptr := reflect.New(rv.Type())
	ptr.Elem().Set(rv)
	e, ok := ptr.Interface().(types.BaseEvent)
	return e, ok
}

func (s *Session) connect(ctx context.Context) (*vim25.Client, *session.Manager, error) {
	u := &url.URL{
		Scheme: s.scheme,
		Host:   fmt.Sprintf("%s:%d", s.host, s.port),
		Path:   "/sdk",
	}

	soapClient := soap.NewClient(u, s.insecure)

	if !s.insecure && s.caPEM != "" {
		pool := x509.NewCertPool()
		if !pool.AppendCertsFromPEM([]byte(s.caPEM)) {
			return nil, nil, fmt.Errorf("failed to parse certificate_authority PEM")
		}
		soapClient.DefaultTransport().TLSClientConfig.RootCAs = pool
	}

	vimClient, err := vim25.NewClient(ctx, soapClient)
	if err != nil {
		return nil, nil, fmt.Errorf("vim25.NewClient: %w", err)
	}

	sm := session.NewManager(vimClient)
	if err := sm.Login(ctx, url.UserPassword(s.username, s.password)); err != nil {
		return nil, nil, fmt.Errorf("Login: %w", err)
	}

	return vimClient, sm, nil
}
