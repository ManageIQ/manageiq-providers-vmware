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

## ADR-004: The binary is built at packaging time, not committed

**Context.** The gem ships `git ls-files`, so an uncommitted binary is not in the gem. The RPM
build (`manageiq-rpm_build`) assembles the gemset from `bundle install`, and its build image has no
Go toolchain. The pods images contain no worker code; they install the RPMs. Appliance and pods
repos have no event-catcher references.

**Decision.** The binary is built into the plugin directory during gemset creation; containers and appliances then get it from the RPM. The binary is not committed. Developers run `make install`.

**Consequences.** Needs a `golang` build dependency in the build environment and a build step per
architecture (x86_64, aarch64, ppc64le, s390x).

