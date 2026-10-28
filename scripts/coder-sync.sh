#!/usr/bin/env bash
# Local directory <-> Coder workspace two-way live sync (Mutagen over coder ssh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$ROOT/bin" ]; then export PATH="$ROOT/bin:$PATH"; fi
export MUTAGEN_DATA_DIRECTORY="${MUTAGEN_DATA_DIRECTORY:-$HOME/.coder-sync/mutagen}"
MUTAGEN="${MUTAGEN_BIN:-$ROOT/mutagen}"
if [ ! -x "$MUTAGEN" ] && [ -x "$HOME/coder-tools/mutagen" ]; then MUTAGEN="$HOME/coder-tools/mutagen"; fi
if [ ! -x "$MUTAGEN" ]; then MUTAGEN="$(command -v mutagen || true)"; fi
SSH_ALIAS_SUFFIX=".coder"

usage() {
  cat <<'USAGE'
Usage:
  coder-sync.sh start <workspace> <local-dir> [remote-dir]
  coder-sync.sh status [workspace]
  coder-sync.sh flush <workspace>
  coder-sync.sh stop <workspace>
  coder-sync.sh list

Examples:
  ./coder-sync.sh start alice-dev ~/projects/demo
  # -> syncs ~/projects/demo with /home/coder/workspace/demo
  ./coder-sync.sh status
  ./coder-sync.sh flush alice-dev
  ./coder-sync.sh stop alice-dev

Notes:
  - Requires `coder` CLI logged in and `coder config-ssh` done (this script runs it if needed).
  - Default remote dir is /home/coder/workspace/<basename of local-dir>.
  - Sync mode is two-way-safe: concurrent edits create conflict copies instead of losing data.
  - Mutagen daemon must be running; `start` starts it. Set MUTAGEN_DATA_DIRECTORY to keep sessions in a custom dir.
USAGE
}

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need coder
[ -n "$MUTAGEN" ] && [ -x "$MUTAGEN" ] || { echo "mutagen binary not found. Put it at $ROOT/mutagen, set MUTAGEN_BIN, or install mutagen in PATH." >&2; exit 1; }

ensure_ssh() {
  local ws="$1"
  if ! ssh -o BatchMode=yes -o ConnectTimeout=30 "${ws}${SSH_ALIAS_SUFFIX}" 'true' >/dev/null 2>&1; then
    echo "SSH alias ${ws}${SSH_ALIAS_SUFFIX} not ready; running coder config-ssh..."
    printf 'yes\n' | coder config-ssh >/dev/null 2>&1 || true
    ssh -o BatchMode=yes -o ConnectTimeout=30 "${ws}${SSH_ALIAS_SUFFIX}" 'true' >/dev/null 2>&1 || {
      echo "cannot SSH to ${ws}${SSH_ALIAS_SUFFIX}; run: coder login <your-coder-url> && coder config-ssh" >&2
      exit 1
    }
  fi
}

cmd="${1:-help}"
case "$cmd" in
  start)
    ws="${2:-}"; local_dir="${3:-}"; remote_dir="${4:-}"
    [ -n "$ws" ] && [ -n "$local_dir" ] || { usage; exit 1; }
    [ -d "$local_dir" ] || { echo "local dir not found: $local_dir" >&2; exit 1; }
    local_abs="$(cd "$local_dir" && pwd)"
    remote_dir="${remote_dir:-/home/coder/workspace/$(basename "$local_abs")}"
    ensure_ssh "$ws"
    "$MUTAGEN" daemon start >/dev/null 2>&1 || true
    name="coder-sync-$ws"
    if "$MUTAGEN" sync list 2>/dev/null | grep -q "Name: ${name}"; then
      echo "terminating existing session ${name}"
      "$MUTAGEN" sync terminate "$name" >/dev/null 2>&1 || true
    fi
    "$MUTAGEN" sync create --name="$name" --sync-mode=two-way-safe --ignore-vcs \
      "$local_abs" "coder@${ws}${SSH_ALIAS_SUFFIX}:${remote_dir}"
    echo
    "$MUTAGEN" sync list | sed -n "/Name: ${name}/,/^$/p"
    ;;
  status)
    ws="${2:-}"
    if [ -n "$ws" ]; then
      "$MUTAGEN" sync list | sed -n "/Name: coder-sync-${ws}/,/^$/p"
    else
      "$MUTAGEN" sync list
    fi
    ;;
  flush)
    ws="${2:-}"; [ -n "$ws" ] || { usage; exit 1; }
    "$MUTAGEN" sync flush "coder-sync-$ws"
    ;;
  stop)
    ws="${2:-}"; [ -n "$ws" ] || { usage; exit 1; }
    "$MUTAGEN" sync terminate "coder-sync-$ws"
    ;;
  list)
    "$MUTAGEN" sync list
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage; exit 1
    ;;
esac
