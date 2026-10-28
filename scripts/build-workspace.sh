#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${WORKSPACE_IMAGE:-coder-workspace:latest}"

docker pull ghcr.io/yetone/magpie:latest
docker build --pull -t "$IMAGE" "$ROOT/workspace"

echo "Verifying the Claude shim and Magpie:"
docker run --rm "$IMAGE" sh -lc '
  set -e
  command -v claude
  grep -q "CLAUDE_CODE_ENTRYPOINT=custom" /usr/local/bin/claude
  claude --version
  claude-real --version
  magpie --version
'
