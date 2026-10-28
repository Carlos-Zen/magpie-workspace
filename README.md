# magpie-workspace

[English](README.md) | [简体中文](README.zh-CN.md)

**Isolated Claude Code workspaces, one Magpie gateway per developer.**

A small self-hosted reference stack for teams that want a local-like Claude Code
experience without putting every developer behind one shared relay.

Claude Code runs inside a dedicated Docker workspace. Its model traffic goes to a
Magpie gateway running in the same workspace, and then to the provider. The
request leaves from the workspace/server, not from the developer's laptop and not
from a shared multi-tenant relay. Each workspace has its own home volume, Claude
configuration, Magpie configuration, web key and gateway key.

> This is an isolation and deployment pattern, **not a guarantee against account
> enforcement**. Provider terms still apply. Do not use it to share accounts,
> resell access, or circumvent provider limits.

---

## The problem

Claude Code subscriptions are personal. When several people share one relay,
one API key, or one egress identity, a provider can see a confusing mix of
sessions, IPs, machines and quota usage. That is exactly the pattern that makes
accounts look compromised or abusive. Traditional relays also add their own
problems:

- one shared credential pool for everybody;
- one shared IP/egress identity;
- cross-user request logs and data;
- quota collisions and noisy-neighbour failures;
- a central service that becomes a single point of failure.

## The approach

```
Developer browser / VS Code
          |
          | HTTPS (Coder path app, optional Coder login)
          v
+---------------------------------------------------+
|  Coder workspace (one Docker container per person) |
|                                                   |
|  Chromium + noVNC          Claude Code            |
|       :6080                 |                     |
|                             | shim                 |
|                             v                     |
|                   CLAUDE_CODE_ENTRYPOINT=custom   |
|                             |                     |
|                             v                     |
|            Magpie gateway 127.0.0.1:3425          |
|                             |                     |
|            Magpie web/API   :3430                 |
|            nginx path proxy :3440                 |
+-----------------------------|---------------------+
                              |
                              v
                    upstream provider APIs
```

- **Local-like development**: use the browser desktop, terminal, or VS Code
  Remote-SSH.
- **Remote request origin**: Claude Code and Magpie run in the workspace, so the
  provider sees the workspace/server egress, not the developer's laptop.
- **One gateway per workspace**: no shared Magpie relay, no shared provider
  config, no cross-user request log.
- **Independent environments**: separate container, home volume, Claude config,
  Magpie credentials and web/gateway keys per workspace.
- **No account pooling**: every person signs in to their own provider accounts
  and keeps their own credentials.

## Features

- Coder control plane with Docker-based workspaces.
- One isolated workspace per developer, configurable CPU/memory (default 1 CPU / 2 GiB).
- Claude Code `latest` in the workspace.
- `claude` shim that exports `CLAUDE_CODE_ENTRYPOINT=custom` before running the real CLI.
- Per-workspace Magpie web UI + gateway, with persistent config.
- nginx path proxy so Magpie works behind a Coder path app.
- Public/authenticated/owner sharing options for the Magpie app.
- Chromium + Xvfb + noVNC browser, with clipboard bridge.
- Persistent `/home/coder` and `/home/coder/workspace` volumes.
- Docker Compose quick start and Makefile.
- Optional Mutagen local-folder sync helper.

## Requirements

- Linux host with Docker Engine + Docker Compose v2.
- Coder CLI on the operator machine (for template/workspace commands).
- A DNS name and TLS reverse proxy if you want HTTPS (recommended).
- 4 GiB RAM + 2 vCPU for a small test; more for multiple concurrent workspaces.
  Rule of thumb: **2 GiB RAM + 1 vCPU per workspace**, plus host/Coder overhead.

## Quick start

### 1. Clone and configure

```bash
git clone https://github.com/<your-account>/magpie-workspace.git
cd magpie-workspace
cp .env.example .env
$EDITOR .env
```

At minimum set:

```dotenv
POSTGRES_PASSWORD=...
CODER_ACCESS_URL=http://localhost:7080
CODER_ADMIN_USER=admin
CODER_ADMIN_EMAIL=admin@example.com
CODER_ADMIN_PASSWORD=...
```

For a real deployment put a TLS reverse proxy in front and set
`CODER_ACCESS_URL=https://coder.example.com`.

### 2. Start Coder + create the first admin

```bash
make up
make admin
```

The admin password is read from `.env`; it is never printed.

### 3. Install the Coder CLI and log in

```bash
# macOS
brew install coder
# Linux
curl -fsSL https://coder.com/install.sh | sh

coder login http://localhost:7080
# or: coder login https://coder.example.com
```

### 4. Build the workspace image and push the template

```bash
make image      # builds coder-workspace:latest and verifies Claude/Magpie
make template   # pushes the magpie-workspace template
```

`make image` pulls the latest Magpie image, installs the latest Claude Code,
creates `/usr/local/bin/claude-real`, and installs the shim at
`/usr/local/bin/claude`.

### 5. Create a user and a workspace

```bash
make user USER=alice EMAIL=alice@example.com
make workspace SPEC=alice/dev
```

`make user` asks for the password interactively; Coder users are dormant until
activated, and the script activates the new user.

Then open Coder, start `alice/dev`, and open the **Magpie** app. The workspace
metadata contains:

- `magpie_url` — the keyed web UI URL;
- `magpie_gateway_url` — `<access-url>/@alice/dev.main/apps/magpie/v1`;
- `magpie_gateway_key` — the gateway credential.

The web URL has this shape:

```text
https://coder.example.com/@alice/dev.main/apps/magpie/?k=magpie-alice-dev-web
```

The gateway:

```text
Base URL: https://coder.example.com/@alice/dev.main/apps/magpie/v1
API key:  magpie-alice-dev-gw
```

> Opening the app without `?k=` returns 401 by design. Use the keyed URL from
> the workspace metadata.

### 6. Open the workspace

- **Terminal**: Coder's web terminal, or `coder ssh alice/dev`.
- **Browser desktop**: the Browser app.
- **VS Code**: `coder config-ssh`, then connect to `alice-dev.coder` and open
  `/home/coder/workspace`.

## Public vs. authenticated Magpie

By default `template/main.tf` sets:

```hcl
variable "magpie_share" {
  default = "owner"
}
```

So the Magpie path app is reachable over the network but requires a Coder login.
This is the safe default.

To make the keyed Magpie URL reachable **without a Coder login**:

1. In `template/main.tf`, change the default to `"public"`.
2. Set `CODER_ALLOW_PUBLIC_PATH_APPS=true` in `.env`.
3. `docker compose up -d` (recreate Coder) and `make template`.
4. Re-create or update workspaces so the app sharing level changes.

Path apps that are publicly shareable can reach the Coder API as the workspace
owner; read [`docs/security.md`](docs/security.md) before enabling this.

## Using Magpie

1. Open the keyed `magpie_url` from the workspace metadata.
2. Add a provider or sign in to a subscription in the Magpie UI.
3. Add a **gateway key** for clients that are outside the workspace.
4. Point clients at `magpie_gateway_url` with `magpie_gateway_key`.
5. Inside the workspace, Claude Code can be wired by Magpie's Agents page or CLI.

Useful CLI checks inside a workspace:

```bash
magpie --version
magpie gateway-key list
cat ~/.config/magpie/coder-gateway-key
```

A provider request path is:

```text
Claude Code -> 127.0.0.1:3425 -> Magpie -> provider
```

The workspace, not a shared relay, is the request origin.

## Claude Code shim

The image deliberately keeps the real CLI at `/usr/local/bin/claude-real` and
puts a shim at the normal path:

```sh
#!/bin/sh
export CLAUDE_CODE_ENTRYPOINT=custom
exec /usr/local/bin/claude-real "$@"
```

Verify:

```bash
command -v claude
sed -n '1,5p' /usr/local/bin/claude
claude --version
claude-real --version
```

To change the entrypoint value, edit `workspace/Dockerfile` and rebuild.

## Configuration

### `.env`

| Variable | Purpose |
|---|---|
| `POSTGRES_PASSWORD` | Coder PostgreSQL password |
| `CODER_ACCESS_URL` | URL users open; use HTTPS in production |
| `CODER_ADMIN_USER` / `EMAIL` / `PASSWORD` | first admin created by `make admin` |
| `CODER_ALLOW_PUBLIC_PATH_APPS` | enables unauthenticated path-app sharing; default false |

### Template variables

| Variable | Default | Purpose |
|---|---|---|
| `workspace_cpus` | `1` | CPU limit per workspace |
| `workspace_memory_mb` | `2048` | memory limit per workspace (MiB) |
| `magpie_share` | `owner` | `owner`, `authenticated`, or `public` |

### Keys

Web/gateway keys are derived from owner + workspace and are stable across
restarts:

```text
magpie-<owner>-<workspace>-web
magpie-<owner>-<workspace>-gw
```

They are not high-entropy secrets. The gateway key is visible in workspace
metadata and in `~/.config/magpie/coder-gateway-key`. Treat the keyed URL as a
credential. See [`docs/security.md`](docs/security.md).

## Isolation model

| Resource | Isolation |
|---|---|
| Workspace container | one per user/workspace |
| `/home/coder` | dedicated Docker volume |
| `/home/coder/workspace` | dedicated Docker volume |
| Claude config | inside the workspace (`CLAUDE_CONFIG_DIR`) |
| Magpie config/keys | inside the workspace (`~/.config/magpie`) |
| Chromium profile | inside the workspace |
| Provider accounts | each user signs in to their own |

The Coder control plane and Docker host are shared infrastructure. If the host
is compromised, workspace isolation is not a security boundary.

## Operations

```bash
make logs       # follow Coder logs
make down       # stop, keep volumes
make clean      # stop and delete volumes (DESTRUCTIVE)
```

Back up the Coder data volume and PostgreSQL volume before upgrades. Upgrade the
workspace image with `make image`; **new** workspaces use the latest image.
Existing workspaces must be stopped/started or updated.

## File sync and editors

- **Coder Desktop File Sync** — GUI two-way sync.
- **rsync / scp** over Coder SSH.
- **Mutagen** — optional helper in `scripts/coder-sync.sh`.
- **VS Code Remote-SSH** — `coder config-ssh`, connect to
  `<workspace>.coder`, open `/home/coder/workspace`.

## Troubleshooting

- **Magpie page loads but rows are skeletons** — open the keyed URL, hard-refresh,
  and make sure the workspace uses the latest image. See
  [`docs/troubleshooting.md`](docs/troubleshooting.md).
- **401 from Magpie** — missing `?k=` or wrong web key.
- **Coder app 502 / unreachable** — check `docker compose ps`, Coder logs,
  workspace health, and Docker socket permissions.
- **Template push fails** — log in with `coder login`, and make sure the CLI
  points at the same Coder URL.
- **Image has no `claude`** — run `make image` again and check the build output.

## Repository layout

```text
.
├── docker-compose.yml       Coder + PostgreSQL
├── .env.example
├── Makefile
├── scripts/
│   ├── create-admin.sh
│   ├── build-workspace.sh
│   ├── push-template.sh
│   ├── create-workspace.sh
│   └── coder-sync.sh
├── template/main.tf         Coder template
├── workspace/
│   ├── Dockerfile           Claude Code + Magpie + Chromium/noVNC
│   ├── start-browser.sh
│   ├── start-magpie.sh
│   ├── start-magpie-proxy.sh
│   ├── novnc-bootstrap.js
│   └── patch-novnc-clipboard.py
└── docs/
    ├── security.md
    └── troubleshooting.md
```

## License

MIT. Coder is AGPL-3.0 and Magpie is MIT; the Docker stack pulls their official
images and does not vendor their source. See [`NOTICE`](NOTICE).
