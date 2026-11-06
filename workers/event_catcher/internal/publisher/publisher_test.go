package publisher

import (
	"context"
	"io"
	"log/slog"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/parser"
)

// testCAPEM is a self-signed certificate used only to exercise buildTLS PEM parsing.
// It has no trust value; the CN is "test" and it expired quickly by design.
const testCAPEM = `-----BEGIN CERTIFICATE-----
MIIC/zCCAeegAwIBAgIUYum9ICz8SIBQYNoM62tCFlOO05AwDQYJKoZIhvcNAQEL
BQAwDzENMAsGA1UEAwwEdGVzdDAeFw0yNjEwMjMxNDEzNTNaFw0yNjEwMjQxNDEz
NTNaMA8xDTALBgNVBAMMBHRlc3QwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
AoIBAQDOgv4c1zdlUWtFfkC7CoaWPkBm2bLbChGC3dRPbrCh7pYfazHlUCKv8SuH
ty62zCAj3W7GuNTFzcv2/ovnwY3P+pi+pxYZ9ZBUBkhh9EYpL0BmIjqo6w6fVIqu
QY3mLLUUwQ7rWPWkCMUlu7hbHfiwGxRo7+jqCFJY/9SzWZsLmkiY16LwKk4EQkLP
xnBBIubS02UtBE03WeiEu0qwwjltR5lRjmSlMnPrrW9fCN1aKvGBKY4wFo3c+2Or
unmtW/jPoSAh3/YHfc0HAkt6gEq7BOw6d49dNRxMrFolSllcRcng294O9Ur8VNqQ
Iyb0vnpK2wRYBqudTRDUNfAHfZ2RAgMBAAGjUzBRMB0GA1UdDgQWBBS6JcsfRoil
HtMWD02e36Bhx2/jbDAfBgNVHSMEGDAWgBS6JcsfRoilHtMWD02e36Bhx2/jbDAP
BgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQBp1nzwVaVfSG5IWKp5
b5B1BOrFFQNqTSRrX7bIrQ4x+Nd1pKkPYoSFkMJYZKDehsT16qgnyMU1+nNm08cF
Rb5VUHVKnCUCEmDXqnR1JkGVnNKavRc8oLHwDHa3xOkfwr55hkN2FMsORnYn7Vlx
Ea9XOJ4V0vRQpCDBL5CmQOTu5rP8NBFky7Kk0l6kB5xNBE53hKgyWrt6jwN3tnW2
gjQai2NMpb0qiMD/6x3gu6r1GuR86LIQKdeJpx2p6TrFtHpg8j+DP+xnPFjIu/AO
oSTalegsqc3aI5qWZO3V6591kSC0oJ/0L7qdEqDfnTMs355/RjRvd0iS+Zhi1RQc
GTUe
-----END CERTIFICATE-----
`

// TestEmsIDString covers numeric, quoted-string, and edge-case inputs.
func TestEmsIDString(t *testing.T) {
	cases := []struct {
		raw  string
		want string
	}{
		{`42`, "42"},
		{`123`, "123"},
		{`"42"`, "42"},
		{`"my-ems"`, "my-ems"},
		{`""`, ""},
		{``, ""},
	}
	for _, tc := range cases {
		t.Run(tc.raw, func(t *testing.T) {
			got := emsIDString([]byte(tc.raw))
			if got != tc.want {
				t.Errorf("emsIDString(%q) = %q, want %q", tc.raw, got, tc.want)
			}
		})
	}
}

// TestBuildSASL covers the empty default, all supported mechanisms (upper and
// lower case), and an unsupported mechanism.
func TestBuildSASL(t *testing.T) {
	cases := []struct {
		mechanism string
		wantErr   bool
	}{
		{"", false}, // defaults to PLAIN
		{"PLAIN", false},
		{"plain", false}, // case-insensitive
		{"SCRAM-SHA-256", false},
		{"scram-sha-256", false},
		{"SCRAM-SHA-512", false},
		{"scram-sha-512", false},
		{"GSSAPI", true},      // unsupported
		{"OAUTHBEARER", true}, // unsupported
	}
	for _, tc := range cases {
		t.Run(tc.mechanism, func(t *testing.T) {
			mech, err := buildSASL(tc.mechanism, "user", "pass")
			if tc.wantErr {
				if err == nil {
					t.Errorf("buildSASL(%q): expected error, got nil", tc.mechanism)
				}
				return
			}
			if err != nil {
				t.Errorf("buildSASL(%q): unexpected error: %v", tc.mechanism, err)
			}
			if mech == nil {
				t.Errorf("buildSASL(%q): expected non-nil mechanism", tc.mechanism)
			}
		})
	}
}

// TestBuildTLS covers system-roots (no CA file), a valid PEM CA file, a
// missing file, and a file containing no valid PEM certificates.
func TestBuildTLS(t *testing.T) {
	t.Run("no CA file uses system roots", func(t *testing.T) {
		cfg, err := buildTLS("")
		if err != nil {
			t.Fatal(err)
		}
		if cfg.RootCAs != nil {
			t.Error("RootCAs should be nil (system roots) when ca_file is empty")
		}
	})

	t.Run("valid PEM CA file is loaded", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "ca.pem")
		if err := os.WriteFile(path, []byte(testCAPEM), 0600); err != nil {
			t.Fatal(err)
		}
		cfg, err := buildTLS(path)
		if err != nil {
			t.Fatalf("buildTLS with valid CA: %v", err)
		}
		if cfg.RootCAs == nil {
			t.Error("RootCAs should be non-nil when a valid CA file is provided")
		}
	})

	t.Run("missing file returns error", func(t *testing.T) {
		_, err := buildTLS("/nonexistent/ca.pem")
		if err == nil {
			t.Error("expected error for missing ca_file")
		}
	})

	t.Run("file with no valid PEM returns error", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "bad.pem")
		if err := os.WriteFile(path, []byte("not a certificate"), 0600); err != nil {
			t.Fatal(err)
		}
		_, err := buildTLS(path)
		if err == nil {
			t.Error("expected error when PEM file contains no valid certificates")
		}
	})
}

func TestSeedBrokers(t *testing.T) {
	tests := []struct {
		name string
		cfg  Config
		want []string
	}{
		{"single host", Config{Host: "k1", Port: 9092}, []string{"k1:9092"}},
		{"hosts list shares the port", Config{Hosts: []string{"k1", "k2", "k3"}, Port: 9093}, []string{"k1:9093", "k2:9093", "k3:9093"}},
		{"hosts wins over host", Config{Host: "ignored", Hosts: []string{"k1"}, Port: 9092}, []string{"k1:9092"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := seedBrokers(tt.cfg); !reflect.DeepEqual(got, tt.want) {
				t.Errorf("got %v, want %v", got, tt.want)
			}
		})
	}
}

// TestPublishTimesOutOnSilentBroker uses a listener that accepts connections and never replies.
func TestPublishTimesOutOnSilentBroker(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go io.Copy(io.Discard, c)
		}
	}()

	old := deliveryTimeout
	deliveryTimeout = time.Second
	defer func() { deliveryTimeout = old }()

	p, err := New(Config{Host: "127.0.0.1", Port: ln.Addr().(*net.TCPAddr).Port, EmsID: []byte("1")}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil {
		t.Fatal(err)
	}
	defer p.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	start := time.Now()
	if err := p.Publish(ctx, &parser.Event{EventType: "x"}); err == nil {
		t.Fatal("expected an error from a silent broker")
	}
	if ctx.Err() != nil {
		t.Fatalf("Publish only returned when the context expired (after %s); delivery timeout not applied", time.Since(start))
	}
}
