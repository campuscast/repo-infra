SHELL := /bin/bash

.PHONY: install-init stack-up stack-down stack-smoke stack-e2e ci-iam-runtime val03 val04 val05 val08 validation-all

install-init:
	: "$${AUTH_BOOTSTRAP_ADMIN_EMAIL:?AUTH_BOOTSTRAP_ADMIN_EMAIL is required}"
	: "$${AUTH_BOOTSTRAP_ADMIN_PASSWORD:?AUTH_BOOTSTRAP_ADMIN_PASSWORD is required}"
	AUTH_BOOTSTRAP_ADMIN_EMAIL="$${AUTH_BOOTSTRAP_ADMIN_EMAIL}" \
	AUTH_BOOTSTRAP_ADMIN_PASSWORD="$${AUTH_BOOTSTRAP_ADMIN_PASSWORD}" \
	AUTH_BOOTSTRAP_ADMIN_ROLE="$${AUTH_BOOTSTRAP_ADMIN_ROLE:-super_admin}" \
	./scripts/stack.sh bootstrap --fresh

stack-up:
	./scripts/stack.sh up

stack-down:
	./scripts/stack.sh down

stack-smoke:
	./scripts/stack.sh smoke

stack-e2e:
	./scripts/stack.sh e2e

ci-iam-runtime:
	: "$${AUTH_BOOTSTRAP_ADMIN_EMAIL:?AUTH_BOOTSTRAP_ADMIN_EMAIL is required}"
	: "$${AUTH_BOOTSTRAP_ADMIN_PASSWORD:?AUTH_BOOTSTRAP_ADMIN_PASSWORD is required}"
	mkdir -p artifacts
	AUTH_BOOTSTRAP_ADMIN_EMAIL="$${AUTH_BOOTSTRAP_ADMIN_EMAIL}" \
	AUTH_BOOTSTRAP_ADMIN_PASSWORD="$${AUTH_BOOTSTRAP_ADMIN_PASSWORD}" \
	./scripts/smoke-bootstrap.sh | tee artifacts/ci-smoke-bootstrap.log
	AUTH_BOOTSTRAP_ADMIN_EMAIL="$${AUTH_BOOTSTRAP_ADMIN_EMAIL}" \
	AUTH_BOOTSTRAP_ADMIN_PASSWORD="$${AUTH_BOOTSTRAP_ADMIN_PASSWORD}" \
	./scripts/e2e-iam.sh | tee artifacts/ci-e2e-iam.log

val03:
	: "$${AUTH_BOOTSTRAP_ADMIN_EMAIL:?AUTH_BOOTSTRAP_ADMIN_EMAIL is required}"
	: "$${AUTH_BOOTSTRAP_ADMIN_PASSWORD:?AUTH_BOOTSTRAP_ADMIN_PASSWORD is required}"
	AUTH_BOOTSTRAP_ADMIN_EMAIL="$${AUTH_BOOTSTRAP_ADMIN_EMAIL}" \
	AUTH_BOOTSTRAP_ADMIN_PASSWORD="$${AUTH_BOOTSTRAP_ADMIN_PASSWORD}" \
	BASE_URL="$${BASE_URL:-http://localhost:3000}" \
	node ./scripts/validation/load-test.mjs

val04:
	: "$${AUTH_BOOTSTRAP_ADMIN_EMAIL:?AUTH_BOOTSTRAP_ADMIN_EMAIL is required}"
	: "$${AUTH_BOOTSTRAP_ADMIN_PASSWORD:?AUTH_BOOTSTRAP_ADMIN_PASSWORD is required}"
	AUTH_BOOTSTRAP_ADMIN_EMAIL="$${AUTH_BOOTSTRAP_ADMIN_EMAIL}" \
	AUTH_BOOTSTRAP_ADMIN_PASSWORD="$${AUTH_BOOTSTRAP_ADMIN_PASSWORD}" \
	BASE_URL="$${BASE_URL:-http://localhost:3000}" \
	node ./scripts/validation/fault-sim.mjs

val05:
	: "$${AUTH_BOOTSTRAP_ADMIN_EMAIL:?AUTH_BOOTSTRAP_ADMIN_EMAIL is required}"
	: "$${AUTH_BOOTSTRAP_ADMIN_PASSWORD:?AUTH_BOOTSTRAP_ADMIN_PASSWORD is required}"
	AUTH_BOOTSTRAP_ADMIN_EMAIL="$${AUTH_BOOTSTRAP_ADMIN_EMAIL}" \
	AUTH_BOOTSTRAP_ADMIN_PASSWORD="$${AUTH_BOOTSTRAP_ADMIN_PASSWORD}" \
	BASE_URL="$${BASE_URL:-http://localhost:3000}" \
	node ./scripts/validation/crdt-metrics.mjs

val08:
	: "$${AUTH_BOOTSTRAP_ADMIN_EMAIL:?AUTH_BOOTSTRAP_ADMIN_EMAIL is required}"
	: "$${AUTH_BOOTSTRAP_ADMIN_PASSWORD:?AUTH_BOOTSTRAP_ADMIN_PASSWORD is required}"
	AUTH_BOOTSTRAP_ADMIN_EMAIL="$${AUTH_BOOTSTRAP_ADMIN_EMAIL}" \
	AUTH_BOOTSTRAP_ADMIN_PASSWORD="$${AUTH_BOOTSTRAP_ADMIN_PASSWORD}" \
	BASE_URL="$${BASE_URL:-http://localhost:3000}" \
	node ./scripts/validation/build-validation-pack.mjs

validation-all: val03 val04 val05 val08
