#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-campuscast}"
COMPOSE_FILE="${COMPOSE_FILE:-${ROOT_DIR}/compose.yaml}"

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  echo "[stack] Docker Compose not found. Install Docker Desktop Compose plugin or docker-compose binary." >&2
  exit 1
fi

compose() {
  "${COMPOSE_CMD[@]}" --project-name "${PROJECT_NAME}" -f "${COMPOSE_FILE}" "$@"
}

usage() {
  cat <<'EOF'
Usage: ./scripts/stack.sh <command>

Commands:
  up        Build and start the full stack in background
  bootstrap Install/init flow: up + first admin + smoke checks
  start     Start existing stopped containers
  stop      Stop running containers
  down      Stop and remove containers and orphans
  rebuild   Rebuild images from scratch and start stack
  smoke     Run install/bootstrap smoke checks against running stack
  ps        Show stack services state
  logs      Follow logs (all services)
  config    Validate/render Compose config
EOF
}

cmd="${1:-}"

case "${cmd}" in
  up)
    compose up -d --build --remove-orphans
    ;;
  bootstrap)
    shift
    "${ROOT_DIR}/scripts/bootstrap.sh" "$@"
    ;;
  start)
    compose start
    ;;
  stop)
    compose stop
    ;;
  down)
    compose down --remove-orphans
    ;;
  rebuild)
    compose down --remove-orphans
    compose build --no-cache
    compose up -d --remove-orphans
    ;;
  smoke)
    shift
    "${ROOT_DIR}/scripts/smoke-bootstrap.sh" "$@"
    ;;
  ps)
    compose ps
    ;;
  logs)
    compose logs -f --tail=200
    ;;
  config)
    compose config
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    echo "[stack] Unknown command: ${cmd}" >&2
    usage
    exit 2
    ;;
esac
