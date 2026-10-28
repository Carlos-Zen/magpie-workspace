#!/usr/bin/env bash
set -euo pipefail

USERNAME="${1:-}"
EMAIL="${2:-}"

if [[ -z "$USERNAME" || -z "$EMAIL" ]]; then
  echo "usage: $0 <username> <email>" >&2
  echo "The script asks for the password interactively." >&2
  exit 1
fi

read -rsp "Password for ${USERNAME}: " PASSWORD
echo
if [[ -z "$PASSWORD" ]]; then
  echo "empty password" >&2
  exit 1
fi

coder users create \
  --username "$USERNAME" \
  --email "$EMAIL" \
  --password "$PASSWORD" \
  --login-type password \
  -O coder

# New Coder users are dormant until activated.
printf 'yes\n' | coder users activate "$USERNAME" || true
echo "User ${USERNAME} is ready. Create a workspace with:"
echo "  make workspace SPEC=${USERNAME}/dev"
