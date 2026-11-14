// Package config parses the JSON document written to stdin by ManageIQ core before exec'ing
// the worker. See README.md for the shape of the document.
package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"sort"
)

// Config is the parsed, validated configuration for the event catcher.
type Config struct {
	Messaging *Messaging
	EMS       EMS
	Settings  Settings
}

// Messaging holds the Kafka broker connection details parsed from the "messaging" key.
type Messaging struct {
	Protocol string
	Host     string
	// Hosts is the optional "hosts" list. When non-empty it takes precedence over Host, as in
	// manageiq-messaging. All entries share Port.
	Hosts    []string
	Port     int
	Username string
	Password string

	SSL           bool
	CAFile        string
	SASLMechanism string

	// Unknown lists the unsupported keys that were present (sorted, names only). The Ruby gem
	// passed these straight to librdkafka; this worker cannot honor them.
	Unknown []string
}

// messagingKeys are the keys that are read, plus "encoding", which is deliberately ignored
// because the worker always publishes JSON.
var messagingKeys = map[string]bool{
	"protocol": true, "host": true, "hosts": true, "port": true, "username": true, "password": true,
	"ssl": true, "ca_file": true, "sasl_mechanism": true, "encoding": true,
	"sasl.username": true, "sasl.password": true, "sasl.mechanism": true, "ssl.ca.location": true,
}

// UnmarshalJSON reads the messaging hash, preferring the librdkafka-style keys over the
// friendly ones when both are present, and records unsupported keys in Unknown.
func (m *Messaging) UnmarshalJSON(data []byte) error {
	var kv map[string]json.RawMessage
	if err := json.Unmarshal(data, &kv); err != nil {
		return err
	}

	*m = Messaging{}
	for _, f := range []struct {
		dst  any
		keys []string // later keys win
	}{
		{&m.Protocol, []string{"protocol"}},
		{&m.Host, []string{"host"}},
		{&m.Port, []string{"port"}},
		{&m.Username, []string{"username", "sasl.username"}},
		{&m.Password, []string{"password", "sasl.password"}},
		{&m.SSL, []string{"ssl"}},
		{&m.CAFile, []string{"ca_file", "ssl.ca.location"}},
		{&m.SASLMechanism, []string{"sasl_mechanism", "sasl.mechanism"}},
	} {
		for _, k := range f.keys {
			v, ok := kv[k]
			if !ok || string(v) == "null" {
				continue
			}
			if err := json.Unmarshal(v, f.dst); err != nil {
				return fmt.Errorf("messaging.%s: %w", k, err)
			}
		}
	}

	// The gem does Array(options[:hosts]), so a bare string is accepted as a one-element list.
	if v, ok := kv["hosts"]; ok && string(v) != "null" {
		if err := json.Unmarshal(v, &m.Hosts); err != nil {
			var one string
			if json.Unmarshal(v, &one) != nil {
				return fmt.Errorf("messaging.hosts: %w", err)
			}
			m.Hosts = []string{one}
		}
	}

	for k := range kv {
		if !messagingKeys[k] {
			m.Unknown = append(m.Unknown, k)
		}
	}
	sort.Strings(m.Unknown)
	return nil
}

// EMS is the selected provider entry, with the default endpoint and authentication resolved.
type EMS struct {
	ID   json.RawMessage // left raw so it can be forwarded verbatim to parser.Event.EmsID
	Host string
	Port int

	VerifySSL            int
	CertificateAuthority string
	Username             string
	Password             string
}

// Settings holds the values read from the "settings" block.
type Settings struct {
	HeartbeatTimeout        int // seconds
	BlacklistedEventNames   []string
	MinimumSupportedVersion string
}

const defaultHeartbeatTimeout = 120

type raw struct {
	Messaging json.RawMessage `json:"messaging"`
	Settings  rawSettings     `json:"settings"`
	EMS       []rawEMS        `json:"ems"`
}

type rawSettings struct {
	EMS            rawEMSSettings    `json:"ems"`
	WorkerSettings rawWorkerSettings `json:"worker_settings"`
}

type rawEMSSettings struct {
	EMSVmware rawEMSVmwareSettings `json:"ems_vmware"`
}

type rawEMSVmwareSettings struct {
	BlacklistedEventNames   []string   `json:"blacklisted_event_names"`
	MinimumSupportedVersion flexString `json:"minimum_supported_version"`
}

// flexString accepts a JSON string or number. Core's normalize_settings! converts numeric-looking
// strings such as "7.0" into integers before sending them on stdin.
type flexString string

func (f *flexString) UnmarshalJSON(data []byte) error {
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		*f = flexString(s)
		return nil
	}
	var n json.Number
	if err := json.Unmarshal(data, &n); err != nil {
		return err
	}
	*f = flexString(n.String())
	return nil
}

type rawWorkerSettings struct {
	HeartbeatTimeout int `json:"heartbeat_timeout"`
}

type rawEMS struct {
	Type            string              `json:"type"`
	ID              json.RawMessage     `json:"id"`
	Endpoints       []rawEndpoint       `json:"endpoints"`
	Authentications []rawAuthentication `json:"authentications"`
}

type rawEndpoint struct {
	Role                 string `json:"role"`
	Host                 string `json:"hostname"`
	Port                 int    `json:"port"`
	VerifySSL            int    `json:"verify_ssl"`
	CertificateAuthority string `json:"certificate_authority"`
}

type rawAuthentication struct {
	AuthType string `json:"authtype"`
	Username string `json:"userid"`
	Password string `json:"password"`
}

// Parse reads and validates the JSON configuration document from r (normally os.Stdin).
func Parse(r io.Reader) (*Config, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, fmt.Errorf("reading stdin: %w", err)
	}

	var doc raw
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("Invalid argument format")
	}

	cfg := &Config{}

	if string(doc.Messaging) == "null" || len(doc.Messaging) == 0 {
		return nil, errors.New("messaging configuration is missing (null); " +
			"ensure MESSAGING_* environment variables or config/messaging.yml are configured")
	}
	var msg Messaging
	if err := json.Unmarshal(doc.Messaging, &msg); err != nil {
		return nil, fmt.Errorf("Invalid argument format")
	}
	if msg.Host == "" && len(msg.Hosts) == 0 {
		return nil, errors.New("messaging.host is missing")
	}
	cfg.Messaging = &msg

	ems, err := selectEMS(doc.EMS)
	if err != nil {
		return nil, err
	}
	cfg.EMS = *ems

	cfg.Settings = parseSettings(doc.Settings)

	return cfg, nil
}

const (
	vmwareEMSType = "ManageIQ::Providers::Vmware::InfraManager"

	// defaultRole is the primary vCenter API role; ignore the "console" (VMRC) role also present.
	defaultRole = "default"

	defaultPort = 443
)

func selectEMS(entries []rawEMS) (*EMS, error) {
	for _, entry := range entries {
		if entry.Type == vmwareEMSType {
			return newEMS(entry)
		}
	}
	return nil, fmt.Errorf("no EMS entry of type %s found in stdin document", vmwareEMSType)
}

func newEMS(entry rawEMS) (*EMS, error) {
	ep, ok := findEndpoint(entry.Endpoints, defaultRole)
	if !ok {
		return nil, fmt.Errorf("no endpoint with role=%s found for %s", defaultRole, vmwareEMSType)
	}

	out := &EMS{
		ID:                   entry.ID,
		Host:                 ep.Host,
		Port:                 ep.Port,
		VerifySSL:            ep.VerifySSL,
		CertificateAuthority: ep.CertificateAuthority,
	}
	if out.Port == 0 {
		out.Port = defaultPort
	}

	// Credentials are optional here: a missing default authentication is not a config error,
	// it surfaces as a login failure when the worker connects.
	if auth, ok := findAuthentication(entry.Authentications, defaultRole); ok {
		out.Username = auth.Username
		out.Password = auth.Password
	}

	return out, nil
}

func findEndpoint(endpoints []rawEndpoint, role string) (rawEndpoint, bool) {
	for _, ep := range endpoints {
		if ep.Role == role {
			return ep, true
		}
	}
	return rawEndpoint{}, false
}

func findAuthentication(auths []rawAuthentication, authType string) (rawAuthentication, bool) {
	for _, auth := range auths {
		if auth.AuthType == authType {
			return auth, true
		}
	}
	return rawAuthentication{}, false
}

func parseSettings(s rawSettings) Settings {
	hb := s.WorkerSettings.HeartbeatTimeout
	if hb <= 0 {
		hb = defaultHeartbeatTimeout
	}
	return Settings{
		HeartbeatTimeout:        hb,
		BlacklistedEventNames:   s.EMS.EMSVmware.BlacklistedEventNames,
		MinimumSupportedVersion: string(s.EMS.EMSVmware.MinimumSupportedVersion),
	}
}
