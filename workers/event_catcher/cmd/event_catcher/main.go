// Command event_catcher is the Go implementation of the VMware infra manager event catcher.
//
// ManageIQ core execs this binary (workers/event_catcher/worker) with a JSON document on stdin; see
// README.md.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/config"
	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/heartbeat"
	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/logging"
	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/parser"
	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/publisher"
	"github.com/ManageIQ/manageiq-providers-vmware/workers/event_catcher/internal/vim"
)

func main() {
	os.Exit(run())
}

func run() int {
	setproctitle()

	cfg, err := config.Parse(os.Stdin)
	if err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		return 1
	}

	log := logging.New()
	slog.SetDefault(log)

	log.Info(logging.Msg("starting"),
		"ems_host", cfg.EMS.Host,
		"ems_port", cfg.EMS.Port,
	)

	log.Info(logging.Msg("filtered events"),
		"count", len(cfg.Settings.BlacklistedEventNames),
		"names", strings.Join(cfg.Settings.BlacklistedEventNames, ","),
	)

	// Core sends "Kafka" (see MiqQueue.messaging_client_options).
	if !strings.EqualFold(cfg.Messaging.Protocol, "kafka") {
		fmt.Fprintf(os.Stderr, "unsupported messaging protocol %q: only \"Kafka\" is supported\n", cfg.Messaging.Protocol)
		return 1
	}
	if len(cfg.Messaging.Unknown) > 0 {
		// Names only: values may be secrets.
		log.Warn(logging.Msg("ignoring unsupported messaging settings"),
			"keys", strings.Join(cfg.Messaging.Unknown, ","))
	}

	pub, err := publisher.New(publisher.Config{
		Host:          cfg.Messaging.Host,
		Hosts:         cfg.Messaging.Hosts,
		Port:          cfg.Messaging.Port,
		Username:      cfg.Messaging.Username,
		Password:      cfg.Messaging.Password,
		SSL:           cfg.Messaging.SSL,
		CAFile:        cfg.Messaging.CAFile,
		SASLMechanism: cfg.Messaging.SASLMechanism,
		EmsID:         cfg.EMS.ID,
	}, log)
	if err != nil {
		fmt.Fprintf(os.Stderr, "kafka publisher init: %v\n", err)
		return 1
	}
	defer pub.Close()

	log.Info(logging.Msg("kafka publisher ready"),
		"host", cfg.Messaging.Host,
		"port", cfg.Messaging.Port,
		"ssl", cfg.Messaging.SSL,
	)

	hb := heartbeat.New(cfg.Settings.HeartbeatTimeout)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	sess := vim.New(vim.Config{
		Host:                  cfg.EMS.Host,
		Port:                  cfg.EMS.Port,
		VerifySSL:             cfg.EMS.VerifySSL,
		CertificateAuthority:  cfg.EMS.CertificateAuthority,
		Username:              cfg.EMS.Username,
		Password:              cfg.EMS.Password,
		EmsID:                 cfg.EMS.ID,
		BlacklistedEventNames: cfg.Settings.BlacklistedEventNames,
	}, log)
	sess.OnBeat = hb.Beat

	if err := hb.Ready(); err != nil {
		log.Warn(logging.Msg("sd_notify READY failed"), "err", err)
	}

	exitCode := mainLoop(ctx, log, sess, pub)

	// Cleanup on a fresh context — the main ctx may already be cancelled.
	cleanupCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	cleanup(cleanupCtx, log, hb)

	return exitCode
}

func setproctitle() {
	if len(os.Args) > 0 {
		os.Args[0] = "MIQ: Vmware::InfraManager::EventCatcher guid: " + os.Getenv("GUID")
	}
}

// shutdownTimeout is how long cleanup has after a signal.
const shutdownTimeout = 10 * time.Second

func mainLoop(ctx context.Context, log *slog.Logger, sess *vim.Session, pub publisher.Publisher) int {
	log.Info(logging.Msg("collecting events"))

	err := sess.Run(ctx, func(ctx context.Context, e *parser.Event) error {
		return pub.Publish(ctx, e)
	})
	if err != nil {
		log.Error(logging.Msg("event loop error"), "err", err)
		return 1
	}
	return 0
}

func cleanup(_ context.Context, log *slog.Logger, hb *heartbeat.Beater) {
	if err := hb.Stopping(); err != nil {
		log.Warn(logging.Msg("sd_notify STOPPING failed"), "err", err)
	}
	log.Info(logging.Msg("stopped"))
}
