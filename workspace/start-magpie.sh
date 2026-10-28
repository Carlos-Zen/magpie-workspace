#!/bin/bash
# Start Magpie web + gateway inside a Coder workspace.
# The browser UI listens on 0.0.0.0:3430 and also serves the gateway routes
# (/v1, /v1beta, /mcp, ...). The gateway itself listens on 0.0.0.0:3425 for
# local agents. MAGPIE_WEB_KEY and MAGPIE_EXTERNAL_KEY are set by the template.
set -euo pipefail

export HOME="${HOME:-/home/coder}"
export MAGPIE_ADDR="${MAGPIE_ADDR:-0.0.0.0:3425}"
RUNTIME_DIR="$HOME/workspace/.magpie-runtime"
CONFIG_DIR="$HOME/.config/magpie"
KEY_FILE="$CONFIG_DIR/coder-gateway-key"
mkdir -p "$RUNTIME_DIR" "$CONFIG_DIR"

if [ -z "${MAGPIE_WEB_KEY:-}" ]; then
  echo "MAGPIE_WEB_KEY is required" >&2
  exit 1
fi
if [ -z "${MAGPIE_EXTERNAL_KEY:-}" ]; then
  echo "MAGPIE_EXTERNAL_KEY is required" >&2
  exit 1
fi

# Make one stable external gateway key per workspace. It is created once and
# kept in the persistent home volume; the plain value is also exposed to the
# owner through the Coder metadata item "magpie_gateway_key".
if [ ! -s "$KEY_FILE" ]; then
  if ! printf '%s\n' "$MAGPIE_EXTERNAL_KEY" | \
      magpie gateway-key add "coder-external" --key - \
      >"$RUNTIME_DIR/gateway-key.log" 2>&1; then
    cat "$RUNTIME_DIR/gateway-key.log" >&2 || true
    exit 1
  fi
  printf '%s\n' "$MAGPIE_EXTERNAL_KEY" >"$KEY_FILE"
  chmod 600 "$KEY_FILE"
fi

if pgrep -u "$(id -u)" -x magpie >/dev/null 2>&1; then
  exit 0
fi

nohup magpie web --addr 0.0.0.0:3430 --no-open \
  >"$RUNTIME_DIR/magpie.log" 2>&1 &

# The page answers 401 without its key, which still proves the listener is up.
for _ in $(seq 1 30); do
  code=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:3430/ 2>/dev/null || true)
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    exit 0
  fi
  sleep 1
done

echo "magpie did not start on port 3430" >&2
tail -80 "$RUNTIME_DIR/magpie.log" >&2 || true
exit 1
