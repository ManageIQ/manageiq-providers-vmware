// Package logging sets up a log/slog logger that matches the ManageIQ logging conventions.
//
// Three modes, selected by environment variable:
//
//   - CONTAINER set: one JSON object per line with keys @timestamp, hostname, pid, tid,
//     service, level, message.  Level strings: debug, info, warning, err, crit.
//   - APPLIANCE set: plain text on stdout (journald captures stdout from the unit).
//   - otherwise: human-readable text on stdout (for local development).
//
// All messages produced via [Logger] include the MIQ(...) prefix required by existing
// log searches in ManageIQ Core.
package logging

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"os"
	"runtime"
	"time"
)

const (
	miqPrefix = "MIQ(ManageIQ::Providers::Vmware::InfraManager::EventCatcher) "
	service   = "evm"
)

// New returns a *slog.Logger configured for the current environment.
func New() *slog.Logger {
	h := newHandler(os.Stdout)
	return slog.New(h)
}

func newHandler(w io.Writer) slog.Handler {
	if os.Getenv("CONTAINER") != "" {
		return &jsonHandler{w: w}
	}
	opts := &slog.HandlerOptions{Level: slog.LevelDebug}
	return slog.NewTextHandler(w, opts)
}

// NewWithWriter creates a logger writing to w.
func NewWithWriter(w io.Writer) *slog.Logger {
	return slog.New(newHandler(w))
}

// Msg prepends the MIQ prefix to a message string.
func Msg(msg string) string {
	return miqPrefix + msg
}

// jsonHandler emits one JSON object per line matching ManageIQ::Loggers::JSONLogger.
type jsonHandler struct {
	w     io.Writer
	attrs []slog.Attr
	group string
}

func (h *jsonHandler) Enabled(_ context.Context, _ slog.Level) bool { return true }

func (h *jsonHandler) Handle(_ context.Context, r slog.Record) error {
	hostname, _ := os.Hostname()

	obj := map[string]interface{}{
		"@timestamp": r.Time.UTC().Format(time.RFC3339Nano),
		"hostname":   hostname,
		"pid":        os.Getpid(),
		"tid":        goroutineID(),
		"service":    service,
		"level":      mapLevel(r.Level),
		"message":    r.Message,
	}

	r.Attrs(func(a slog.Attr) bool {
		obj[a.Key] = a.Value.Any()
		return true
	})
	for _, a := range h.attrs {
		obj[a.Key] = a.Value.Any()
	}

	b, err := json.Marshal(obj)
	if err != nil {
		return err
	}
	b = append(b, '\n')
	_, err = h.w.Write(b)
	return err
}

func (h *jsonHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	merged := make([]slog.Attr, len(h.attrs)+len(attrs))
	copy(merged, h.attrs)
	copy(merged[len(h.attrs):], attrs)
	return &jsonHandler{w: h.w, attrs: merged, group: h.group}
}

func (h *jsonHandler) WithGroup(name string) slog.Handler {
	return &jsonHandler{w: h.w, attrs: h.attrs, group: name}
}

func mapLevel(l slog.Level) string {
	switch {
	case l >= slog.LevelError:
		return "err"
	case l >= slog.LevelWarn:
		return "warning"
	case l >= slog.LevelInfo:
		return "info"
	default:
		return "debug"
	}
}

// goroutineID returns a best-effort goroutine id by parsing the runtime stack header.
func goroutineID() int {
	var buf [64]byte
	n := runtime.Stack(buf[:], false)
	var id int
	fmt.Sscanf(string(buf[:n]), "goroutine %d ", &id)
	return id
}
