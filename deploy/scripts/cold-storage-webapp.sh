#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

PROJECT="cold-storage-webapp"
REMOTE_DIR="/opt/cold-storage-webapp-src"
CLONE_URL="https://github.com/Amaresh/cold-storage-webapp.git"
RUNTIME_DIR="/srv/cold-storage-webapp"
SERVICE_NAME="cold-storage-webapp.service"
ENV_FILE="/etc/cold-storage/cold-storage-webapp.env"
DEPLOY_REF="${DEPLOY_REF:-}"

echo "[$PROJECT] Starting deploy..."

ensure_repo "$PROJECT" "$REMOTE_DIR" "$CLONE_URL" "Webapp source"
update_repo "$PROJECT" "$REMOTE_DIR" "Webapp source" "$DEPLOY_REF"

cd "$REMOTE_DIR"

echo "[$PROJECT] Installing dependencies..."
npm ci

echo "[$PROJECT] Running quality checks..."
npm run lint
npm run typecheck
npm run test:unit
npm run test:component

echo "[$PROJECT] Building..."
npm run build

install -d -m 0755 "$RUNTIME_DIR"
rsync -av --delete "$REMOTE_DIR/.next/" "$RUNTIME_DIR/.next/"
rsync -av --delete "$REMOTE_DIR/public/" "$RUNTIME_DIR/public/"
cp "$REMOTE_DIR/package.json" "$RUNTIME_DIR/"
rsync -av --delete "$REMOTE_DIR/node_modules/" "$RUNTIME_DIR/node_modules/"

install -d -m 0755 "/etc/cold-storage"
install -D -m 0600 "$SCRIPT_DIR/../env/cold-storage-webapp.env.example" "$ENV_FILE"

COLD_STORAGE_API_BASE_URL="${COLD_STORAGE_API_BASE_URL:-http://206.189.141.91:9090/}"

if ! grep -q "^COLD_STORAGE_API_BASE_URL=" "$ENV_FILE" 2>/dev/null; then
  echo "COLD_STORAGE_API_BASE_URL=${COLD_STORAGE_API_BASE_URL}" >> "$ENV_FILE"
fi

if ! grep -q "^NODE_ENV=" "$ENV_FILE" 2>/dev/null; then
  echo "NODE_ENV=production" >> "$ENV_FILE"
fi

install_managed_file "$SCRIPT_DIR/../systemd/cold-storage-webapp.service" "/etc/systemd/system/${SERVICE_NAME}" 0644

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

wait_for_http_ok "$PROJECT" "http://localhost:3000/healthz"

NGINX_CONF_SRC="$SCRIPT_DIR/../nginx/cold-storage-webapp.conf"
NGINX_CONF_DST="/etc/nginx/sites-available/cold-storage-webapp.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/cold-storage-webapp.conf"

if [ -f "$NGINX_CONF_SRC" ]; then
  install_managed_file "$NGINX_CONF_SRC" "$NGINX_CONF_DST" 0644
  if [ ! -L "$NGINX_ENABLED" ] && [ ! -f "$NGINX_ENABLED" ]; then
    ln -s "$NGINX_CONF_DST" "$NGINX_ENABLED"
  fi
  nginx -t && systemctl reload nginx
fi

wait_for_http_ok "$PROJECT" "http://206.189.141.91/healthz"

echo "[$PROJECT] Deploy complete"
