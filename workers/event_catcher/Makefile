.PHONY: build test vet fmt check clean

GO ?= go

# Static, stripped binary. CGO is disabled on purpose: the build must not need a C toolchain.
# ManageIQ core execs workers/event_catcher/worker directly, so the binary is built there.
build:
	CGO_ENABLED=0 $(GO) build -trimpath -ldflags="-s -w" -o worker ./cmd/event_catcher

test:
	$(GO) test ./...

vet:
	$(GO) vet ./...

fmt:
	@test -z "$$(gofmt -l .)" || (gofmt -l . && echo "gofmt needed" && exit 1)

check: fmt vet test

clean:
	rm -f worker
