#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-campuscast}"
COMPOSE_FILE="${COMPOSE_FILE:-${ROOT_DIR}/compose.yaml}"
BASE_URL="${BASE_URL:-http://localhost:3000}"
ADMIN_EMAIL="${AUTH_BOOTSTRAP_ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${AUTH_BOOTSTRAP_ADMIN_PASSWORD:-}"
ADMIN_ROLE="${AUTH_BOOTSTRAP_ADMIN_ROLE:-admin}"

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  echo "[smoke] Docker Compose not found." >&2
  exit 1
fi

compose() {
  "${COMPOSE_CMD[@]}" --project-name "${PROJECT_NAME}" -f "${COMPOSE_FILE}" "$@"
}

if [[ -z "${ADMIN_EMAIL}" || -z "${ADMIN_PASSWORD}" ]]; then
  echo "[smoke] AUTH_BOOTSTRAP_ADMIN_EMAIL and AUTH_BOOTSTRAP_ADMIN_PASSWORD are required." >&2
  exit 2
fi

sql_escape() {
  local value="$1"
  printf "%s" "${value//\'/\'\'}"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf "%s" "${value}"
}

check_table() {
  local db="$1"
  local table="$2"
  local count=""
  for _ in $(seq 1 30); do
    count="$(
      compose exec -T postgres psql -U campuscast -d "${db}" -tAc \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '${table}';"
    )"
    count="$(echo "${count}" | tr -d '[:space:]')"
    if [[ "${count}" == "1" ]]; then
      break
    fi
    sleep 2
  done
  if [[ "${count}" != "1" ]]; then
    echo "[smoke] FAIL: table ${db}.${table} not found" >&2
    exit 1
  fi
  echo "[smoke] OK: table ${db}.${table}"
}

check_migrations_row() {
  local db="$1"
  local count=""
  for _ in $(seq 1 30); do
    count="$(
      compose exec -T postgres psql -U campuscast -d "${db}" -tAc \
        "SELECT COUNT(*) FROM migrations;" 2>/dev/null || true
    )"
    count="$(echo "${count}" | tr -d '[:space:]')"
    if [[ "${count}" =~ ^[0-9]+$ && "${count}" -ge 1 ]]; then
      break
    fi
    sleep 2
  done
  if [[ ! "${count}" =~ ^[0-9]+$ || "${count}" -lt 1 ]]; then
    echo "[smoke] FAIL: no migration records in ${db}.migrations" >&2
    exit 1
  fi
  echo "[smoke] OK: ${db}.migrations has ${count} row(s)"
}

wait_health() {
  for _ in $(seq 1 90); do
    if curl -fsS "${BASE_URL}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "[smoke] FAIL: ${BASE_URL}/health is not ready" >&2
  exit 1
}

echo "[smoke] Waiting for gateway health"
wait_health

echo "[smoke] Checking migration state on service databases"
check_table auth_db users
check_table zone_policy_db zones
check_table device_db devices
check_table content_db content_assets
check_table schedule_db schedules
check_table audit_db audit_events

check_migrations_row auth_db
check_migrations_row zone_policy_db
check_migrations_row device_db
check_migrations_row content_db
check_migrations_row schedule_db
check_migrations_row audit_db

admin_email_sql="$(sql_escape "${ADMIN_EMAIL}")"
admin_count="$(
  compose exec -T postgres psql -U campuscast -d auth_db -tAc \
    "SELECT COUNT(*) FROM users WHERE email = '${admin_email_sql}';"
)"
admin_count="$(echo "${admin_count}" | tr -d '[:space:]')"
if [[ "${admin_count}" -lt 1 ]]; then
  echo "[smoke] FAIL: admin user ${ADMIN_EMAIL} not found in auth_db.users" >&2
  exit 1
fi
echo "[smoke] OK: admin user ${ADMIN_EMAIL} exists"

echo "[smoke] Checking auth login"
login_payload="$(printf '{"email":"%s","password":"%s"}' "$(json_escape "${ADMIN_EMAIL}")" "$(json_escape "${ADMIN_PASSWORD}")")"
login_response="$(curl -fsS -X POST "${BASE_URL}/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "${login_payload}")"
access_token="$(printf "%s" "${login_response}" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"

if [[ -z "${access_token}" ]]; then
  echo "[smoke] FAIL: login response did not contain access_token" >&2
  echo "[smoke] Response: ${login_response}" >&2
  exit 1
fi
echo "[smoke] OK: login returned access token"

me_response="$(curl -fsS "${BASE_URL}/api/v1/me" -H "Authorization: Bearer ${access_token}")"
if [[ "${me_response}" != *"\"email\":\"${ADMIN_EMAIL}\""* ]]; then
  echo "[smoke] FAIL: /api/v1/me did not return expected admin email" >&2
  echo "[smoke] Response: ${me_response}" >&2
  exit 1
fi
if [[ "${me_response}" != *"\"${ADMIN_ROLE}\""* ]]; then
  echo "[smoke] FAIL: /api/v1/me does not include expected admin role ${ADMIN_ROLE}" >&2
  echo "[smoke] Response: ${me_response}" >&2
  exit 1
fi

echo "[smoke] PASS: migrations, first-admin bootstrap, and auth login checks succeeded."
