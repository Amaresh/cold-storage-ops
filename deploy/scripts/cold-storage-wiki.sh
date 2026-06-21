#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

PROJECT="cold-storage-wiki"
REMOTE_DIR="/opt/cold-storage-wiki-src"
CLONE_URL="https://github.com/Amaresh/cold-storage-wiki.git"
PUBLISH_DIR="/var/www/cold-storage-wiki/current"
DEPLOY_REF="${DEPLOY_REF:-}"

echo "[$PROJECT] Starting deploy..."

ensure_repo "$PROJECT" "$REMOTE_DIR" "$CLONE_URL" "Wiki source"
update_repo "$PROJECT" "$REMOTE_DIR" "Wiki source" "$DEPLOY_REF"

NODE22_BIN="$(npx -y node@22.14.0 -p 'process.execPath')"
NPM22_BIN="$(dirname "$NODE22_BIN")/npm"

cd "$REMOTE_DIR"

echo "[$PROJECT] Installing dependencies (Node $( "$NODE22_BIN" --version ))..."
"$NPM22_BIN" ci

echo "[$PROJECT] Running quality gate..."
"$NPM22_BIN" run qa

install -d -m 0755 "$(dirname "$PUBLISH_DIR")"
install -d -m 0755 "$PUBLISH_DIR"

echo "[$PROJECT] Publishing static site to $PUBLISH_DIR..."
rsync -av --delete "$REMOTE_DIR/dist/" "$PUBLISH_DIR/"

NGINX_CONF_SRC="$SCRIPT_DIR/../nginx/cold-storage-wiki.conf"
NGINX_CONF_DST="/etc/nginx/sites-available/cold-storage-wiki.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/cold-storage-wiki.conf"

if [ -f "$NGINX_CONF_SRC" ]; then
  install_managed_file "$NGINX_CONF_SRC" "$NGINX_CONF_DST" 0644
  if [ ! -L "$NGINX_ENABLED" ] && [ ! -f "$NGINX_ENABLED" ]; then
    ln -s "$NGINX_CONF_DST" "$NGINX_ENABLED"
  fi
  nginx -t && systemctl reload nginx
fi

wait_for_http_ok "$PROJECT" "http://127.0.0.1:8094/"

if ! curl -sf "http://127.0.0.1:8094/accounting/" >/dev/null 2>&1; then
  echo "[$PROJECT] ❌ Accounting hub not reachable after deploy" >&2
  exit 1
fi

echo "[$PROJECT] Deploy complete — http://127.0.0.1:8094/ (public: port 8094 on crawler host)"
