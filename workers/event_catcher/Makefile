.PHONY: build install test vet fmt check clean

GO      ?= go
BIN_DIR := bin
BIN     := $(BIN_DIR)/event_catcher

# Static, stripped binary. CGO is disabled on purpose: the build must not need a C toolchain
build:
	CGO_ENABLED=0 $(GO) build -trimpath -ldflags="-s -w" -o $(BIN) ./cmd/event_catcher

# ManageIQ core execs workers/event_catcher/worker, so install copies the binary to that path.
install: build
	install -m 0755 $(BIN) worker

test:
	$(GO) test ./...

vet:
	$(GO) vet ./...

fmt:
	@test -z "$$(gofmt -l .)" || (gofmt -l . && echo "gofmt needed" && exit 1)

check: fmt vet test

clean:
	rm -rf $(BIN_DIR)
