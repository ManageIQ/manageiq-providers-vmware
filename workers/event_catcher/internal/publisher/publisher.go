// Package publisher publishes parsed ManageIQ events to a Kafka topic using franz-go.
//
// Wire format (from manageiq-messaging 2.2.0):
//   - topic:    manageiq.ems
//   - key:      none
//   - headers:  sender=<ems_id>, event_type=<event_type>, encoding=json
//   - body:     JSON-encoded parser.Event
//   - client.id: vmware-event-catcher-<ems_id>
//
// Auth: SASL PLAIN (default), SCRAM-SHA-256, SCRAM-SHA-512.
// TLS: only when Config.SSL is true; otherwise plaintext (SASL credentials are not sent).
// Idempotent writes are disabled (franz-go enables them by default; the broker may lack the ACL).
// Each Publish call is synchronous and times out after deliveryTimeout.
//
// See README.md "Kafka Wire Format".
package publisher

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/twmb/franz-go/pkg/kgo"
	"github.com/twmb/franz-go/pkg/sasl"
	"github.com/twmb/franz-go/pkg/sasl/plain"
	"github.com/twmb/franz-go/pkg/sasl/scram"

	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/parser"
)

const topic = "manageiq.ems"

// deliveryTimeout matches the 60s default wait on an rdkafka delivery handle.
var deliveryTimeout = 60 * time.Second

// Publisher is the interface the event loop calls.
type Publisher interface {
	Publish(ctx context.Context, e *parser.Event) error
	Close()
}

// Config holds the Kafka connection details sourced from config.Messaging.
type Config struct {
	Host          string
	Hosts         []string
	Port          int
	Username      string
	Password      string
	SSL           bool
	CAFile        string
	SASLMechanism string
	EmsID         []byte
}

// KafkaPublisher is the live Kafka publisher.
type KafkaPublisher struct {
	client *kgo.Client
	emsID  string
	log    *slog.Logger
}

func seedBrokers(cfg Config) []string {
	hosts := cfg.Hosts
	if len(hosts) == 0 {
		hosts = []string{cfg.Host}
	}
	seeds := make([]string, len(hosts))
	for i, h := range hosts {
		seeds[i] = fmt.Sprintf("%s:%d", h, cfg.Port)
	}
	return seeds
}

// New creates a KafkaPublisher and opens the connection to the broker.
func New(cfg Config, log *slog.Logger) (*KafkaPublisher, error) {
	emsID := emsIDString(cfg.EmsID)

	opts := []kgo.Opt{
		kgo.SeedBrokers(seedBrokers(cfg)...),
		kgo.ClientID(fmt.Sprintf("vmware-event-catcher-%s", emsID)),
		kgo.DefaultProduceTopic(topic),
		kgo.DisableIdempotentWrite(),
		kgo.RecordDeliveryTimeout(deliveryTimeout),
	}

	if cfg.SSL {
		tlsCfg, err := buildTLS(cfg.CAFile)
		if err != nil {
			return nil, fmt.Errorf("publisher TLS config: %w", err)
		}
		opts = append(opts, kgo.DialTLSConfig(tlsCfg))

		saslMech, err := buildSASL(cfg.SASLMechanism, cfg.Username, cfg.Password)
		if err != nil {
			return nil, err
		}
		opts = append(opts, kgo.SASL(saslMech))
	}

	client, err := kgo.NewClient(opts...)
	if err != nil {
		return nil, fmt.Errorf("kafka NewClient: %w", err)
	}

	return &KafkaPublisher{client: client, emsID: emsID, log: log}, nil
}

// Publish JSON-encodes e and produces a single record to the manageiq.ems topic.
func (p *KafkaPublisher) Publish(ctx context.Context, e *parser.Event) error {
	body, err := json.Marshal(e)
	if err != nil {
		return fmt.Errorf("marshal event: %w", err)
	}

	rec := &kgo.Record{
		Topic: topic,
		Value: body,
		Headers: []kgo.RecordHeader{
			{Key: "sender", Value: []byte(p.emsID)},
			{Key: "event_type", Value: []byte(e.EventType)},
			{Key: "encoding", Value: []byte("json")},
		},
	}

	results := p.client.ProduceSync(ctx, rec)
	if err := results.FirstErr(); err != nil {
		return fmt.Errorf("kafka produce: %w", err)
	}

	p.log.Debug("published event", "event_type", e.EventType, "topic", topic)
	return nil
}

func (p *KafkaPublisher) Close() {
	p.client.Close()
}

// buildTLS builds the TLS config; caFile is a PEM CA file path, empty means system roots.
func buildTLS(caFile string) (*tls.Config, error) {
	tlsCfg := &tls.Config{MinVersion: tls.VersionTLS12}
	if caFile == "" {
		return tlsCfg, nil
	}
	pem, err := os.ReadFile(caFile)
	if err != nil {
		return nil, fmt.Errorf("read ca_file %q: %w", caFile, err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(pem) {
		return nil, fmt.Errorf("ca_file %q: no valid PEM certificates found", caFile)
	}
	tlsCfg.RootCAs = pool
	return tlsCfg, nil
}

// buildSASL returns the SASL mechanism; defaults to "PLAIN", supports SCRAM-SHA-256/512.
func buildSASL(mechanism, username, password string) (sasl.Mechanism, error) {
	if mechanism == "" {
		mechanism = "PLAIN"
	}
	switch strings.ToUpper(mechanism) {
	case "PLAIN":
		return plain.Auth{
			User: username,
			Pass: password,
		}.AsMechanism(), nil
	case "SCRAM-SHA-256":
		return scram.Auth{
			User: username,
			Pass: password,
		}.AsSha256Mechanism(), nil
	case "SCRAM-SHA-512":
		return scram.Auth{
			User: username,
			Pass: password,
		}.AsSha512Mechanism(), nil
	default:
		return nil, fmt.Errorf("unsupported sasl_mechanism %q: supported values are PLAIN, SCRAM-SHA-256, SCRAM-SHA-512", mechanism)
	}
}

// emsIDString converts a raw JSON EMS id (e.g. json.RawMessage("42")) to a plain string.
// Quoted strings are unquoted; bare numbers are returned as-is.
func emsIDString(raw []byte) string {
	s := string(raw)
	if unquoted, err := strconv.Unquote(s); err == nil {
		return unquoted
	}
	return s
}
