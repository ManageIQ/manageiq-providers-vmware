package config_test

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"reflect"
	"strings"
	"testing"
	"testing/iotest"

	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/config"
)

const (
	vcenterType  = "ManageIQ::Providers::Vmware::InfraManager"
	networkType  = "ManageIQ::Providers::Vmware::NetworkManager"
	errInvalid   = "Invalid argument format"
	errNoMessage = "messaging configuration is missing"
)

// validDoc returns a mutatable stdin document; tests modify only the fields they care about.
func validDoc() map[string]any {
	return map[string]any{
		"messaging": map[string]any{
			"protocol": "Kafka",
			"host":     "kafka.example.com",
			"port":     9092,
			"username": "user",
			"password": "pass",
			"ssl":      false,
		},
		"settings": map[string]any{
			"ems": map[string]any{
				"ems_vmware": map[string]any{
					"blacklisted_event_names":   []string{"UserLoginSessionEvent"},
					"minimum_supported_version": "6.0",
				},
			},
			"worker_settings": map[string]any{"heartbeat_timeout": 90},
		},
		"ems": []any{
			map[string]any{
				"type":            vcenterType,
				"id":              42,
				"endpoints":       []any{endpoint("default", "vcenter.example.com")},
				"authentications": []any{auth("default", "admin")},
			},
		},
	}
}

func endpoint(role, host string) map[string]any {
	return map[string]any{"role": role, "hostname": host, "port": 443, "verify_ssl": 1}
}

func auth(authType, user string) map[string]any {
	return map[string]any{"authtype": authType, "userid": user, "password": "secret"}
}

func firstEMS(d map[string]any) map[string]any {
	return d["ems"].([]any)[0].(map[string]any)
}

func toReader(t *testing.T, d map[string]any) io.Reader {
	t.Helper()
	b, err := json.Marshal(d)
	if err != nil {
		t.Fatalf("marshal test document: %v", err)
	}
	return bytes.NewReader(b)
}

func mustParse(t *testing.T, d map[string]any) *config.Config {
	t.Helper()
	cfg, err := config.Parse(toReader(t, d))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	return cfg
}

func TestParse_FullDocument(t *testing.T) {
	// A realistic payload as written by core: extra attributes ("name", "zone") that must be
	// ignored, a console endpoint and a metrics authentication that must not be selected,
	// and a child NetworkManager that must be skipped. heartbeat_timeout is deliberately not
	// the default so the test fails if the value is ignored.
	const ca = "-----BEGIN CERTIFICATE-----\nMIIBkDCB+aADAgECAgEBMA0GCSqGSIb3DQEBCwUAMBMxETAPBgNVBAMMCHZjYS1yb290\n-----END CERTIFICATE-----\n"
	doc := `{
	  "messaging": {
	    "protocol": "Kafka",
	    "host": "kafka-cluster-kafka-bootstrap.manageiq.svc",
	    "port": 9092,
	    "username": "manageiq-worker",
	    "password": "WorkerSecretPassword!",
	    "ssl": true,
	    "ca_file": "/opt/manageiq/certs/kafka-ca.crt",
	    "sasl_mechanism": "SCRAM-SHA-512"
	  },
	  "settings": {
	    "ems": {
	      "ems_vmware": {
	        "blacklisted_event_names": ["UserLoginSessionEvent", "EventEx"],
	        "minimum_supported_version": "7.0"
	      }
	    },
	    "worker_settings": {"heartbeat_timeout": 60}
	  },
	  "ems": [
	    {
	      "type": "` + vcenterType + `",
	      "id": 1000000000042,
	      "name": "Production vCenter 7",
	      "zone": "default",
	      "endpoints": [
	        {"role": "console", "hostname": "console.vcenter.prod.local", "port": 443, "verify_ssl": 1},
	        {"role": "default", "hostname": "vcenter.prod.local", "port": 8443, "verify_ssl": 1,
	         "certificate_authority": "` + strings.ReplaceAll(ca, "\n", `\n`) + `"}
	      ],
	      "authentications": [
	        {"authtype": "metrics", "userid": "metrics_collector", "password": "metricspassword"},
	        {"authtype": "default", "userid": "administrator@vsphere.local", "password": "VMwareAdminPassword123!"}
	      ]
	    },
	    {
	      "type": "` + networkType + `",
	      "id": 1000000000043,
	      "endpoints": [{"role": "default", "hostname": "nsx.prod.local", "port": 443, "verify_ssl": 0}],
	      "authentications": [{"authtype": "default", "userid": "admin", "password": "nsxpassword"}]
	    }
	  ]
	}`

	got, err := config.Parse(strings.NewReader(doc))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	want := &config.Config{
		Messaging: &config.Messaging{
			Protocol:      "Kafka",
			Host:          "kafka-cluster-kafka-bootstrap.manageiq.svc",
			Port:          9092,
			Username:      "manageiq-worker",
			Password:      "WorkerSecretPassword!",
			SSL:           true,
			CAFile:        "/opt/manageiq/certs/kafka-ca.crt",
			SASLMechanism: "SCRAM-SHA-512",
		},
		EMS: config.EMS{
			ID:                   json.RawMessage("1000000000042"),
			Host:                 "vcenter.prod.local",
			Port:                 8443,
			VerifySSL:            1,
			CertificateAuthority: ca,
			Username:             "administrator@vsphere.local",
			Password:             "VMwareAdminPassword123!",
		},
		Settings: config.Settings{
			HeartbeatTimeout:        60,
			BlacklistedEventNames:   []string{"UserLoginSessionEvent", "EventEx"},
			MinimumSupportedVersion: "7.0",
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("config mismatch\n got: %s\nwant: %s", mustJSON(t, got), mustJSON(t, want))
	}
}

func mustJSON(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal %T: %v", v, err)
	}
	return string(b)
}

func TestParse_Defaults(t *testing.T) {
	tests := []struct {
		name          string
		mutate        func(d map[string]any)
		wantPort      int
		wantHeartbeat int
	}{
		{
			name:          "explicit values are kept",
			mutate:        func(d map[string]any) {},
			wantPort:      443,
			wantHeartbeat: 90,
		},
		{
			name: "zero endpoint port defaults to 443",
			mutate: func(d map[string]any) {
				ep := endpoint("default", "vcenter.example.com")
				ep["port"] = 0
				firstEMS(d)["endpoints"] = []any{ep}
			},
			wantPort:      443,
			wantHeartbeat: 90,
		},
		{
			name: "missing endpoint port defaults to 443",
			mutate: func(d map[string]any) {
				ep := endpoint("default", "vcenter.example.com")
				delete(ep, "port")
				firstEMS(d)["endpoints"] = []any{ep}
			},
			wantPort:      443,
			wantHeartbeat: 90,
		},
		{
			name: "zero heartbeat defaults to 120",
			mutate: func(d map[string]any) {
				d["settings"].(map[string]any)["worker_settings"] = map[string]any{"heartbeat_timeout": 0}
			},
			wantPort:      443,
			wantHeartbeat: 120,
		},
		{
			name: "negative heartbeat defaults to 120",
			mutate: func(d map[string]any) {
				d["settings"].(map[string]any)["worker_settings"] = map[string]any{"heartbeat_timeout": -5}
			},
			wantPort:      443,
			wantHeartbeat: 120,
		},
		{
			name: "missing worker_settings defaults heartbeat to 120",
			mutate: func(d map[string]any) {
				delete(d["settings"].(map[string]any), "worker_settings")
			},
			wantPort:      443,
			wantHeartbeat: 120,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			d := validDoc()
			tt.mutate(d)
			cfg := mustParse(t, d)

			if cfg.EMS.Port != tt.wantPort {
				t.Errorf("ems port: got %d, want %d", cfg.EMS.Port, tt.wantPort)
			}
			if cfg.Settings.HeartbeatTimeout != tt.wantHeartbeat {
				t.Errorf("heartbeat timeout: got %d, want %d", cfg.Settings.HeartbeatTimeout, tt.wantHeartbeat)
			}
		})
	}
}

func TestParse_Selection(t *testing.T) {
	tests := []struct {
		name     string
		mutate   func(d map[string]any)
		wantID   string
		wantHost string
		wantUser string
	}{
		{
			name: "default endpoint wins over a console endpoint listed first",
			mutate: func(d map[string]any) {
				firstEMS(d)["endpoints"] = []any{
					endpoint("console", "console.example.com"),
					endpoint("default", "vcenter.example.com"),
				}
			},
			wantID: "42", wantHost: "vcenter.example.com", wantUser: "admin",
		},
		{
			name: "default authentication wins over another authtype listed first",
			mutate: func(d map[string]any) {
				firstEMS(d)["authentications"] = []any{auth("metrics", "metrics"), auth("default", "admin")}
			},
			wantID: "42", wantHost: "vcenter.example.com", wantUser: "admin",
		},
		{
			name: "InfraManager wins over a preceding NetworkManager",
			mutate: func(d map[string]any) {
				nsx := map[string]any{
					"type":            networkType,
					"id":              7,
					"endpoints":       []any{endpoint("default", "nsx.example.com")},
					"authentications": []any{auth("default", "nsx-admin")},
				}
				d["ems"] = append([]any{nsx}, d["ems"].([]any)...)
			},
			wantID: "42", wantHost: "vcenter.example.com", wantUser: "admin",
		},
		{
			name: "missing authentications leaves credentials empty",
			mutate: func(d map[string]any) {
				delete(firstEMS(d), "authentications")
			},
			wantID: "42", wantHost: "vcenter.example.com", wantUser: "",
		},
		{
			name: "no default authentication leaves credentials empty",
			mutate: func(d map[string]any) {
				firstEMS(d)["authentications"] = []any{auth("bearer", "token-user")}
			},
			wantID: "42", wantHost: "vcenter.example.com", wantUser: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			d := validDoc()
			tt.mutate(d)
			cfg := mustParse(t, d)

			if got := string(cfg.EMS.ID); got != tt.wantID {
				t.Errorf("ems id: got %q, want %q", got, tt.wantID)
			}
			if cfg.EMS.Host != tt.wantHost {
				t.Errorf("ems host: got %q, want %q", cfg.EMS.Host, tt.wantHost)
			}
			if cfg.EMS.Username != tt.wantUser {
				t.Errorf("ems username: got %q, want %q", cfg.EMS.Username, tt.wantUser)
			}
			if tt.wantUser == "" && cfg.EMS.Password != "" {
				t.Errorf("ems password: got %q, want empty when no credentials selected", cfg.EMS.Password)
			}
		})
	}
}

func TestParse_Errors(t *testing.T) {
	tests := []struct {
		name    string
		raw     string
		mutate  func(d map[string]any)
		wantErr string
	}{
		{
			name:    "malformed JSON",
			raw:     "not json",
			wantErr: errInvalid,
		},
		{
			name:    "null messaging",
			mutate:  func(d map[string]any) { d["messaging"] = nil },
			wantErr: errNoMessage,
		},
		{
			name:    "absent messaging",
			mutate:  func(d map[string]any) { delete(d, "messaging") },
			wantErr: errNoMessage,
		},
		{
			name:    "messaging has no host",
			mutate:  func(d map[string]any) { delete(d["messaging"].(map[string]any), "host") },
			wantErr: "messaging.host is missing",
		},
		{
			name:    "messaging has the wrong shape",
			mutate:  func(d map[string]any) { d["messaging"] = "not an object" },
			wantErr: errInvalid,
		},
		{
			name:    "no InfraManager entry",
			mutate:  func(d map[string]any) { firstEMS(d)["type"] = "ManageIQ::Providers::Something::Else" },
			wantErr: "no EMS entry of type " + vcenterType,
		},
		{
			name:    "empty ems array",
			mutate:  func(d map[string]any) { d["ems"] = []any{} },
			wantErr: "no EMS entry of type " + vcenterType,
		},
		{
			name:    "absent ems",
			mutate:  func(d map[string]any) { delete(d, "ems") },
			wantErr: "no EMS entry of type " + vcenterType,
		},
		{
			name: "no default endpoint",
			mutate: func(d map[string]any) {
				firstEMS(d)["endpoints"] = []any{endpoint("console", "console.example.com")}
			},
			wantErr: "no endpoint with role=default",
		},
		{
			name:    "no endpoints at all",
			mutate:  func(d map[string]any) { delete(firstEMS(d), "endpoints") },
			wantErr: "no endpoint with role=default",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var r io.Reader
			if tt.raw != "" {
				r = strings.NewReader(tt.raw)
			} else {
				d := validDoc()
				tt.mutate(d)
				r = toReader(t, d)
			}

			cfg, err := config.Parse(r)
			if err == nil {
				t.Fatalf("expected error containing %q, got nil (cfg=%+v)", tt.wantErr, cfg)
			}
			if !strings.Contains(err.Error(), tt.wantErr) {
				t.Errorf("error: got %q, want it to contain %q", err.Error(), tt.wantErr)
			}
			if cfg != nil {
				t.Errorf("expected nil config on error, got %+v", cfg)
			}
		})
	}
}

func TestParse_ReadError(t *testing.T) {
	sentinel := errors.New("boom")

	_, err := config.Parse(iotest.ErrReader(sentinel))
	if !errors.Is(err, sentinel) {
		t.Errorf("error: got %v, want it to wrap %v", err, sentinel)
	}
}

func TestParse_MessagingShapes(t *testing.T) {
	tests := []struct {
		name        string
		messaging   map[string]any
		want        config.Messaging
		wantUnknown []string
	}{
		{
			name: "from MESSAGING_* env vars",
			messaging: map[string]any{
				"host": "kafka.svc", "port": 9093, "username": "u", "password": "p",
				"protocol": "Kafka", "encoding": "json", "sasl_mechanism": "SCRAM-SHA-512",
				"ssl": true, "ca_file": "/ca.pem",
			},
			want: config.Messaging{
				Protocol: "Kafka", Host: "kafka.svc", Port: 9093, Username: "u", Password: "p",
				SASLMechanism: "SCRAM-SHA-512", SSL: true, CAFile: "/ca.pem",
			},
		},
		{
			name: "from messaging.yml with librdkafka sasl.* keys",
			messaging: map[string]any{
				"host": "kafka.example.com", "port": 9092, "protocol": "Kafka", "encoding": "json",
				"sasl.username": "user", "sasl.password": "password", "sasl.mechanism": "PLAIN",
			},
			want: config.Messaging{
				Protocol: "Kafka", Host: "kafka.example.com", Port: 9092,
				Username: "user", Password: "password", SASLMechanism: "PLAIN",
			},
		},
		{
			name: "librdkafka keys win over friendly keys",
			messaging: map[string]any{
				"host": "h", "username": "a", "sasl.username": "b", "ca_file": "/x", "ssl.ca.location": "/y",
			},
			want: config.Messaging{Host: "h", Username: "b", CAFile: "/y"},
		},
		{
			name:      "hosts list (multi-broker), not reported as unknown",
			messaging: map[string]any{"hosts": []string{"k1", "k2"}, "port": 9092},
			want:      config.Messaging{Hosts: []string{"k1", "k2"}, Port: 9092},
		},
		{
			name:      "hosts as a bare string, like Ruby's Array()",
			messaging: map[string]any{"hosts": "k1", "port": 9092},
			want:      config.Messaging{Hosts: []string{"k1"}, Port: 9092},
		},
		{
			name: "unsupported keys are reported by name, sorted",
			messaging: map[string]any{
				"host": "h", "ssl.keystore.location": "/k", "message.timeout.ms": 5000, "keystore_password": "secret",
			},
			want:        config.Messaging{Host: "h"},
			wantUnknown: []string{"keystore_password", "message.timeout.ms", "ssl.keystore.location"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			d := validDoc()
			d["messaging"] = tt.messaging
			cfg, err := config.Parse(toReader(t, d))
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			want := tt.want
			want.Unknown = tt.wantUnknown
			if !reflect.DeepEqual(*cfg.Messaging, want) {
				t.Errorf("messaging mismatch\n got: %+v\nwant: %+v", *cfg.Messaging, want)
			}
		})
	}
}

// Core's normalize_settings! turns numeric-looking strings ("7.0") into numbers before sending
// them on stdin, so minimum_supported_version arrives as a JSON number.
func TestParse_MinimumSupportedVersionAsNumber(t *testing.T) {
	doc := `{
	  "messaging": {"protocol": "Kafka", "host": "localhost", "port": 9092},
	  "settings": {"ems": {"ems_vmware": {"minimum_supported_version": 7}}},
	  "ems": [{
	    "type": "` + vcenterType + `",
	    "id": 1,
	    "endpoints": [{"role": "default", "hostname": "vcenter.example.com", "port": 443}],
	    "authentications": [{"authtype": "default", "userid": "u", "password": "p"}]
	  }]
	}`

	got, err := config.Parse(strings.NewReader(doc))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.Settings.MinimumSupportedVersion != "7" {
		t.Errorf("MinimumSupportedVersion = %q, want %q", got.Settings.MinimumSupportedVersion, "7")
	}
}
