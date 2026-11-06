# ManageIQ VMware Event Catcher

Go implementation of the VMware vSphere / vCenter infrastructure manager event catcher worker for ManageIQ.

The event catcher connects to VMware vCenter via the vSphere Web Services SDK (SOAP API), listens for event updates using property collectors, normalizes event structures, filters blacklisted events, and publishes events to Kafka for consumption by ManageIQ Core (`MiqEventHandler`).

## Worker Contract & Behavior

| Concern | Behavior |
|---|---|
| **Launch** | Core's `MiqWorker::Runner#start_non_rails_worker` writes a JSON configuration document to an unlinked temp file, reopens `$stdin` on it, and **execs** `<plugin root>/workers/event_catcher/worker`. No command-line arguments. Because it is an exec, the process PID is preserved. |
| **stdin** | `{"messaging": {...} or null, "settings": {...}, "ems": [{... "endpoints": [...], "authentications": [...]}]}`. The `ems` array holds the manager and its child managers. The worker selects the `ManageIQ::Providers::Vmware::InfraManager`, its `default` endpoint, and its `default` authentication credentials. |
| **Environment** | `GUID`, `WORKER_HEARTBEAT_FILE`, `APP_ROOT`, `EMS_ID`, `NOTIFY_SOCKET` (systemd), `WORKER_HEARTBEAT_METHOD` (containers), `CONTAINER` / `APPLIANCE` (logger format). |
| **vCenter Connection** | Connects to `/sdk` (default port 443). TLS certificate verification is skipped if `endpoint.verify_ssl == 0`; otherwise, the CA certificate in `endpoint.certificate_authority` is trusted. Authenticates via `SessionManager.Login`. |
| **Event Subscription** | Creates an `EventManager.CreateCollectorForEvents` with page size 20, attaches a `PropertyFilter` on `latestPage` requesting partial updates, and polls `WaitForUpdatesEx(version, maxWaitSeconds=60)` in a loop. |
| **Event Parsing** | Translates `govmomi`'s typed `types.BaseEvent` structures into ManageIQ normalized event payloads (see [Event Parsing & Payload](#event-parsing--payload)). |
| **Filtering** | Filters out events whose resolved `event_type` matches entries in `settings.ems.ems_vmware.blacklisted_event_names`. |
| **Kafka Publishing** | Publishes each event synchronously to the `manageiq.ems` Kafka topic (see [Kafka Wire Format](#kafka-wire-format)). |
| **Liveness & Heartbeats** | Systemd: sends `sd_notify` `READY`, `WATCHDOG`, and `STOPPING`. File heartbeat: writes `now + heartbeat_timeout` (default 120s) to `$WORKER_HEARTBEAT_FILE`. A heartbeat is emitted on every return of `WaitForUpdatesEx` (including timeouts). |
| **Shutdown** | On `SIGINT` or `SIGTERM`, cleanly destroys property filter and collector, terminates vCenter session, sends `STOPPING`, and exits. |
| **Failure Handling** | No internal reconnect loop. Any fatal error exits non-zero and core supervisor / systemd / Kubernetes restarts the worker. |

## Architecture

```
stdin JSON --> config --> vSphere session (govmomi) --> event collector + property filter
                                                             |
                                         WaitForUpdatesEx loop (heartbeat every return)
                                                             |
                                            govmomi types.BaseEvent structs
                                                             |
                                            parser.Parse --> blacklist filter
                                                             |
                                    Kafka publish (franz-go), topic manageiq.ems
```

### Package Layout

| Path | Description |
|---|---|
| `cmd/event_catcher` | Application entrypoint (`main`): stdin parsing, lifecycle wiring, signal handling. |
| `internal/config` | Stdin configuration deserialization, defaults, and credential lookup. |
| `internal/heartbeat` | Liveness tracking (`sd_notify` watchdog and heartbeat file management). |
| `internal/logging` | Structured logging using `log/slog` (JSON formatting for containers, text for appliances). |
| `internal/parser` | Event conversion from `types.BaseEvent` into ManageIQ normalized event shape. |
| `internal/publisher` | Kafka message publisher using `franz-go`. |
| `internal/vim` | VMware vSphere API client session, event collector, property filter, and polling loop. |

## Event Parsing & Payload

The event parser translates vCenter events from `govmomi`'s strongly typed `types.BaseEvent` into the published ManageIQ event payload.

1. **Top-Level Attributes:**
   Extracted directly from the event: `event_type`, `chain_id`, `is_task`, `source`, `message`, `timestamp`, `username`, `vm_ems_ref`, `vm_name`, `dest_vm_name`, `host_name`, `host_ems_ref`, `dest_host_ems_ref`, `dest_host_name`, and `ems_id`.
2. **`full_data` Payload:**
   `full_data` contains the raw event object (`types.BaseEvent`) marshaled directly to JSON. `full_data` is provider-internal/opaque to ManageIQ Core (stored for timelines and historical audit), while Core's relational links and alert policies evaluate the normalized top-level attributes.

## Kafka Wire Format

Publishing conforms to `manageiq-messaging` wire specifications:

* **Topic:** `manageiq.ems` (no partition key)
* **Headers:**
  * `sender`: EMS ID
  * `event_type`: Normalized event type string
  * `encoding`: `json`
* **Body:** JSON stringified event payload
* **Producer Configuration:**
  * `bootstrap.servers`: `host:port`
  * `client.id`: `vmware-event-catcher-<ems_id>`
  * `sasl.mechanism`: `PLAIN`, `SCRAM-SHA-256`, or `SCRAM-SHA-512`
  * `security.protocol`: `SASL_SSL` or `PLAINTEXT` (SSL certificate verification via CA bundle when configured)
  * Synchronous delivery per event, 60s delivery timeout
  * The `manageiq.ems` topic is not auto-created and must exist

## Building & Testing

Requires **Go 1.25** or newer. Pure Go with `CGO_ENABLED=0` (no C toolchain or librdkafka required).

```sh
# Run code formatting checks, go vet, and all tests
make check

# Run tests with race detection / vcsim integration tests
make test

# Build binary as worker executable (used by ManageIQ core runner)
make build
```
