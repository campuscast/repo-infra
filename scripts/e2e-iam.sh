#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
ADMIN_EMAIL="${AUTH_BOOTSTRAP_ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${AUTH_BOOTSTRAP_ADMIN_PASSWORD:-}"

if [[ -z "${ADMIN_EMAIL}" || -z "${ADMIN_PASSWORD}" ]]; then
  echo "[e2e] AUTH_BOOTSTRAP_ADMIN_EMAIL and AUTH_BOOTSTRAP_ADMIN_PASSWORD are required." >&2
  exit 2
fi

TMP_DIR="$(mktemp -d)"
ADMIN_COOKIE_JAR="${TMP_DIR}/admin.cookies"
USER_COOKIE_JAR="${TMP_DIR}/user.cookies"
trap 'rm -rf "${TMP_DIR}"' EXIT
touch "${ADMIN_COOKIE_JAR}" "${USER_COOKIE_JAR}"

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
  local cookie_file="$1"
  local cookie_name="$2"
  awk -v name="${cookie_name}" 'BEGIN { value = "" } !/^#/ && $6 == name { value = $7 } END { print value }' "${cookie_file}"
}

wait_for_audit_event() {
  local event_type="$1"
  local resource_id="$2"

  for _ in $(seq 1 25); do
    local response
    response="$(curl -fsS "${BASE_URL}/api/v1/audit?event_type=${event_type}&page=1&page_size=50" \
      -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}")"
    if [[ "${response}" == *"\"resource_id\":\"${resource_id}\""* ]]; then
      return 0
    fi
    sleep 1
  done

  echo "[e2e] FAIL: audit event ${event_type} for resource ${resource_id} not found" >&2
  exit 1
}

echo "[e2e] Waiting for gateway health"
for _ in $(seq 1 60); do
  if curl -fsS "${BASE_URL}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl -fsS "${BASE_URL}/health" >/dev/null

echo "[e2e] Checking init-state"
init_response="$(curl -fsS "${BASE_URL}/api/v1/system/init-state")"
if [[ "${init_response}" != *"\"initialized\":true"* ]]; then
  echo "[e2e] FAIL: /api/v1/system/init-state did not return initialized=true" >&2
  echo "[e2e] Response: ${init_response}" >&2
  exit 1
fi

echo "[e2e] Admin login + cookie flow"
admin_login_payload="$(printf '{"email":"%s","password":"%s"}' "$(json_escape "${ADMIN_EMAIL}")" "$(json_escape "${ADMIN_PASSWORD}")")"
admin_login_response="$(curl -fsS -X POST "${BASE_URL}/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -c "${ADMIN_COOKIE_JAR}" \
  -b "${ADMIN_COOKIE_JAR}" \
  -d "${admin_login_payload}")"
ADMIN_ACCESS_TOKEN="$(extract_json_string "${admin_login_response}" "access_token")"
if [[ -z "${ADMIN_ACCESS_TOKEN}" ]]; then
  echo "[e2e] FAIL: admin login did not return access_token" >&2
  echo "[e2e] Response: ${admin_login_response}" >&2
  exit 1
fi
admin_csrf_token="$(cookie_value "${ADMIN_COOKIE_JAR}" "csrf_token")"
if [[ -z "${admin_csrf_token}" ]]; then
  echo "[e2e] FAIL: admin csrf cookie missing after login" >&2
  exit 1
fi
admin_me_response="$(curl -fsS "${BASE_URL}/api/v1/me" -b "${ADMIN_COOKIE_JAR}")"
if [[ "${admin_me_response}" != *"\"email\":\"${ADMIN_EMAIL}\""* ]]; then
  echo "[e2e] FAIL: cookie-based /api/v1/me failed for admin" >&2
  exit 1
fi

E2E_SUFFIX="$(date +%s)"
ROLE_NAME="e2e_role_${E2E_SUFFIX}"
USER_EMAIL="e2e_user_${E2E_SUFFIX}@example.local"
USER_INITIAL_PASSWORD='StartPwd123!'
USER_RESET_PASSWORD='ResetPwd123!'
USER_CHANGED_PASSWORD='ChangedPwd123!'

echo "[e2e] Roles CRUD"
create_role_payload="$(printf '{"name":"%s","permissions":["users.read"]}' "$(json_escape "${ROLE_NAME}")")"
create_role_response="$(curl -fsS -X POST "${BASE_URL}/api/v1/roles" \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${create_role_payload}")"
ROLE_ID="$(extract_json_string "${create_role_response}" "id")"
if [[ -z "${ROLE_ID}" ]]; then
  echo "[e2e] FAIL: role create did not return id" >&2
  echo "[e2e] Response: ${create_role_response}" >&2
  exit 1
fi

update_role_payload='{"permissions":["users.read","audit.read"]}'
update_role_response="$(curl -fsS -X PUT "${BASE_URL}/api/v1/roles/${ROLE_ID}" \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${update_role_payload}")"
if [[ "${update_role_response}" != *"\"id\":\"${ROLE_ID}\""* ]]; then
  echo "[e2e] FAIL: role update response mismatch" >&2
  echo "[e2e] Response: ${update_role_response}" >&2
  exit 1
fi

echo "[e2e] Users CRUD"
create_user_payload="$(printf '{"email":"%s","name":"E2E User","password":"%s"}' \
  "$(json_escape "${USER_EMAIL}")" \
  "$(json_escape "${USER_INITIAL_PASSWORD}")")"
create_user_response="$(curl -fsS -X POST "${BASE_URL}/api/v1/users" \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${create_user_payload}")"
USER_ID="$(extract_json_string "${create_user_response}" "id")"
if [[ -z "${USER_ID}" ]]; then
  echo "[e2e] FAIL: user create did not return id" >&2
  echo "[e2e] Response: ${create_user_response}" >&2
  exit 1
fi

get_user_response="$(curl -fsS "${BASE_URL}/api/v1/users/${USER_ID}" \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}")"
if [[ "${get_user_response}" != *"\"id\":\"${USER_ID}\""* ]]; then
  echo "[e2e] FAIL: user get did not return created user" >&2
  exit 1
fi

update_user_payload='{"name":"E2E Updated User"}'
update_user_response="$(curl -fsS -X PUT "${BASE_URL}/api/v1/users/${USER_ID}" \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${update_user_payload}")"
if [[ "${update_user_response}" != *"E2E Updated User"* ]]; then
  echo "[e2e] FAIL: user update did not apply name change" >&2
  exit 1
fi

echo "[e2e] Role assign/remove to user"
assign_role_payload="$(printf '{"user_id":"%s","role_id":"%s"}' "${USER_ID}" "${ROLE_ID}")"
curl -fsS -X POST "${BASE_URL}/api/v1/roles/assign" \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${assign_role_payload}" >/dev/null
curl -fsS -X POST "${BASE_URL}/api/v1/roles/remove" \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${assign_role_payload}" >/dev/null

echo "[e2e] Password reset + cookie auth + password change"
reset_password_payload="$(printf '{"temporary_password":"%s"}' "$(json_escape "${USER_RESET_PASSWORD}")")"
reset_password_response="$(curl -fsS -X POST "${BASE_URL}/api/v1/users/${USER_ID}/reset-password" \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${reset_password_payload}")"
if [[ "${reset_password_response}" != *"\"ok\":true"* ]]; then
  echo "[e2e] FAIL: reset password endpoint failed" >&2
  echo "[e2e] Response: ${reset_password_response}" >&2
  exit 1
fi

user_login_payload="$(printf '{"email":"%s","password":"%s"}' "$(json_escape "${USER_EMAIL}")" "$(json_escape "${USER_RESET_PASSWORD}")")"
user_login_response="$(curl -fsS -X POST "${BASE_URL}/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -c "${USER_COOKIE_JAR}" \
  -b "${USER_COOKIE_JAR}" \
  -d "${user_login_payload}")"
USER_ACCESS_TOKEN="$(extract_json_string "${user_login_response}" "access_token")"
if [[ -z "${USER_ACCESS_TOKEN}" ]]; then
  echo "[e2e] FAIL: user login failed after reset password" >&2
  exit 1
fi

user_csrf_token="$(cookie_value "${USER_COOKIE_JAR}" "csrf_token")"
if [[ -z "${user_csrf_token}" ]]; then
  echo "[e2e] FAIL: user csrf cookie missing after login" >&2
  exit 1
fi

user_change_password_payload="$(printf '{"current_password":"%s","new_password":"%s"}' \
  "$(json_escape "${USER_RESET_PASSWORD}")" \
  "$(json_escape "${USER_CHANGED_PASSWORD}")")"
change_password_response="$(curl -fsS -X POST "${BASE_URL}/api/v1/users/me/change-password" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: ${user_csrf_token}" \
  -b "${USER_COOKIE_JAR}" \
  -c "${USER_COOKIE_JAR}" \
  -d "${user_change_password_payload}")"
if [[ "${change_password_response}" != *"\"ok\":true"* ]]; then
  echo "[e2e] FAIL: user change-password failed" >&2
  echo "[e2e] Response: ${change_password_response}" >&2
  exit 1
fi

echo "[e2e] Permission enforcement (non-admin user should be denied role creation)"
forbidden_code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "${BASE_URL}/api/v1/roles" \
  -H "Authorization: Bearer ${USER_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name":"forbidden_role","permissions":["users.read"]}')"
if [[ "${forbidden_code}" != "403" ]]; then
  echo "[e2e] FAIL: expected 403 for role creation by non-admin user, got ${forbidden_code}" >&2
  exit 1
fi

echo "[e2e] Schedule fetch/edit happy path"
zones_response="$(curl -fsS "${BASE_URL}/api/v1/zones?page=1&page_size=1" \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}")"
ZONE_ID="$(printf "%s" "${zones_response}" | sed -n 's/.*"zone_id":"\([^"]*\)".*/\1/p' | head -n1)"
if [[ -z "${ZONE_ID}" ]]; then
  zone_name="e2e-zone-${E2E_SUFFIX}"
  create_zone_payload="$(printf '{"name":"%s","description":"e2e"}' "$(json_escape "${zone_name}")")"
  create_zone_response="$(curl -fsS -X POST "${BASE_URL}/api/v1/zones" \
    -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${create_zone_payload}")"
  ZONE_ID="$(extract_json_string "${create_zone_response}" "zone_id")"
fi
if [[ -z "${ZONE_ID}" ]]; then
  echo "[e2e] FAIL: could not get zone for schedule e2e flow" >&2
  exit 1
fi

create_schedule_payload="$(printf '{"zone_id":"%s","name":"%s"}' "${ZONE_ID}" "e2e-schedule-${E2E_SUFFIX}")"
create_schedule_response="$(curl -fsS -X POST "${BASE_URL}/api/v1/schedules" \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${create_schedule_payload}")"
SCHEDULE_ID="$(extract_json_string "${create_schedule_response}" "schedule_id")"
if [[ -z "${SCHEDULE_ID}" ]]; then
  echo "[e2e] FAIL: schedule create failed" >&2
  echo "[e2e] Response: ${create_schedule_response}" >&2
  exit 1
fi

lock_response="$(curl -fsS -X POST "${BASE_URL}/api/v1/schedules/${SCHEDULE_ID}/lock" \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"ttl_seconds":120}')"
LOCK_TOKEN="$(extract_json_string "${lock_response}" "lock_token")"
if [[ -z "${LOCK_TOKEN}" ]]; then
  echo "[e2e] FAIL: schedule lock failed" >&2
  echo "[e2e] Response: ${lock_response}" >&2
  exit 1
fi

save_payload="$(printf '{"lock_token":"%s","slots":[{"asset_id":"asset-e2e","start_time":"2030-01-01T10:00:00Z","end_time":"2030-01-01T11:00:00Z","priority":10,"zone_id":"%s","group_id":"g-e2e"}]}' "${LOCK_TOKEN}" "${ZONE_ID}")"
save_response="$(curl -fsS -X POST "${BASE_URL}/api/v1/schedules/${SCHEDULE_ID}/save" \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${save_payload}")"
if [[ "${save_response}" != *"\"schedule_id\":\"${SCHEDULE_ID}\""* ]]; then
  echo "[e2e] FAIL: schedule save draft failed" >&2
  echo "[e2e] Response: ${save_response}" >&2
  exit 1
fi

curl -fsS -X DELETE "${BASE_URL}/api/v1/schedules/${SCHEDULE_ID}/lock" \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(printf '{"lock_token":"%s"}' "${LOCK_TOKEN}")" >/dev/null

schedules_response="$(curl -fsS "${BASE_URL}/api/v1/schedules?zone_id=${ZONE_ID}&page=1&page_size=20" \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}")"
if [[ "${schedules_response}" != *"\"schedule_id\":\"${SCHEDULE_ID}\""* ]]; then
  echo "[e2e] FAIL: schedule list did not include created schedule" >&2
  exit 1
fi

echo "[e2e] Checking audit side-effects"
wait_for_audit_event "iam.user_created" "${USER_ID}"
wait_for_audit_event "iam.role_created" "${ROLE_ID}"
wait_for_audit_event "iam.password_changed" "${USER_ID}"

echo "[e2e] Deactivating e2e user"
deactivate_response="$(curl -fsS -X DELETE "${BASE_URL}/api/v1/users/${USER_ID}" \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}")"
if [[ "${deactivate_response}" != *"\"status\":\"inactive\""* ]]; then
  echo "[e2e] FAIL: deactivate user did not set inactive status" >&2
  exit 1
fi

echo "[e2e] PASS: bootstrap/init, admin login, users/roles CRUD, permission enforcement, password reset/change, cookie-auth, schedule edit path, and audit checks succeeded."
