// Package heartbeat implements the two liveness mechanisms used by ManageIQ core:
//
//   - systemd sd_notify datagrams (when NOTIFY_SOCKET is set)
//   - epoch-seconds written to WORKER_HEARTBEAT_FILE (when that env var is set)
//
// When neither variable is set the package is a no-op, which is normal for local development.
// See README.md "Worker Contract & Behavior".
package heartbeat

import (
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"time"
)

// Beater sends liveness signals.
type Beater struct {
	mode          mode
	socketPath    string
	heartbeatFile string
	timeout       int
}

type mode int

const (
	modeNoop     mode = iota
	modeSDNotify      // NOTIFY_SOCKET is set
	modeFile          // WORKER_HEARTBEAT_FILE is set
)

// New reads the environment and returns a Beater configured for the current environment.
// timeout is the heartbeat_timeout value from config (seconds), used when writing the file.
func New(timeout int) *Beater {
	if sock := os.Getenv("NOTIFY_SOCKET"); sock != "" {
		return &Beater{mode: modeSDNotify, socketPath: sock, timeout: timeout}
	}
	if file := os.Getenv("WORKER_HEARTBEAT_FILE"); file != "" {
		return &Beater{mode: modeFile, heartbeatFile: file, timeout: timeout}
	}
	return &Beater{mode: modeNoop}
}

// Ready signals that the worker is ready and its main loop has started (sd_notify READY=1).
func (b *Beater) Ready() error {
	if b.mode == modeSDNotify {
		return b.notify("READY=1")
	}
	return nil
}

// Beat is called after every WaitForUpdatesEx return (including empty timeouts).
//   - sd_notify mode: sends WATCHDOG=1
//   - file mode: writes "now + timeout" epoch seconds to the heartbeat file
//   - no-op mode: does nothing
func (b *Beater) Beat() error {
	switch b.mode {
	case modeSDNotify:
		return b.notify("WATCHDOG=1")
	case modeFile:
		deadline := time.Now().Unix() + int64(b.timeout)
		return os.WriteFile(b.heartbeatFile, []byte(strconv.FormatInt(deadline, 10)+"\n"), 0o644)
	}
	return nil
}

// Stopping sends sd_notify STOPPING=1.
func (b *Beater) Stopping() error {
	if b.mode == modeSDNotify {
		return b.notify("STOPPING=1")
	}
	return nil
}

// notify sends a single datagram to the NOTIFY_SOCKET.
// A leading '@' in the path means an abstract socket (Linux); replace it with a null byte.
func (b *Beater) notify(payload string) error {
	addr := b.socketPath
	if strings.HasPrefix(addr, "@") {
		addr = "\x00" + addr[1:]
	}

	conn, err := net.Dial("unixgram", addr)
	if err != nil {
		return fmt.Errorf("sd_notify dial %s: %w", b.socketPath, err)
	}
	defer conn.Close()

	_, err = fmt.Fprint(conn, payload)
	return err
}
