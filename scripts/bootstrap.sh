#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-campuscast}"
COMPOSE_FILE="${COMPOSE_FILE:-${ROOT_DIR}/compose.yaml}"
BASE_URL="${BASE_URL:-http://localhost:3000}"

ADMIN_EMAIL="${AUTH_BOOTSTRAP_ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${AUTH_BOOTSTRAP_ADMIN_PASSWORD:-}"
REQUESTED_ADMIN_ROLE="${AUTH_BOOTSTRAP_ADMIN_ROLE:-}"
ADMIN_ROLE="super_admin"
ADMIN_RESET_PASSWORD="${AUTH_BOOTSTRAP_ADMIN_RESET_PASSWORD:-false}"

SKIP_BUILD=0
SKIP_SMOKE=0
FRESH=0

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  echo "[bootstrap] Docker Compose not found." >&2
  exit 1
fi

compose() {
  "${COMPOSE_CMD[@]}" --project-name "${PROJECT_NAME}" -f "${COMPOSE_FILE}" "$@"
}

usage() {
  cat <<'EOF'
Usage: ./scripts/bootstrap.sh [options]

Options:
  --admin-email <email>       First admin login/email (or AUTH_BOOTSTRAP_ADMIN_EMAIL)
  --admin-password <password> First admin password (or AUTH_BOOTSTRAP_ADMIN_PASSWORD)
  --admin-role <role>         Deprecated and ignored (bootstrap role is fixed to super_admin)
  --admin-reset-password      Force password reset for existing bootstrap admin
  --fresh                     Recreate stack from clean volumes (destructive)
  --skip-build                Skip docker image build step
  --skip-smoke                Skip post-bootstrap smoke checks
  -h, --help                  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --admin-email)
      ADMIN_EMAIL="${2:-}"
      shift 2
      ;;
    --admin-password)
      ADMIN_PASSWORD="${2:-}"
      shift 2
      ;;
    --admin-role)
      REQUESTED_ADMIN_ROLE="${2:-}"
      shift 2
      ;;
    --admin-reset-password)
      ADMIN_RESET_PASSWORD=true
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --fresh)
      FRESH=1
      shift
      ;;
    --skip-smoke)
      SKIP_SMOKE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[bootstrap] Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${ADMIN_EMAIL}" || -z "${ADMIN_PASSWORD}" ]]; then
  echo "[bootstrap] Missing admin credentials. Provide --admin-email/--admin-password or AUTH_BOOTSTRAP_ADMIN_EMAIL/AUTH_BOOTSTRAP_ADMIN_PASSWORD." >&2
  exit 2
fi

if [[ "${ADMIN_EMAIL}" =~ [[:space:]] ]]; then
  echo "[bootstrap] AUTH_BOOTSTRAP_ADMIN_EMAIL must not contain whitespace." >&2
  exit 2
fi

if [[ -n "${REQUESTED_ADMIN_ROLE}" && "${REQUESTED_ADMIN_ROLE}" != "${ADMIN_ROLE}" ]]; then
  echo "[bootstrap] AUTH_BOOTSTRAP_ADMIN_ROLE=${REQUESTED_ADMIN_ROLE} is ignored. Bootstrap role is fixed to ${ADMIN_ROLE}."
fi

export NODE_ENV="${NODE_ENV:-production}"
export DB_SYNCHRONIZE="${DB_SYNCHRONIZE:-false}"
export DB_MIGRATIONS_RUN="${DB_MIGRATIONS_RUN:-true}"
export AUTH_BOOTSTRAP_ROOT_ENABLED="${AUTH_BOOTSTRAP_ROOT_ENABLED:-false}"

BUILD_ARG=()
if [[ "${SKIP_BUILD}" -eq 0 ]]; then
  BUILD_ARG=(--build)
fi

if [[ "${FRESH}" -eq 1 ]]; then
  echo "[bootstrap] Resetting stack volumes for clean install."
  compose down --remove-orphans --volumes
fi

echo "[bootstrap] Starting stack (NODE_ENV=${NODE_ENV}, migrations=${DB_MIGRATIONS_RUN}, synchronize=${DB_SYNCHRONIZE})"
compose up -d "${BUILD_ARG[@]}" --remove-orphans

echo "[bootstrap] Waiting for API gateway health via ${BASE_URL}/health"
for _ in $(seq 1 90); do
  if curl -fsS "${BASE_URL}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! curl -fsS "${BASE_URL}/health" >/dev/null 2>&1; then
  echo "[bootstrap] API gateway health check did not become ready in time." >&2
  exit 1
fi

echo "[bootstrap] Running first-admin install-time bootstrap"
compose run --rm --no-deps \
  -e AUTH_BOOTSTRAP_ADMIN_EMAIL="${ADMIN_EMAIL}" \
  -e AUTH_BOOTSTRAP_ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
  -e AUTH_BOOTSTRAP_ADMIN_ROLE="${ADMIN_ROLE}" \
  -e AUTH_BOOTSTRAP_ADMIN_RESET_PASSWORD="${ADMIN_RESET_PASSWORD}" \
  auth-iam \
  node dist/bootstrap/create-first-admin.js

if [[ "${SKIP_SMOKE}" -eq 0 ]]; then
  echo "[bootstrap] Running smoke checks"
  AUTH_BOOTSTRAP_ADMIN_EMAIL="${ADMIN_EMAIL}" \
  AUTH_BOOTSTRAP_ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
  AUTH_BOOTSTRAP_ADMIN_ROLE="${ADMIN_ROLE}" \
  BASE_URL="${BASE_URL}" \
  "${SCRIPT_DIR}/smoke-bootstrap.sh"
fi

echo "[bootstrap] Bootstrap completed successfully."
