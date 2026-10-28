# Troubleshooting

## Magpie UI shows skeletons or "not Magpie's response"

Magpie's frontend uses absolute `/api/...` requests. Behind a Coder path app,
those must be rewritten to the app base path. The workspace nginx does this.

Check:

```bash
# Inside the workspace
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3440/
tail -50 ~/workspace/.magpie-runtime/nginx-error.log
grep -n 'sub_filter' ~/workspace/.magpie-runtime/nginx.conf
```

Then open the **keyed** URL from workspace metadata, and hard-refresh. If the
workspace was created before the image was updated, stop/start it so it uses the
current `coder-workspace:latest`.

## Magpie returns 401

- Missing `?k=<web-key>`: use the complete `magpie_url` from metadata.
- Wrong key: the key is `magpie-<owner>-<workspace>-web`.
- Old cookie from another workspace: clear cookies for the Coder host and open
  the keyed URL again.

## Gateway returns 401

Use the gateway key, not the web key:

```bash
curl -H 'Authorization: Bearer magpie-<owner>-<workspace>-gw' \
  https://<coder-host>/@<owner>/<workspace>.main/apps/magpie/v1/models
```

## The Magpie app link opens without a key

Coder's app icon opens the bare app path. Open the keyed URL from the workspace
metadata (`magpie_url`) instead, or bookmark that URL.

## Public app still requires Coder login

- `magpie_share` is still `owner` or `authenticated`.
- `CODER_ALLOW_PUBLIC_PATH_APPS=true` is not set, or Coder was not recreated
  after changing `.env`.

Changing `.env` requires `docker compose up -d` so the Coder container is
recreated. Then update/recreate workspaces so the new app sharing level applies.

## Template push fails

- Run `coder login <your-coder-url>` and make sure it is the same deployment.
- Ensure `make image` ran first; the template refers to
  `coder-workspace:latest` on the Docker host.
- Check that the Coder container can access `/var/run/docker.sock`.

## Workspace image is old

Existing workspaces do not automatically replace their container image. Stop and
start the workspace (or run `coder update`) after `make image`.

## Claude shim

```bash
command -v claude
sed -n '1,5p' /usr/local/bin/claude
claude --version
claude-real --version
```

A wrapper should show:

```sh
#!/bin/sh
export CLAUDE_CODE_ENTRYPOINT=custom
exec /usr/local/bin/claude-real "$@"
```

## Ports inside the workspace

| Port | Service |
|---|---|
| 3425 | Magpie gateway (local agents) |
| 3430 | Magpie web + gateway routes |
| 3440 | nginx path proxy, used by the Coder app |
| 6080 | noVNC |
| 5900 | x11vnc (localhost) |

## Rebuild from scratch

```bash
make down
make clean   # DESTRUCTIVE: deletes Coder DB and workspace volumes
make up
make admin
make image
make template
make workspace SPEC=alice/dev
```
