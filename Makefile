SHELL := /bin/sh
.DEFAULT_GOAL := check
.DELETE_ON_ERROR:

GO_VERSION := 1.27.3
STATICCHECK_VERSION := v0.8.2
export GOTOOLCHAIN := local
GO ?= go
GOFMT ?= $(shell "$(GO)" env GOROOT)/bin/gofmt
# Replace this default with the project's primary service name during initialization.
SERVICE ?= service
VERSION ?= dev
TOOLS_DIR := .tools/go$(GO_VERSION)
STATICCHECK := $(TOOLS_DIR)/staticcheck-$(STATICCHECK_VERSION)/staticcheck

.PHONY: build run test check fmt

# Shared prerequisite checks, expanded only when a public target runs.
define guard
	@test -f go.mod || { printf '%s\n' 'Run from the initialized Go module root.' >&2; exit 1; }
	@actual="$$("$(GO)" env GOVERSION)" && test "$$actual" = 'go$(GO_VERSION)' || { printf '%s\n' 'Go toolchain mismatch: expected go$(GO_VERSION).' >&2; exit 1; }
endef

build:
	$(guard)
	@mkdir -p bin
	"$(GO)" build -trimpath -ldflags '-X main.version=$(VERSION)' -o 'bin/$(SERVICE)' './cmd/$(SERVICE)'

run: build
	'./bin/$(SERVICE)'

test:
	$(guard)
	"$(GO)" test -count=1 -timeout=60s ./...

check:
	$(guard)
	@test -x '$(GOFMT)' || { printf '%s\n' 'gofmt is required from the selected Go toolchain.' >&2; exit 1; }
	@files="$$(find . -type d \( -name .git -o -name .tools -o -name vendor \) -prune -o -type f -name '*.go' -exec '$(GOFMT)' -l {} +)" || exit 1; \
	if [ -n "$$files" ]; then printf 'Unformatted Go files:\n%s\n' "$$files" >&2; exit 1; fi
	"$(GO)" mod verify
	"$(GO)" mod tidy -diff
	"$(GO)" build ./...
	"$(GO)" vet ./...
	@if ! test -x '$(STATICCHECK)'; then \
	  mkdir -p '$(dir $(STATICCHECK))' && \
	  GOBIN='$(CURDIR)/$(dir $(STATICCHECK))' "$(GO)" install honnef.co/go/tools/cmd/staticcheck@$(STATICCHECK_VERSION); \
	fi
	PATH="$$("$(GO)" env GOROOT)/bin:$$PATH" '$(STATICCHECK)' ./...
	CGO_ENABLED=1 "$(GO)" test -race -count=1 -timeout=120s ./...

fmt:
	$(guard)
	@test -x '$(GOFMT)' || { printf '%s\n' 'gofmt is required from the selected Go toolchain.' >&2; exit 1; }
	@find . -type d \( -name .git -o -name .tools -o -name vendor \) -prune -o -type f -name '*.go' -exec '$(GOFMT)' -w {} +
