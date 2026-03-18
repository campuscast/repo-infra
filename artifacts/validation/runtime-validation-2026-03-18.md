# Runtime Validation Report — 2026-03-18

## Smoke Test (smoke-bootstrap.sh) — PASS

| Step | Backlog Criterion | Result |
|------|-------------------|--------|
| Gateway health check | DEP-07 | PASS |
| Migration tables exist (auth_db, zone_policy_db, device_db, content_db, schedule_db, audit_db) | DEP-07 | PASS |
| Migration rows present | DEP-07 | PASS |
| Admin user exists | DEP-07 | PASS |
| Admin login (POST /api/v1/auth/login) | DEP-07, IAM | PASS |
| Bearer token /me returns email, role, permissions | DEP-07, IAM | PASS |
| Cookie-based /me flow | SEC-03 (CSRF cookie) | PASS |
| System init-state = true | DEP-07 | PASS |
| Users list API | IAM | PASS |
| Roles list API (includes super_admin) | IAM | PASS |
| Zone/schedule/device read paths | DEP-07 | PASS |
| Unauthenticated /users returns 401 | SEC | PASS |
| Logout invalidates cookie session | SEC | PASS |

## E2E IAM Test (e2e-iam.sh) — PASS

| Step | Backlog Criterion | Result |
|------|-------------------|--------|
| Init-state check | VAL-02 | PASS |
| Admin login + cookie flow | SEC-03, DEP-07 | PASS |
| Role create | IAM, VAL-02 | PASS |
| Role update | IAM, VAL-02 | PASS |
| User create | IAM, VAL-02 | PASS |
| User get by ID | IAM, VAL-02 | PASS |
| User update | IAM, VAL-02 | PASS |
| Role assign/remove | IAM, VAL-02 | PASS |
| Password reset (admin resets user) | IAM, UI-IAM-01 | PASS |
| User login after reset | IAM | PASS |
| CSRF cookie present | SEC-03 | PASS |
| Password change (user changes own) | IAM, UI-IAM-01 | PASS |
| Permission enforcement (403 for non-admin) | IAM, SEC | PASS |
| Schedule create | SCH, VAL-02 | PASS |
| Schedule lock/save/unlock | SCH, VAL-02 | PASS |
| Schedule ops (add/move/remove via lock/save fallback) | SCH, VAL-02 | PASS |
| Schedule validate | SCH, VAL-02 | PASS |
| Zone-scoped RBAC: create second zone | IAM-05 | PASS |
| Zone-scoped RBAC: assign zone to user | IAM-05 | PASS |
| Zone-scoped RBAC: allow access to assigned zone | IAM-05 | PASS |
| Zone-scoped RBAC: deny access to unassigned zone (403) | IAM-05 | PASS |
| Zone-scoped RBAC: deny lock on unassigned zone schedule (403) | IAM-05 | PASS |
| MFA TOTP: setup returns secret | IAM-06 | PASS |
| MFA TOTP: verify code | IAM-06 | PASS |
| MFA TOTP: enable MFA | IAM-06 | PASS |
| MFA TOTP: login returns mfa_required challenge | IAM-06 | PASS |
| MFA TOTP: login-verify with TOTP code | IAM-06 | PASS |
| MFA TOTP: disable MFA | IAM-06 | PASS |
| Audit: user_created event recorded | Audit, VAL-02 | PASS |
| Audit: role_created event recorded | Audit, VAL-02 | PASS |
| Audit: password_changed event recorded | Audit, VAL-02 | PASS |
| User deactivation | IAM, VAL-02 | PASS |

## Reproducible Commands

```bash
# Prerequisites: stack must be running (all containers healthy)
# Admin password must be known (set via bootstrap or reset)

# Smoke test
AUTH_BOOTSTRAP_ADMIN_EMAIL="admin@campuscast.local" \
AUTH_BOOTSTRAP_ADMIN_PASSWORD="<password>" \
bash scripts/smoke-bootstrap.sh

# E2E IAM test
AUTH_BOOTSTRAP_ADMIN_EMAIL="admin@campuscast.local" \
AUTH_BOOTSTRAP_ADMIN_PASSWORD="<password>" \
bash scripts/e2e-iam.sh

# CI target (runs both)
AUTH_BOOTSTRAP_ADMIN_EMAIL="admin@campuscast.local" \
AUTH_BOOTSTRAP_ADMIN_PASSWORD="<password>" \
make ci-iam-runtime
```

## Notes

- Rate limiting (SEC-04) is in-memory in gateway; restarting gateway clears state
- CRDT ops endpoint requires signature in production mode; e2e uses lock/save fallback
- All tests ran against Docker Compose stack with 20 containers
