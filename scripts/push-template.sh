#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v coder >/dev/null 2>&1; then
  echo "coder CLI not found. Install it, then run: coder login <your-coder-url>" >&2
  exit 1
fi

coder templates push magpie-workspace --directory "$ROOT/template" --yes
