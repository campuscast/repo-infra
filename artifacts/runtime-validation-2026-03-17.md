# Runtime Validation Snapshot (2026-03-17)

Stack and scripts were executed against running local Docker Compose services.

## Credentials source

- Admin account: `admin@campuscast.local`
- Password set via: `docker compose run --rm --no-deps ... auth-iam node dist/bootstrap/create-first-admin.js`
- Bootstrap mode: `AUTH_BOOTSTRAP_ADMIN_RESET_PASSWORD=true`

## Smoke

- Command:
  - `AUTH_BOOTSTRAP_ADMIN_EMAIL=admin@campuscast.local AUTH_BOOTSTRAP_ADMIN_PASSWORD='<redacted>' AUTH_BOOTSTRAP_ADMIN_ROLE=admin BASE_URL=http://localhost:3000 scripts/smoke-bootstrap.sh`
- Result: `PASS`
- Log: `artifacts/smoke-bootstrap-2026-03-17.log`

## IAM E2E

- Command:
  - `AUTH_BOOTSTRAP_ADMIN_EMAIL=admin@campuscast.local AUTH_BOOTSTRAP_ADMIN_PASSWORD='<redacted>' BASE_URL=http://localhost:3000 scripts/e2e-iam.sh`
- Result: `PASS`
- Log: `artifacts/e2e-iam-2026-03-17.log`

## Covered runtime checks

- init-state bootstrap
- login + cookie `/me`
- users CRUD + roles CRUD
- permission enforcement (403)
- zone-scoped RBAC allow/deny
- password reset + password change
- MFA TOTP setup/verify/enable/login challenge/disable
- audit side effects
- schedule happy path (create/lock/save/list)
- logout/session invalidation (smoke)
