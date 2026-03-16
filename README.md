# repo-infra

Infrastructure configurations for CampusCast Distributed Media CMS.

## Quick Start

```bash
# Full stack up (build + run)
./scripts/stack.sh up

# Full stack rebuild from scratch
./scripts/stack.sh rebuild

# Seed development data
docker exec -i campuscast-postgres-1 psql -U campuscast < scripts/seed.sql

# View services
./scripts/stack.sh ps
```

Alternative direct commands:

```bash
# Compose v2 canonical file
docker compose -f compose.yaml up -d --build
docker compose -f compose.yaml ps
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

## Initial Root User Bootstrap

`auth-iam` creates a root user on first startup (idempotent):

- login: `root`
- password: `admin`
- role: `admin`

Override for production via env variables in deploy environment:

- `AUTH_BOOTSTRAP_ROOT_ENABLED` (default `true`)
- `AUTH_BOOTSTRAP_ROOT_EMAIL` (default `root`)
- `AUTH_BOOTSTRAP_ROOT_PASSWORD` (default `admin`)
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
