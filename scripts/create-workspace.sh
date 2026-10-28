#!/usr/bin/env bash
set -euo pipefail

SPEC="${1:-}"
if [[ -z "$SPEC" ]]; then
  echo "usage: $0 <owner/workspace>    e.g. $0 alice/dev" >&2
  exit 1
fi

coder create "$SPEC" --template magpie-workspace --yes
