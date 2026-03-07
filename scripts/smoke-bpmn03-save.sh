#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost}"
SCHEDULE_ID="${SCHEDULE_ID:-test}"
AUTH_HEADER="${AUTH_HEADER:-Authorization: Bearer dummy}"
BODY='{"slots":[],"lock_token":"t"}'

tmp_file="$(mktemp)"
status_code="$(
  curl -sS -o "${tmp_file}" -w "%{http_code}" \
    -X POST "${BASE_URL}/api/v1/schedules/${SCHEDULE_ID}/save" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "${BODY}"
)"

echo "POST ${BASE_URL}/api/v1/schedules/${SCHEDULE_ID}/save -> HTTP ${status_code}"
echo "Body:"
cat "${tmp_file}"
echo
rm -f "${tmp_file}"

if [[ "${status_code}" == "404" ]]; then
  echo "FAIL: route is missing (HTTP 404)"
  exit 1
fi

echo "PASS: route exists and is proxied (non-404)"
