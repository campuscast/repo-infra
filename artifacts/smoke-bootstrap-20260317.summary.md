# Smoke Bootstrap Summary (2026-03-17)

- Stack: `repo-infra/compose.yaml` (running locally via Docker Compose)
- Script: `scripts/smoke-bootstrap.sh`
- Result: `PASS`

Validated runtime paths:

- DB schema + migrations for auth/zone/device/content/schedule/audit
- first admin existence in `auth_db.users`
- `/api/v1/auth/login` returns access token
- `/api/v1/me` with bearer token
- cookie-based `/api/v1/me`
- `/api/v1/system/init-state`
- `/api/v1/users` and `/api/v1/roles`
- unauthenticated `/api/v1/users` returns `401`
- schedule read path (`/api/v1/schedules`)
- device read path (`/api/v1/devices`)
- `/api/v1/auth/logout` invalidates cookie session

Raw log: `artifacts/smoke-bootstrap-20260317.log`
