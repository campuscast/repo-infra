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
TMP_DIR="$(mktemp -d)"
COOKIE_JAR="${TMP_DIR}/cookies.txt"

trap 'rm -rf "${TMP_DIR}"' EXIT
touch "${COOKIE_JAR}"

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

if [[ -n "${REQUESTED_ADMIN_ROLE}" && "${REQUESTED_ADMIN_ROLE}" != "${ADMIN_ROLE}" ]]; then
  echo "[smoke] AUTH_BOOTSTRAP_ADMIN_ROLE=${REQUESTED_ADMIN_ROLE} is ignored. Expected bootstrap role: ${ADMIN_ROLE}."
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

extract_json_string() {
  local json="$1"
  local field="$2"
  printf "%s" "${json}" | sed -n "s/.*\"${field}\":\"\\([^\"]*\\)\".*/\\1/p"
}

cookie_value() {
  local cookie_name="$1"
  awk -v name="${cookie_name}" 'BEGIN { value = "" } NF >= 7 && $6 == name { value = $7 } END { print value }' "${COOKIE_JAR}"
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
  -c "${COOKIE_JAR}" \
  -b "${COOKIE_JAR}" \
  -H "Content-Type: application/json" \
  -d "${login_payload}")"
access_token="$(extract_json_string "${login_response}" "access_token")"

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
if [[ "${me_response}" != *"\"permissions\""* ]]; then
  echo "[smoke] FAIL: /api/v1/me does not include permissions array" >&2
  echo "[smoke] Response: ${me_response}" >&2
  exit 1
fi
echo "[smoke] OK: /me returns email, role, and permissions"

echo "[smoke] Checking cookie-based auth flow"
access_cookie="$(cookie_value "cc_access_token")"
refresh_cookie="$(cookie_value "refresh_token")"
csrf_cookie="$(cookie_value "csrf_token")"
if [[ -z "${access_cookie}" || -z "${csrf_cookie}" ]]; then
  echo "[smoke] FAIL: login did not set expected auth/csrf cookies" >&2
  exit 1
fi
if [[ -z "${refresh_cookie}" ]]; then
  echo "[smoke] WARN: refresh_token cookie missing in login response (continuing)"
fi

me_cookie_response="$(curl -fsS "${BASE_URL}/api/v1/me" -b "${COOKIE_JAR}")"
if [[ "${me_cookie_response}" != *"\"email\":\"${ADMIN_EMAIL}\""* ]]; then
  echo "[smoke] FAIL: cookie-auth /api/v1/me did not return expected admin email" >&2
  echo "[smoke] Response: ${me_cookie_response}" >&2
  exit 1
fi
echo "[smoke] OK: cookie-based /me flow works"

# ── Init state ──
echo "[smoke] Checking system init state"
init_response="$(curl -fsS "${BASE_URL}/api/v1/system/init-state")"
if [[ "${init_response}" != *"\"initialized\":true"* ]]; then
  echo "[smoke] FAIL: /api/v1/system/init-state does not show initialized=true" >&2
  echo "[smoke] Response: ${init_response}" >&2
  exit 1
fi
echo "[smoke] OK: system init-state shows initialized=true"

# ── Users API ──
echo "[smoke] Checking users list API"
users_response="$(curl -fsS "${BASE_URL}/api/v1/users" \
  -H "Authorization: Bearer ${access_token}")"
if [[ "${users_response}" != *"\"data\""* ]]; then
  echo "[smoke] FAIL: GET /api/v1/users did not return data array" >&2
  echo "[smoke] Response: ${users_response}" >&2
  exit 1
fi
echo "[smoke] OK: users list returns data"

# ── Roles API ──
echo "[smoke] Checking roles list API"
roles_response="$(curl -fsS "${BASE_URL}/api/v1/roles" \
  -H "Authorization: Bearer ${access_token}")"
if [[ "${roles_response}" != *"\"data\""* ]]; then
  echo "[smoke] FAIL: GET /api/v1/roles did not return data array" >&2
  echo "[smoke] Response: ${roles_response}" >&2
  exit 1
fi
if [[ "${roles_response}" != *"\"super_admin\""* ]]; then
  echo "[smoke] FAIL: roles list does not contain super_admin role" >&2
  exit 1
fi
echo "[smoke] OK: roles list returns data with default roles"

# ── Schedule + device read paths ──
echo "[smoke] Checking zone/schedule/device read paths"
zones_response="$(curl -fsS "${BASE_URL}/api/v1/zones?page=1&page_size=1" -H "Authorization: Bearer ${access_token}")"
if [[ "${zones_response}" != *"\"data\""* ]]; then
  echo "[smoke] FAIL: GET /api/v1/zones did not return data array" >&2
  echo "[smoke] Response: ${zones_response}" >&2
  exit 1
fi

zone_id="$(printf "%s" "${zones_response}" | sed -n 's/.*"zone_id":"\([^"]*\)".*/\1/p' | head -n1)"
if [[ -z "${zone_id}" ]]; then
  zone_name="smoke-zone-$(date +%s)"
  create_zone_payload="$(printf '{"name":"%s","description":"smoke"}' "$(json_escape "${zone_name}")")"
  create_zone_response="$(curl -fsS -X POST "${BASE_URL}/api/v1/zones" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    -d "${create_zone_payload}")"
  zone_id="$(extract_json_string "${create_zone_response}" "zone_id")"
fi

if [[ -z "${zone_id}" ]]; then
  echo "[smoke] FAIL: could not determine zone_id for schedule/device checks" >&2
  exit 1
fi

schedules_response="$(curl -fsS "${BASE_URL}/api/v1/schedules?zone_id=${zone_id}&page=1&page_size=5" \
  -H "Authorization: Bearer ${access_token}")"
if [[ "${schedules_response}" != *"\"data\""* ]]; then
  echo "[smoke] FAIL: GET /api/v1/schedules did not return data array" >&2
  echo "[smoke] Response: ${schedules_response}" >&2
  exit 1
fi

devices_response="$(curl -fsS "${BASE_URL}/api/v1/devices?zone_id=${zone_id}" \
  -H "Authorization: Bearer ${access_token}")"
if [[ "${devices_response}" != *"\"data\""* ]]; then
  echo "[smoke] FAIL: GET /api/v1/devices did not return data payload" >&2
  echo "[smoke] Response: ${devices_response}" >&2
  exit 1
fi
echo "[smoke] OK: schedule/device read paths respond successfully"

# ── Permission enforcement ──
echo "[smoke] Checking permission enforcement (unauthenticated request)"
unauth_code="$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/api/v1/users")"
if [[ "${unauth_code}" != "401" ]]; then
  echo "[smoke] FAIL: GET /api/v1/users without token returned ${unauth_code}, expected 401" >&2
  exit 1
fi
echo "[smoke] OK: unauthenticated /users request returns 401"

echo "[smoke] Checking logout and session invalidation"
logout_code="$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST "${BASE_URL}/api/v1/auth/logout" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: ${csrf_cookie}" \
  -b "${COOKIE_JAR}" \
  -c "${COOKIE_JAR}" \
  -d '{}')"
if [[ "${logout_code}" != "200" ]]; then
  echo "[smoke] FAIL: /api/v1/auth/logout returned ${logout_code}, expected 200" >&2
  exit 1
fi

me_after_logout_code="$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/api/v1/me" -b "${COOKIE_JAR}")"
if [[ "${me_after_logout_code}" != "401" ]]; then
  echo "[smoke] FAIL: cookie-based /api/v1/me after logout returned ${me_after_logout_code}, expected 401" >&2
  exit 1
fi
echo "[smoke] OK: logout invalidates cookie-based session"

echo "[smoke] PASS: migrations, init-state, login, cookie-auth, IAM APIs, permission checks, schedule/device reads, and logout checks succeeded."
