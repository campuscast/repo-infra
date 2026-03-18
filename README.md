# repo-infra

Infrastructure configurations for CampusCast Distributed Media CMS.

## Quick Start

```bash
# Canonical install/init (migrations + first admin + smoke checks)
AUTH_BOOTSTRAP_ADMIN_EMAIL=admin@campuscast.local \
AUTH_BOOTSTRAP_ADMIN_PASSWORD='replace-with-strong-password' \
./scripts/bootstrap.sh --fresh
```

Equivalent Make target:

```bash
AUTH_BOOTSTRAP_ADMIN_EMAIL=admin@campuscast.local \
AUTH_BOOTSTRAP_ADMIN_PASSWORD='replace-with-strong-password' \
make install-init
```

Alternative direct commands:

```bash
# Same flow via stack wrapper
AUTH_BOOTSTRAP_ADMIN_EMAIL=admin@campuscast.local \
AUTH_BOOTSTRAP_ADMIN_PASSWORD='replace-with-strong-password' \
./scripts/stack.sh bootstrap --fresh
```

## Canonical Install/Init Flow

`./scripts/bootstrap.sh` performs:

1. Environment guard checks (required first-admin credentials, no `root/admin` insecure default).
2. Full stack startup with production-like DB mode:
   - migrations enabled (`DB_MIGRATIONS_RUN=true`)
   - schema sync disabled (`DB_SYNCHRONIZE=false`)
3. Install-time first-admin bootstrap through `repo-auth-iam` CLI.
4. Post-check smoke validation (`./scripts/smoke-bootstrap.sh`):
   - schema/migration state across service DBs,
   - admin presence in `auth_db`,
   - auth login + cookie-based `/api/v1/me`,
   - init-state / users / roles / permission enforcement,
   - schedule + device read paths,
   - logout + cookie session invalidation.

Optional IAM/security e2e suite against running stack:

```bash
AUTH_BOOTSTRAP_ADMIN_EMAIL=admin@campuscast.local \
AUTH_BOOTSTRAP_ADMIN_PASSWORD='replace-with-strong-password' \
./scripts/e2e-iam.sh
```

or through stack wrapper:

```bash
AUTH_BOOTSTRAP_ADMIN_EMAIL=admin@campuscast.local \
AUTH_BOOTSTRAP_ADMIN_PASSWORD='replace-with-strong-password' \
./scripts/stack.sh e2e
```

CI-friendly entrypoint (running stack + smoke + IAM e2e):

```bash
AUTH_BOOTSTRAP_ADMIN_EMAIL=admin@campuscast.local \
AUTH_BOOTSTRAP_ADMIN_PASSWORD='replace-with-strong-password' \
make ci-iam-runtime
```

## Smoke Runtime Artifact

Latest local smoke artifact:

- `artifacts/smoke-bootstrap-2026-03-17.log`
- `artifacts/smoke-bootstrap-20260317.summary.md`

Latest local IAM e2e artifact:

- `artifacts/e2e-iam-2026-03-17.log`

Re-run command:

```bash
AUTH_BOOTSTRAP_ADMIN_EMAIL=admin@campuscast.local \
AUTH_BOOTSTRAP_ADMIN_PASSWORD='replace-with-strong-password' \
./scripts/smoke-bootstrap.sh | tee artifacts/smoke-bootstrap-$(date +%Y%m%d-%H%M%S).log
```

```bash
AUTH_BOOTSTRAP_ADMIN_EMAIL=admin@campuscast.local \
AUTH_BOOTSTRAP_ADMIN_PASSWORD='replace-with-strong-password' \
./scripts/e2e-iam.sh | tee artifacts/e2e-iam-$(date +%Y%m%d-%H%M%S).log
```

## E2E Coverage Map (DEP-08 / VAL-02)

`scripts/e2e-iam.sh` step-to-criterion mapping:

| E2E step | Covered criterion |
| -------- | ----------------- |
| `Checking init-state` | bootstrap/init state |
| `Admin login + cookie flow` | login + cookie session flow |
| `Roles CRUD` | roles CRUD |
| `Users CRUD` | users CRUD |
| `Role assign/remove to user` + `Permission enforcement` | permission enforcement |
| `Zone-scoped RBAC enforcement` | zone-level allow/deny server-side checks |
| `MFA TOTP setup/verify/enable/login-challenge/disable flow` | MFA runtime flow (setup/verify/enable/challenge/disable) |
| `Password reset + cookie auth + password change` | change/reset password |
| `Checking audit side-effects` | audit side effects |
| `Schedule fetch/edit happy path` | schedule happy path |
| `Schedule ops path (add/move/remove)` | schedule interactive edit semantics (add/move/delete) |
| `Schedule validate path` | schedule validation path before publish |
| `PASS ...` final assertion | consolidated runtime e2e confirmation |

## Validation Scripts (VAL-03 / VAL-04 / VAL-05 / VAL-08)

Reproducible validation entrypoints (running stack required):

```bash
AUTH_BOOTSTRAP_ADMIN_EMAIL=admin@campuscast.local \
AUTH_BOOTSTRAP_ADMIN_PASSWORD='replace-with-strong-password' \
make validation-all
```

Individual targets:

- `make val03` — load profile (100/500/1000 clients)
- `make val04` — fault injection profile (loss/delay/duplicate/reconnect/partition equivalent)
- `make val05` — merge/sync/payload/conflict metrics
- `make val08` — aggregated thesis validation pack

Artifacts are written to `artifacts/validation/` (`.json` + `.md` per run).

## Development Seed Data (Explicit Dev-Only)

`scripts/seed.sql` is no longer part of required install/init flow.

Use it only for local development fixtures:

```bash
docker exec -i campuscast-postgres-1 psql -U campuscast < scripts/seed.sql
```

## Services Map

| Service           | External Access | Internal               |
| ----------------- | --------------- | ---------------------- |
| Web App (Next.js) | via nginx:80/443| web-app:3000           |
| API Gateway       | no direct port  | api-gateway:3000       |
| Auth & IAM        | no direct port  | auth-iam:3001          |
| Zone & Policy     | no direct port  | zone-policy:3002       |
| Device Management | no direct port  | device-management:3003 |
| Content Service   | no direct port  | content-service:3004   |
| Schedule Service  | no direct port  | schedule-service:3005  |
| Sync Service (WS) | no direct port  | sync-service:3006      |
| Validation QA     | no direct port  | validation-qa:3007     |
| Signing KMS       | no direct port  | signing-kms:3008       |
| Audit Service     | no direct port  | audit-service:3009     |

## Security Perimeter

- External ingress is only through `nginx` on ports `80/443`.
- All app services are internal-only on the Docker network and are not exposed via host `ports`.
- External UI/API surface is `nginx -> web-app` (`/`) and `nginx -> api-gateway` (`/api/*`, `/ws/*`).
- Explicit unauthenticated exceptions are only `/health` and `/metrics` (proxied to gateway).

## Infrastructure

| Component  | Port      | Purpose                                        |
| ---------- | --------- | ---------------------------------------------- |
| Nginx      | 80/443    | Reverse proxy, rate limiting, security headers |
| PostgreSQL | 5432      | Primary database                               |
| Redis      | 6379      | Locks, cache, rate limiting, idempotency       |
| MinIO      | 9000/9001 | Object storage (S3-compatible)                 |
| Mosquitto  | 1883      | MQTT broker for player updates                 |
| Prometheus | 9090      | Metrics collection                             |
| Grafana    | 3100      | Dashboards (admin/admin)                       |
| Loki       | 3200      | Log aggregation                                |

## Environment Variables

All services share `REDIS_URL`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `NODE_ENV`.
DB services use `DATABASE_URL`. Content uses `S3_*`. Sync uses `MQTT_BROKER_URL`.

DB install defaults in compose:

- `DB_MIGRATIONS_RUN=true`
- `DB_SYNCHRONIZE=false`

Bootstrap script inputs:

- `AUTH_BOOTSTRAP_ADMIN_EMAIL` (required)
- `AUTH_BOOTSTRAP_ADMIN_PASSWORD` (required)
- `AUTH_BOOTSTRAP_ADMIN_ROLE` (optional, default `admin`)
- `AUTH_BOOTSTRAP_ADMIN_RESET_PASSWORD` (optional, default `false`, can also be set via `--admin-reset-password`)

Legacy startup bootstrap in `auth-iam` remains available only as explicit opt-in:

- `AUTH_BOOTSTRAP_ROOT_ENABLED` (default `false`)
- `AUTH_BOOTSTRAP_ROOT_EMAIL` (required when enabled)
- `AUTH_BOOTSTRAP_ROOT_PASSWORD` (required when enabled)
- `AUTH_BOOTSTRAP_ROOT_ROLE` (default `admin`)
- `AUTH_BOOTSTRAP_ROOT_RESET_PASSWORD` (default `false`)

## Troubleshooting

### Docker Desktop: `unknown flag: --project-name`

If clicking "Start" on the `repo-infra` compose app in Docker Desktop fails with:

`unknown flag: --project-name`

then your `docker` CLI does not resolve the compose plugin correctly.

Use the stack script (it auto-detects working compose CLI):

```bash
./scripts/stack.sh up
```

and check plugin availability:

```bash
docker compose version || docker-compose version
```

If `docker compose version` fails but `docker-compose version` works, use `docker-compose` commands (or the script) for this workspace.
