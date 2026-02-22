# repo-infra

Infrastructure configurations for CampusCast Distributed Media CMS.

## Quick Start

```bash
# Start all infrastructure + services
docker-compose up -d

# Start with optional validation-qa service
docker-compose --profile with-validation up -d

# Seed development data
docker exec -i campuscast-postgres psql -U campuscast < scripts/seed.sql

# View services
docker-compose ps
```

## Services Map

| Service           | External Access | Internal               |
| ----------------- | --------------- | ---------------------- |
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
- External API surface is `nginx -> api-gateway` (`/api/*`, `/ws/*`).
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
