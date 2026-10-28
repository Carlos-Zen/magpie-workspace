# Security notes

This project is a deployment pattern, not a security boundary. Read this before
exposing it to the internet.

## Default posture

- The Magpie app is `share = "owner"` by default. A Coder login is required.
- `CODER_ALLOW_PUBLIC_PATH_APPS=false` by default.
- Magpie's web UI is protected by `MAGPIE_WEB_KEY`; the API is protected by a
  gateway key.
- Each workspace has its own provider configuration, home volume and keys.

## Public Magpie URLs

Setting `magpie_share = public` and
`CODER_ALLOW_PUBLIC_PATH_APPS=true` makes the keyed URL reachable without a
Coder login. This is convenient for external API clients, but:

- anyone with the keyed web URL can manage Magpie and see its provider keys;
- Coder path apps that can be publicly shared may act as the workspace owner
  against the Coder API;
- a path app is served from the same origin as Coder, so an app-level XSS would
  be more serious than a separate-subdomain deployment.

Prefer a separate-subdomain app or a reverse proxy in front for production.
If you do not need unauthenticated access, keep the default.

## Docker socket

Coder needs `/var/run/docker.sock` to create workspace containers. That is
root-equivalent access on the host. Run the stack only on a host you control,
and do not give workspace users Docker socket access.

## Secrets

- Never commit `.env`.
- Replace the example admin password and PostgreSQL password.
- The generated web/gateway keys are derived from owner/workspace and are
  **not high-entropy secrets**. Treat them as credentials.
- Put Coder behind TLS. Do not expose plain HTTP on the public internet.
- Back up the Coder/PostgreSQL volumes encrypted.

## Accounts and provider terms

- Each person must use their own provider accounts and credentials.
- Do not pool, resell or share subscription accounts through this project.
- Isolation reduces accidental credential mixing and shared-relay patterns; it
  does **not** guarantee that a provider will not enforce its terms.
- Follow the provider's terms of service and usage policies.

## Rotating keys

Keys are computed in `template/main.tf`. To rotate them, change the key format
there and update/recreate workspaces. Existing Magpie configurations remain in
the workspace volume; remove `~/.config/magpie` if you need a clean reset.

## Logs

Magpie and Coder can contain prompt metadata, provider identifiers and keys.
Restrict access to the host, Docker logs and Coder's database. Do not ship logs
to a third party without reviewing them.
