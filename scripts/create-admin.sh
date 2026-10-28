#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ -f .env ] || { echo "missing .env; run: cp .env.example .env" >&2; exit 1; }
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${CODER_ADMIN_USER:?set CODER_ADMIN_USER in .env}"
: "${CODER_ADMIN_EMAIL:?set CODER_ADMIN_EMAIL in .env}"
: "${CODER_ADMIN_PASSWORD:?set CODER_ADMIN_PASSWORD in .env}"

docker compose --env-file .env up -d

echo "Waiting for Coder..."
for _ in $(seq 1 60); do
  if curl -fsS "${CODER_ACCESS_URL%/}/healthz" >/dev/null 2>&1 \
    || curl -fsS "http://localhost:7080/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if docker compose --env-file .env exec -T coder /opt/coder server create-admin-user \
  --username "$CODER_ADMIN_USER" \
  --email "$CODER_ADMIN_EMAIL" \
  --password "$CODER_ADMIN_PASSWORD"; then
  echo "Coder admin '$CODER_ADMIN_USER' created."
else
  echo "Could not create admin. It may already exist; otherwise check the stack logs." >&2
fi
