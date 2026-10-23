package heartbeat_test

import (
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/heartbeat"
)

// clearEnv clears both heartbeat env vars and restores them after the test.
func clearEnv(t *testing.T) {
	t.Helper()
	old := map[string]string{
		"NOTIFY_SOCKET":         os.Getenv("NOTIFY_SOCKET"),
		"WORKER_HEARTBEAT_FILE": os.Getenv("WORKER_HEARTBEAT_FILE"),
	}
	os.Unsetenv("NOTIFY_SOCKET")
	os.Unsetenv("WORKER_HEARTBEAT_FILE")
	t.Cleanup(func() {
		for k, v := range old {
			if v == "" {
				os.Unsetenv(k)
			} else {
				os.Setenv(k, v)
			}
		}
	})
}

// listenUnixgram opens a unixgram socket and returns it.
// It uses os.MkdirTemp with a short prefix to stay within macOS's 104-byte
// unix socket path limit, which t.TempDir() can exceed when the test name is long.
func listenUnixgram(t *testing.T) (net.PacketConn, string) {
	t.Helper()
	dir, err := os.MkdirTemp("", "hb")
	if err != nil {
		t.Fatalf("MkdirTemp: %v", err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	sockPath := filepath.Join(dir, "n.sock")
	pc, err := net.ListenPacket("unixgram", sockPath)
	if err != nil {
		t.Fatalf("ListenPacket: %v", err)
	}
	t.Cleanup(func() { pc.Close() })
	return pc, sockPath
}

// recvDatagram reads one datagram from pc and returns it as a string.
func recvDatagram(t *testing.T, pc net.PacketConn) string {
	t.Helper()
	buf := make([]byte, 256)
	pc.SetDeadline(time.Now().Add(2 * time.Second))
	n, _, err := pc.ReadFrom(buf)
	if err != nil {
		t.Fatalf("ReadFrom: %v", err)
	}
	return string(buf[:n])
}

// TestBeatFileMode covers the file-mode behaviour of Beat.
func TestBeatFileMode(t *testing.T) {
	t.Run("writes now+timeout epoch to the heartbeat file", func(t *testing.T) {
		clearEnv(t)
		f := filepath.Join(t.TempDir(), "heartbeat")
		os.Setenv("WORKER_HEARTBEAT_FILE", f)

		const timeout = 120
		b := heartbeat.New(timeout)

		before := time.Now().Unix()
		if err := b.Beat(); err != nil {
			t.Fatalf("Beat: %v", err)
		}
		after := time.Now().Unix()

		raw, err := os.ReadFile(f)
		if err != nil {
			t.Fatalf("ReadFile: %v", err)
		}
		epoch, err := strconv.ParseInt(strings.TrimSpace(string(raw)), 10, 64)
		if err != nil {
			t.Fatalf("parse epoch %q: %v", string(raw), err)
		}

		lo, hi := before+timeout, after+timeout
		if epoch < lo || epoch > hi {
			t.Errorf("epoch %d not in [%d, %d]", epoch, lo, hi)
		}
	})

	t.Run("rewrites the file on every call", func(t *testing.T) {
		clearEnv(t)
		f := filepath.Join(t.TempDir(), "heartbeat")
		os.Setenv("WORKER_HEARTBEAT_FILE", f)

		b := heartbeat.New(120)
		if err := b.Beat(); err != nil {
			t.Fatalf("first Beat: %v", err)
		}
		fi1, err := os.Stat(f)
		if err != nil {
			t.Fatalf("Stat after first Beat: %v", err)
		}

		time.Sleep(10 * time.Millisecond)

		if err := b.Beat(); err != nil {
			t.Fatalf("second Beat: %v", err)
		}
		fi2, err := os.Stat(f)
		if err != nil {
			t.Fatalf("Stat after second Beat: %v", err)
		}

		if !fi2.ModTime().After(fi1.ModTime()) {
			t.Error("file mtime did not advance on second Beat call")
		}
	})

	t.Run("returns error when file path is unwritable", func(t *testing.T) {
		clearEnv(t)
		os.Setenv("WORKER_HEARTBEAT_FILE", "/nonexistent/dir/heartbeat")

		b := heartbeat.New(120)
		if err := b.Beat(); err == nil {
			t.Error("expected error writing to unwritable path, got nil")
		}
	})

	t.Run("Ready and Stopping are no-ops in file mode", func(t *testing.T) {
		clearEnv(t)
		f := filepath.Join(t.TempDir(), "heartbeat")
		os.Setenv("WORKER_HEARTBEAT_FILE", f)

		b := heartbeat.New(120)
		if err := b.Ready(); err != nil {
			t.Errorf("Ready in file mode: %v", err)
		}
		if err := b.Stopping(); err != nil {
			t.Errorf("Stopping in file mode: %v", err)
		}
		// Neither should have created the file.
		if _, err := os.Stat(f); err == nil {
			t.Error("heartbeat file should not exist after Ready/Stopping in file mode")
		}
	})
}

// TestNoopMode verifies that all three methods succeed silently when no env vars are set.
func TestNoopMode(t *testing.T) {
	clearEnv(t)
	b := heartbeat.New(120)
	if err := b.Beat(); err != nil {
		t.Errorf("Beat noop: %v", err)
	}
	if err := b.Ready(); err != nil {
		t.Errorf("Ready noop: %v", err)
	}
	if err := b.Stopping(); err != nil {
		t.Errorf("Stopping noop: %v", err)
	}
}

// TestSDNotifyMode verifies that each method sends the correct sd_notify datagram.
func TestSDNotifyMode(t *testing.T) {
	signals := []struct {
		name string
		call func(b *heartbeat.Beater) error
		want string
	}{
		{"Ready sends READY=1", func(b *heartbeat.Beater) error { return b.Ready() }, "READY=1"},
		{"Beat sends WATCHDOG=1", func(b *heartbeat.Beater) error { return b.Beat() }, "WATCHDOG=1"},
		{"Stopping sends STOPPING=1", func(b *heartbeat.Beater) error { return b.Stopping() }, "STOPPING=1"},
	}

	for _, tc := range signals {
		t.Run(tc.name, func(t *testing.T) {
			clearEnv(t)
			pc, sockPath := listenUnixgram(t)
			os.Setenv("NOTIFY_SOCKET", sockPath)

			b := heartbeat.New(120)
			if err := tc.call(b); err != nil {
				t.Fatalf("call: %v", err)
			}
			if got := recvDatagram(t, pc); got != tc.want {
				t.Errorf("datagram = %q, want %q", got, tc.want)
			}
		})
	}
}

// TestNewEnvPriority verifies that NOTIFY_SOCKET takes precedence over
// WORKER_HEARTBEAT_FILE when both are set.
func TestNewEnvPriority(t *testing.T) {
	clearEnv(t)
	pc, sockPath := listenUnixgram(t)
	os.Setenv("NOTIFY_SOCKET", sockPath)
	os.Setenv("WORKER_HEARTBEAT_FILE", filepath.Join(t.TempDir(), "heartbeat"))

	b := heartbeat.New(120)
	// In sd_notify mode Beat sends WATCHDOG=1, not a file write.
	if err := b.Beat(); err != nil {
		t.Fatalf("Beat: %v", err)
	}
	if got := recvDatagram(t, pc); got != "WATCHDOG=1" {
		t.Errorf("datagram = %q, want WATCHDOG=1; NOTIFY_SOCKET should take priority", got)
	}
}
