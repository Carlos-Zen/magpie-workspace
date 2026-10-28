#!/bin/bash
# Reverse proxy for Magpie web on Coder path apps.
#
# Coder serves path apps under /@owner/workspace.main/apps/<slug>/. Magpie
# redirects "/" to "/" after exchanging ?k=<web key> for a cookie, which would
# otherwise escape the app path. This nginx layer rewrites that redirect (and
# root-relative HTML URLs) back under the Coder app base path.
set -euo pipefail

export HOME="${HOME:-/home/coder}"
: "${CODER_APP_BASE:?CODER_APP_BASE is required}"
MAGPIE_PUBLIC_ORIGIN="${MAGPIE_PUBLIC_ORIGIN:-https://coder.example.com}"
RUNTIME_DIR="$HOME/workspace/.magpie-runtime"
mkdir -p "$RUNTIME_DIR/client_body" "$RUNTIME_DIR/proxy" \
  "$RUNTIME_DIR/fastcgi" "$RUNTIME_DIR/uwsgi" "$RUNTIME_DIR/scgi"

CONF="$RUNTIME_DIR/nginx.conf"
cat >"$CONF" <<EOF
pid $RUNTIME_DIR/nginx.pid;
error_log $RUNTIME_DIR/nginx-error.log warn;
events { worker_connections 256; }
http {
  access_log off;
  client_body_temp_path $RUNTIME_DIR/client_body;
  proxy_temp_path $RUNTIME_DIR/proxy;
  fastcgi_temp_path $RUNTIME_DIR/fastcgi;
  uwsgi_temp_path $RUNTIME_DIR/uwsgi;
  scgi_temp_path $RUNTIME_DIR/scgi;
  server {
    listen 127.0.0.1:3440;
    server_name _;
    location / {
      proxy_pass http://127.0.0.1:3430;
      proxy_http_version 1.1;
      proxy_set_header Host \$host;
      proxy_set_header Accept-Encoding "";
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_redirect / $MAGPIE_PUBLIC_ORIGIN$CODER_APP_BASE;
      sub_filter_types text/html application/javascript text/javascript application/json;
      # Force a fresh asset URL so Cloudflare's 4h JS cache cannot keep the
      # pre-rewrite bundle; nginx then prefixes Magpie's absolute /api/ paths.
      sub_filter '?v=' '?v=8&';
      sub_filter '"/api/' '"${CODER_APP_BASE}api/';
      sub_filter '\`/api/' '\`${CODER_APP_BASE}api/';
      sub_filter '"/api"' '"${CODER_APP_BASE}api"';
      sub_filter "'/api/" "'${CODER_APP_BASE}api/";
      sub_filter 'href="/' 'href="${CODER_APP_BASE}';
      sub_filter 'src="/' 'src="${CODER_APP_BASE}';
      sub_filter_once off;
    }
  }
}
EOF
/usr/sbin/nginx -t -c "$CONF" -p "$RUNTIME_DIR" >/dev/null 2>&1

for _ in $(seq 1 10); do
  code=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:3440/ 2>/dev/null || true)
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    exit 0
  fi
  sleep 1
done

/usr/sbin/nginx -c "$CONF" -p "$RUNTIME_DIR" -g 'daemon off;' \
  >"$RUNTIME_DIR/nginx.log" 2>&1 &

for _ in $(seq 1 20); do
  code=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:3440/ 2>/dev/null || true)
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    exit 0
  fi
  sleep 1
done

echo "magpie proxy did not start on port 3440" >&2
tail -80 "$RUNTIME_DIR/nginx-error.log" >&2 || true
exit 1
