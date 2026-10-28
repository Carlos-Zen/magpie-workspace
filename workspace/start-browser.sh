#!/bin/bash
# Start the isolated X11 desktop + Chromium for the Coder Browser app.
set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"
export HOME="${HOME:-/home/coder}"
RUNTIME_DIR="${HOME}/workspace/.browser-runtime"
PROFILE_DIR="${HOME}/workspace/.chromium-profile"
mkdir -p "$RUNTIME_DIR" "$PROFILE_DIR"

if ! pgrep -u "$(id -u)" -x Xvfb >/dev/null 2>&1; then
  Xvfb "$DISPLAY" -screen 0 1920x1080x24 -ac -nolisten tcp \
    >"$RUNTIME_DIR/xvfb.log" 2>&1 &
fi
for _ in $(seq 1 30); do
  [ -S "/tmp/.X11-unix/X${DISPLAY#:}" ] && break
  sleep 1
done

if ! pgrep -u "$(id -u)" -x fluxbox >/dev/null 2>&1; then
  fluxbox >"$RUNTIME_DIR/fluxbox.log" 2>&1 &
fi

if ! pgrep -u "$(id -u)" -x x11vnc >/dev/null 2>&1; then
  x11vnc -display "$DISPLAY" -rfbport 5900 -localhost -forever -shared -nopw -xkb \
    >"$RUNTIME_DIR/x11vnc.log" 2>&1 &
fi

if ! curl -fsS http://127.0.0.1:6080/ >/dev/null 2>&1; then
  websockify --web=/usr/share/novnc 6080 localhost:5900 \
    >"$RUNTIME_DIR/websockify.log" 2>&1 &
fi

if ! pgrep -u "$(id -u)" -x chromium >/dev/null 2>&1 \
  || ! DISPLAY="$DISPLAY" xwininfo -root -tree 2>/dev/null | grep -qi '"chromium"'; then
  pkill -u "$(id -u)" chromium || true
  rm -f "$PROFILE_DIR"/SingletonLock "$PROFILE_DIR"/SingletonSocket "$PROFILE_DIR"/SingletonCookie
  chromium \
    --no-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --display="$DISPLAY" \
    --start-maximized \
    --user-data-dir="$PROFILE_DIR" \
    --no-first-run \
    --no-default-browser-check \
    >"$RUNTIME_DIR/chromium.log" 2>&1 &
fi
