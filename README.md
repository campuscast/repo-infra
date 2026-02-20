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

| Service           | Port | Internal               |
| ----------------- | ---- | ---------------------- |
| API Gateway       | 3000 | api-gateway:3000       |
| Auth & IAM        | -    | auth-iam:3001          |
| Zone & Policy     | -    | zone-policy:3002       |
| Device Management | -    | device-management:3003 |
| Content Service   | -    | content-service:3004   |
| Schedule Service  | -    | schedule-service:3005  |
| Sync Service (WS) | 3006 | sync-service:3006      |
| Validation QA     | -    | validation-qa:3007     |
| Signing KMS       | 3008 | signing-kms:3008       |
| Audit Service     | -    | audit-service:3009     |

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
