SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

.PHONY: help
help:
	@printf '%s\n' \
		'Targets:' \
		'  validate        Run local build/template validation' \
		'  validate-full   Run local and extended validation' \
		'  local-up        Start the full local stack' \
		'  local-test      Run local workflow/OIDC health test' \
		'  local-sso       Run browser SSO smoke test' \
		'  local-full      Start stack and run local tests' \
		'  local-down      Stop local stack' \
		'  local-clean     Stop local stack and remove volumes' \
		'  devconsole-build Build the main DevConsole Docker image' \
		'  aws-preflight   Validate AWS bootstrap inputs without AWS writes' \
		'  deploy-preflight Validate full deploy .env without external calls'

.PHONY: validate
validate:
	./infra/scripts/validate-local.sh

.PHONY: validate-full
validate-full:
	./infra/scripts/validate-local.sh
	./infra/scripts/validate-extended-local.sh

.PHONY: local-up
local-up:
	./local/scripts/local-up.sh

.PHONY: local-test
local-test:
	./local/scripts/local-test.sh

.PHONY: local-sso
local-sso:
	./local/scripts/local-sso-browser-test.sh

.PHONY: local-full
local-full:
	./local/scripts/local-up.sh
	./local/scripts/local-test.sh
	./local/scripts/local-sso-browser-test.sh

.PHONY: local-down
local-down:
	./local/scripts/local-down.sh

.PHONY: local-clean
local-clean:
	./local/scripts/local-down.sh --volumes

.PHONY: devconsole-build
devconsole-build:
	docker build -t temporal-devconsole:local .

.PHONY: aws-preflight
aws-preflight:
	./infra/scripts/bootstrap-aws.sh --dry-run

.PHONY: deploy-preflight
deploy-preflight:
	./infra/scripts/validate-deploy-env.sh
	set -a; source .env; set +a; ./infra/scripts/deploy.sh --check-env-only
