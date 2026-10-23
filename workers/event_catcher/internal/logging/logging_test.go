package logging_test

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"os"
	"strings"
	"testing"

	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/logging"
)

// TestMapLevel verifies the slog.Level → ManageIQ level string mapping,
// including boundary values.
func TestMapLevel(t *testing.T) {
	cases := []struct {
		level slog.Level
		want  string
	}{
		{slog.LevelDebug, "debug"},
		{slog.LevelDebug + 1, "debug"},
		{slog.LevelInfo - 1, "debug"},
		{slog.LevelInfo, "info"},
		{slog.LevelInfo + 1, "info"},
		{slog.LevelWarn - 1, "info"},
		{slog.LevelWarn, "warning"},
		{slog.LevelWarn + 1, "warning"},
		{slog.LevelError - 1, "warning"},
		{slog.LevelError, "err"},
		{slog.LevelError + 1, "err"},
	}
	for _, tc := range cases {
		t.Run(tc.level.String(), func(t *testing.T) {
			var buf bytes.Buffer
			os.Setenv("CONTAINER", "1")
			t.Cleanup(func() { os.Unsetenv("CONTAINER") })

			log := logging.NewWithWriter(&buf)
			log.Log(nil, tc.level, "probe") //nolint:staticcheck // nil ctx is fine for slog
			var wire map[string]interface{}
			if err := json.Unmarshal(buf.Bytes(), &wire); err != nil {
				t.Fatalf("json.Unmarshal: %v", err)
			}
			if got, _ := wire["level"].(string); got != tc.want {
				t.Errorf("level %v: got %q, want %q", tc.level, got, tc.want)
			}
		})
	}
}

// TestJSONHandlerFields verifies that every required ManageIQ JSON field is
// present in the output and has the right type.
func TestJSONHandlerFields(t *testing.T) {
	os.Setenv("CONTAINER", "1")
	t.Cleanup(func() { os.Unsetenv("CONTAINER") })

	var buf bytes.Buffer
	log := logging.NewWithWriter(&buf)
	log.Info("hello world", "key", "value")

	var wire map[string]interface{}
	if err := json.Unmarshal(buf.Bytes(), &wire); err != nil {
		t.Fatalf("json.Unmarshal: %v", err)
	}

	t.Run("required fields are present", func(t *testing.T) {
		for _, field := range []string{"@timestamp", "hostname", "pid", "tid", "service", "level", "message"} {
			if _, ok := wire[field]; !ok {
				t.Errorf("missing field %q", field)
			}
		}
	})

	t.Run("service is evm", func(t *testing.T) {
		if got, _ := wire["service"].(string); got != "evm" {
			t.Errorf("service = %q, want evm", got)
		}
	})

	t.Run("message matches input", func(t *testing.T) {
		if got, _ := wire["message"].(string); got != "hello world" {
			t.Errorf("message = %q, want hello world", got)
		}
	})

	t.Run("extra attrs appear in output", func(t *testing.T) {
		if got, _ := wire["key"].(string); got != "value" {
			t.Errorf("key = %q, want value", got)
		}
	})

	t.Run("pid is a positive number", func(t *testing.T) {
		pid, ok := wire["pid"].(float64)
		if !ok || pid <= 0 {
			t.Errorf("pid = %v, want positive number", wire["pid"])
		}
	})

	t.Run("tid is a positive number", func(t *testing.T) {
		tid, ok := wire["tid"].(float64)
		if !ok || tid <= 0 {
			t.Errorf("tid = %v, want positive number", wire["tid"])
		}
	})
}

// TestJSONHandlerWithAttrs verifies that attrs added via logger.With appear in output.
func TestJSONHandlerWithAttrs(t *testing.T) {
	os.Setenv("CONTAINER", "1")
	t.Cleanup(func() { os.Unsetenv("CONTAINER") })

	var buf bytes.Buffer
	log := logging.NewWithWriter(&buf).With("ems_id", "42")
	log.Info("test")

	var wire map[string]interface{}
	if err := json.Unmarshal(buf.Bytes(), &wire); err != nil {
		t.Fatalf("json.Unmarshal: %v", err)
	}
	if got, _ := wire["ems_id"].(string); got != "42" {
		t.Errorf("ems_id = %q, want 42", got)
	}
}

// TestNewHandlerEnvSwitch verifies CONTAINER produces JSON and its absence produces text.
func TestNewHandlerEnvSwitch(t *testing.T) {
	t.Run("CONTAINER set produces JSON output", func(t *testing.T) {
		os.Setenv("CONTAINER", "1")
		t.Cleanup(func() { os.Unsetenv("CONTAINER") })

		var buf bytes.Buffer
		logging.NewWithWriter(&buf).Info("json-mode")
		if !json.Valid(buf.Bytes()) {
			t.Errorf("expected valid JSON, got %q", buf.String())
		}
	})

	t.Run("CONTAINER unset produces text output", func(t *testing.T) {
		os.Unsetenv("CONTAINER")
		var buf bytes.Buffer
		logging.NewWithWriter(&buf).Info("text-mode")
		if json.Valid(bytes.TrimSpace(buf.Bytes())) {
			t.Errorf("expected text output, got JSON: %q", buf.String())
		}
	})
}

// TestMsg verifies the MIQ prefix is prepended.
func TestMsg(t *testing.T) {
	got := logging.Msg("starting")
	if !strings.HasPrefix(got, "MIQ(") {
		t.Errorf("Msg(%q) = %q, want MIQ(...) prefix", "starting", got)
	}
	if !strings.HasSuffix(got, "starting") {
		t.Errorf("Msg(%q) = %q, want suffix 'starting'", "starting", got)
	}
}
