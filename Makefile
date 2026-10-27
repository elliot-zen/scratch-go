SHELL := /bin/sh
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:

GO_VERSION := 1.27.3
STATICCHECK_VERSION := v0.8.2
GOVULNCHECK_VERSION := v1.9.0
export GOTOOLCHAIN := local
GO ?= go
GOFMT ?= $(shell "$(GO)" env GOROOT)/bin/gofmt
VERSION ?= dev
TOOLS_DIR := .tools/go$(GO_VERSION)
STATICCHECK := $(TOOLS_DIR)/staticcheck-$(STATICCHECK_VERSION)/staticcheck
GOVULNCHECK := $(TOOLS_DIR)/govulncheck-$(GOVULNCHECK_VERSION)/govulncheck

.PHONY: help guard tools fmt fmt-check mod-check build-check vet lint test check race build run env vuln release-check

help:
	@printf '%s\n' \
	  'tools          Install pinned check tools (network required on first use)' \
	  'fmt            Format Go sources' \
	  'check          Check format, modules, build, vet, static analysis and tests' \
	  'race           Run tests with the race detector (C compiler required)' \
	  'build          Build bin/api; override VERSION for release identity' \
	  'run            Run bin/api in the foreground; HTTP_ADDR defaults to :8080' \
	  'env            Print source, platform and installed tool information' \
	  'vuln           Scan vulnerabilities (current database; network required)' \
	  'release-check  Run check, race and vulnerability scan'

guard:
	@test -f go.mod || { printf '%s\n' 'Run from the initialized Go module root.' >&2; exit 1; }
	@actual="$$("$(GO)" env GOVERSION)" && test "$$actual" = 'go$(GO_VERSION)' || { printf '%s\n' 'Go toolchain mismatch: expected go$(GO_VERSION).' >&2; exit 1; }
	@test -x '$(GOFMT)' || { printf '%s\n' 'gofmt is required from the selected Go toolchain.' >&2; exit 1; }

$(STATICCHECK): | guard
	@mkdir -p '$(dir $@)'
	GOBIN='$(CURDIR)/$(dir $@)' "$(GO)" install honnef.co/go/tools/cmd/staticcheck@$(STATICCHECK_VERSION)

$(GOVULNCHECK): | guard
	@mkdir -p '$(dir $@)'
	GOBIN='$(CURDIR)/$(dir $@)' "$(GO)" install golang.org/x/vuln/cmd/govulncheck@$(GOVULNCHECK_VERSION)

tools: $(STATICCHECK) $(GOVULNCHECK)

fmt: guard
	@find . -type d \( -name .git -o -name .tools -o -name vendor \) -prune -o -type f -name '*.go' -exec '$(GOFMT)' -w {} +

fmt-check: guard
	@files="$$(find . -type d \( -name .git -o -name .tools -o -name vendor \) -prune -o -type f -name '*.go' -exec '$(GOFMT)' -l {} +)" || exit 1; \
	if [ -n "$$files" ]; then printf 'Unformatted Go files:\n%s\n' "$$files" >&2; exit 1; fi

mod-check: guard
	"$(GO)" mod verify
	"$(GO)" mod tidy -diff

build-check: guard
	"$(GO)" build ./...

vet: guard
	"$(GO)" vet ./...

lint: guard $(STATICCHECK)
	PATH="$$("$(GO)" env GOROOT)/bin:$$PATH" '$(STATICCHECK)' ./...

test: guard
	"$(GO)" test -count=1 -timeout=60s ./...

check: fmt-check mod-check build-check vet lint test

race: guard
	CGO_ENABLED=1 "$(GO)" test -race -count=1 -timeout=120s ./...

build: guard
	@mkdir -p bin
	"$(GO)" build -trimpath -ldflags '-X main.version=$(VERSION)' -o bin/api ./cmd/api

run: build
	./bin/api

env: guard
	@date -u '+Checked at: %Y-%m-%dT%H:%M:%SZ'
	@if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
	  if git rev-parse --verify HEAD >/dev/null 2>&1; then git rev-parse HEAD; else printf '%s\n' 'Source revision: no commits yet'; fi; \
	  git status --short; \
	else printf '%s\n' 'Source identity: no Git repository available'; fi
	"$(GO)" version
	"$(GO)" env GOOS GOARCH CGO_ENABLED GOTOOLCHAIN GOFLAGS
	@if test -x '$(STATICCHECK)'; then '$(STATICCHECK)' -version; else printf 'Staticcheck %s: not installed\n' '$(STATICCHECK_VERSION)'; fi
	@if test -x '$(GOVULNCHECK)'; then "$(GO)" version -m '$(GOVULNCHECK)'; else printf 'Govulncheck %s: not installed\n' '$(GOVULNCHECK_VERSION)'; fi
	"$(GO)" list -m all

vuln: guard $(GOVULNCHECK)
	@date -u '+Vulnerability scan at: %Y-%m-%dT%H:%M:%SZ'
	PATH="$$("$(GO)" env GOROOT)/bin:$$PATH" '$(GOVULNCHECK)' -show verbose ./...

release-check: check race vuln
