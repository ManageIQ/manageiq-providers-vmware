# Architecture Decisions

Format: context, decision, consequences. Status is `accepted` unless stated.

## ADR-001: Replace the Ruby non-Rails worker with a Go binary at the same path

**Context.** Core launches non-Rails workers by exec'ing `<plugin root>/workers/<type>/worker`
with a JSON document on stdin (`MiqWorker::Runner#start_non_rails_worker`). Systemd units,
Kubernetes pods and the process monitor all rely on the exec preserving the PID.

**Decision.** The Go binary is installed as `workers/event_catcher/worker` and honors the same
contract: no arguments, JSON on stdin, same environment variables, same heartbeat mechanisms.

**Consequences.** No change to `manageiq` core, the systemd units or the pods repo. The rewrite is
invisible to core. The cost is that the binary has to be built at packaging time (ADR-004).

## ADR-002: Parse directly from govmomi's `types.BaseEvent` structs

**Context.** Downstream consumers in ManageIQ Core (`MiqEventHandler`, `EmsEvent.add`) extract and evaluate the normalized top-level event fields (`event_type`, `vm_ems_ref`, `host_ems_ref`, `message`, `timestamp`, `ems_id`). The nested `full_data` payload is internal/opaque to the provider and stored for historical audit and timelines.

**Decision.** Use `govmomi`'s native typed structs (`types.BaseEvent`) directly for event unmarshaling and parsing. `internal/parser` resolves top-level entity references and event types directly from `types.BaseEvent`, and sets `FullData = base`.

**Consequences.** No need for raw SOAP XML interception or custom XML AST decoding. Event parsing is type-safe and clean.

## ADR-003: Kafka via franz-go; pure Go, `CGO_ENABLED=0`

**Context.** Messaging is `manageiq-messaging`, which uses `rdkafka` (librdkafka). Only Kafka is
supported going forward (core's artemis support remains for Rails workers but is out of scope
here). Options considered:

| | franz-go | confluent-kafka-go | segmentio/kafka-go |
|---|---|---|---|
| Implementation | pure Go | cgo + librdkafka | pure Go |
| Arbitrary librdkafka config passthrough | no | yes | no |
| Static binary, trivial cross-compile (incl. s390x, ppc64le) | yes | no | yes |
| New runtime / build dependency | none | gcc, librdkafka headers or `-tags dynamic` | none |

**Decision.** franz-go, with a fixed set of options: `host`, `port`, `username`, `password`,
`sasl_mechanism` (`PLAIN`, `SCRAM-SHA-256`, `SCRAM-SHA-512`), `ssl`, `ca_file`, `client_ref`.
Idempotent writes are disabled (franz-go enables them by default; rdkafka does not, and idempotence
needs an extra cluster ACL on locked-down brokers). Producing is synchronous per message.

**Consequences.** Any extra librdkafka keys someone has put in `messaging.yml` are not honored.
The worker logs one warning listing the ignored key names (never values) and carries on. This
includes `keystore_location`/`keystore_password` (mutual TLS), which the Ruby gem supported and
this worker does not; nothing in core, pods or appliance sets them.

The `messaging` keys are those core produces (`MiqQueue.messaging_client_options`): `host` (not
`hostname`), `port`, `protocol` (`"Kafka"`, compared case-insensitively), `username`, `password`,
`ssl`, `ca_file`, `sasl_mechanism`, and `encoding` (ignored; always JSON). The librdkafka
spellings `sasl.username`, `sasl.password`, `sasl.mechanism` and `ssl.ca.location` are accepted
and win over the friendly keys, as in `manageiq-messaging`. The gem's `hosts` list is supported
too (all entries share `port`, and it takes precedence over `host`), although core itself only
ever sets `host`.

Any protocol other than Kafka makes the worker exit with a clear error.

### Parity with the Ruby / librdkafka path

What the Go worker does not do that `manageiq-messaging` 2.2.0 (rdkafka) could do. "Inherited"
means the Ruby path behaved the same for everything core produces. "Unrecorded" means the
rationale was not written down when the decision was made; the reason given is inferred.

| Capability | Ruby / librdkafka | Go worker | Kind | Reason |
|---|---|---|---|---|
| Arbitrary librdkafka keys from `messaging.yml` | merged into the config verbatim (`result.merge(options.except(...))`) | ignored, one warning listing key names | Intentional | franz-go has no string-keyed config passthrough; the options are typed |
| Mutual TLS (`keystore_location`, `keystore_password`) | supported | ignored | Intentional | Nothing in core, pods or the appliance sets them |
| SASL mechanisms other than `PLAIN`, `SCRAM-SHA-256`, `SCRAM-SHA-512` (`GSSAPI`, `OAUTHBEARER`) | `sasl.mechanism` was passed through unvalidated | exits at startup with a clear error | Unrecorded | Core only produces `username`/`password`. Kerberos and OAuth also need further keys (`sasl.kerberos.*`, token config) that only the passthrough could supply. This is not a franz-go limit: `sasl/kerberos` and `sasl/oauth` exist, and kerberos adds a dependency |
| `SASL_PLAINTEXT` and TLS-without-SASL | only by setting a raw `security.protocol` key, which overrides the gem's choice | not available; `security.protocol` is ignored | Inherited | The gem derives the protocol from one flag: `ssl` true gives `SASL_SSL`, otherwise `PLAINTEXT`. Core's env and file paths never set `security.protocol`. The Go worker matches the derived behavior, including that credentials are not sent when `ssl` is false |
| Producer tuning (acks, retries, `message.timeout.ms`, compression, linger, batching, socket and timeout settings) | settable via passthrough | franz-go defaults, not configurable | Intentional | Same cause as the first row. The defaults differ from librdkafka's |
| Idempotent writes | off (librdkafka default) | off (`DisableIdempotentWrite`) | Parity | Deliberately matched; see the Decision above |
| Delivery model | `publish_topic` waits on each delivery handle, 60s default | `ProduceSync` per event, `RecordDeliveryTimeout` 60s | Parity | Both are synchronous per event. franz-go has no delivery timeout by default, and a dead broker blocked `Publish` until core killed the worker on heartbeat, so the timeout is set explicitly |
| Topic auto-creation | creates a missing topic if the broker allows it (tested against Kafka 4.3.1) | fails with `UNKNOWN_TOPIC_OR_PARTITION`; `manageiq.ems` must exist | Intentional | The appliance (`manageiq-messaging-ready`) and the pods operator (`KafkaTopic`) create it up front. Auto-creation would hide a wrong topic name and give the topic default partition and replication settings. Dev setups need the topic created by hand |
| TLS implementation | OpenSSL: cipher strings, CRL/OCSP, PKCS#12 keystores, FIPS provider | Go `crypto/tls`, TLS 1.2 minimum, PEM CA file only | Consequence of pure Go | `CGO_ENABLED=0` rules out OpenSSL. Anyone needing OpenSSL or FIPS behavior should verify this worker first |
| Certificates without a SAN | OpenSSL falls back to the Common Name | Go `crypto/tls` rejects them: `certificate relies on legacy Common Name field, use SANs instead` | Consequence of pure Go | Appliances configured by `manageiq-appliance_console` before the SAN fix (`-ext` on `keytool -certreq`, `-copy_extensions copy` on `openssl x509 -req`) have a broker certificate with CN only. Regenerate that certificate, or the worker cannot connect. Pods use Strimzi certificates, which have SANs (not verified) |
| Client diagnostics (`debug=` contexts, statistics callback) | available | not exposed | Unrecorded | franz-go has loggers and hooks, but the worker does not wire them to config |
| `encoding` | `yaml` by default, `json` when set | always JSON, key ignored | Inherited | Core always sets `json` |
| Non-Kafka protocols | n/a (the gem is Kafka only; artemis lives elsewhere in core) | exits with an error | Intentional | Out of scope; see Context |

#### What was verified, and where

Checked by reading the sibling repos (`manageiq`, `manageiq-pods`, `manageiq-appliance`,
`manageiq-rpm_build`, `manageiq-appliance_console`) and by running the clients:

- Nothing sets `keystore_*` or `security.protocol`. The pods configure TLS on 9093 with
  SCRAM-SHA-512 and `MESSAGING_SSL_CA`.
- The appliance console writes `messaging.yml` from `config/messaging.kafka.yml` and sets only
  `host`, `port`, `username`, `password`, `ssl` and `ca_file`. Port 9093 means `ssl: true` and the
  broker listens `SASL_SSL` with `PLAIN`; any other port means `ssl: false`.
- Both topic creators (`manageiq-messaging-ready`, the pods operator) create `manageiq.ems`.
- A dead broker blocked `Publish` until the context ended (tested with a silent TCP listener); a
  missing topic was auto-created by rdkafka but not by franz-go (tested on Kafka 4.3.1).
- The console signed broker certificates without a SAN. Go rejected one in a local test; this is
  fixed in `manageiq-appliance_console` but not yet released.

#### Open items

Not checkable from a developer machine. Each needs an owner or a real environment.

| Item | Why it matters | How to check |
|---|---|---|
| Console SAN fix released and appliances regenerated | Existing appliances have CN-only broker certificates, and the worker cannot connect to them | Ship the console change. On an appliance: `openssl x509 -in /etc/kafka/config/keystore/cert-signed -noout -ext subjectAltName` |
| `openssl x509 -copy_extensions` on appliance OpenSSL | The flag needs OpenSSL 3.0+; an older one rejects it | `openssl version` on an appliance |
| Strimzi certificate SANs in pods | The pods trust path is assumed to be fine | `openssl s_client -connect <app>-kafka-bootstrap:9093 </dev/null \| openssl x509 -noout -ext subjectAltName` |
| SCRAM-SHA-512 over TLS end to end | Only the unit-level SASL builder and a plaintext broker were tested | Add a `SASL_SSL` listener and a SCRAM user to a local broker and run the worker against it |
| librdkafka version actually shipped | The RPM requires a system `librdkafka`, but the gem loads its own bundled copy; the shipped lockfile can differ | `bundle exec ruby -e 'require "rdkafka"; puts Rdkafka::LIBRDKAFKA_VERSION'` in a built environment |
| FIPS | Go `crypto/tls` is not the OpenSSL FIPS provider | Ask the compliance owner whether the Kafka client must be FIPS-validated |
| Kill during publish | An in-flight event could be lost or duplicated | SIGKILL the worker while it publishes and count events on the topic. Both workers start a fresh vCenter collector, so downtime events are not replayed in either |
| Hand-edited `messaging.yml` on live appliances | Extra keys are ignored with a warning | Look for "ignoring unsupported messaging settings" in a running worker's log |
| Console "unsecure" mode (port other than 9093) | The console writes `ssl: false` plus a username and password. The gem and the Go worker both send no credentials in that case, so a broker expecting SASL on that port would reject both | Check whether anyone runs the appliance Kafka on a non-9093 port. If so, decide whether to support `SASL_PLAINTEXT` |
| `golang` in the RPM build image | ADR-004 says the image has no Go toolchain; `manageiq-rpm_build` has uncommitted edits adding it | Land those edits, then update ADR-004 |

Reading the table: SASL mechanism support is a gap that was never decided, so it is cheap to
revisit if a deployment needs Kerberos or OAuth. The SASL/TLS coupling is not a gap: it mirrors
the gem. It only differs for a user who set a raw `security.protocol` key in `messaging.yml`,
which the worker now reports in the ignored-keys warning.

## ADR-004: The binary is built at packaging time, not committed

**Context.** The gem ships `git ls-files`, so an uncommitted binary is not in the gem. The RPM
build (`manageiq-rpm_build`) assembles the gemset from `bundle install`, and its build image has no
Go toolchain. The pods images contain no worker code; they install the RPMs. Appliance and pods
repos have no event-catcher references.

**Decision.** The binary is built into the plugin directory during gemset creation; containers and appliances then get it from the RPM. The binary is not committed. Developers run `make build`.

**Consequences.** Needs a `golang` build dependency in the build environment and a build step per
architecture (x86_64, aarch64, ppc64le, s390x).

