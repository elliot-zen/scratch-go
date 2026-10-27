SHELL := /bin/sh
.DEFAULT_GOAL := check
.DELETE_ON_ERROR:

STATICCHECK_VERSION := v0.8.2
GO ?= go
GOFMT ?= $(shell "$(GO)" env GOROOT)/bin/gofmt
# Replace this default with the project's primary service name during initialization.
SERVICE ?= service
VERSION ?= dev
# Separate installed tools by the toolchain selected for this module.
TOOLS_DIR = .tools/$(shell "$(GO)" env GOVERSION)
STATICCHECK := $(TOOLS_DIR)/staticcheck-$(STATICCHECK_VERSION)/staticcheck

.PHONY: build run test check fmt

# Shared prerequisite checks, expanded only when a public target runs.
define guard
	@test -f go.mod || { printf '%s\n' 'Run from the initialized Go module root.' >&2; exit 1; }
	@"$(GO)" env GOVERSION > /dev/null
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
