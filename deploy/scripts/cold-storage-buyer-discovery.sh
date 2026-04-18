#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=deploy/scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

PROJECT="cold-storage-buyer-discovery"
REMOTE_DIR="/opt/cold-storage-buyer-discovery"
CLONE_URL="https://github.com/Amaresh/cold-storage-buyer-discovery.git"
ENV_DIR="/etc/cold-storage"
ENV_FILE="${ENV_DIR}/cold-storage-buyer-discovery.env"
ENV_TEMPLATE="/opt/cold-storage-ops/deploy/env/cold-storage-buyer-discovery.env.example"
SERVICE_TEMPLATE="/opt/cold-storage-ops/deploy/systemd/cold-storage-buyer-discovery.service"
TIMER_TEMPLATE="/opt/cold-storage-ops/deploy/systemd/cold-storage-buyer-discovery.timer"
SERVICE_FILE="/etc/systemd/system/cold-storage-buyer-discovery.service"
TIMER_FILE="/etc/systemd/system/cold-storage-buyer-discovery.timer"
BACKEND_ENV_FILE="/etc/cold-storage-backend.env"
DEPLOY_REF="${DEPLOY_REF:-}"
ENABLE_TIMER="${ENABLE_TIMER:-false}"

echo "[$PROJECT] Starting deploy..."

ensure_repo "$PROJECT" "$REMOTE_DIR" "$CLONE_URL" "Worker source"
update_repo "$PROJECT" "$REMOTE_DIR" "Worker source" "$DEPLOY_REF"

install -d -m 0755 -o root -g root "$ENV_DIR"
install_if_missing "$ENV_TEMPLATE" "$ENV_FILE" 0640 root root
append_env_if_missing "$ENV_FILE" "BUYER_DISCOVERY_BACKEND_BASE_URL" "http://127.0.0.1:9090"
append_env_if_missing "$ENV_FILE" "BUYER_DISCOVERY_TENANT_ID" "demo-tenant"
append_env_if_missing "$ENV_FILE" "BUYER_DISCOVERY_WAREHOUSE_ID" "guntur-hub"
append_env_if_missing "$ENV_FILE" "BUYER_DISCOVERY_INTERNAL_API_HEADER" "X-API-Key"
append_env_if_missing "$ENV_FILE" "BUYER_DISCOVERY_DISCOVERY_SOURCE" "buyer-discovery-worker"
append_env_if_missing "$ENV_FILE" "BUYER_DISCOVERY_USE_SAMPLE_SNAPSHOTS" "true"

backend_internal_api_key="$(read_env_value "$BACKEND_ENV_FILE" "APP_SECURITY_INTERNAL_API_KEY" || true)"
if [ -n "$backend_internal_api_key" ]; then
    append_env_if_missing "$ENV_FILE" "BUYER_DISCOVERY_INTERNAL_API_KEY" "$backend_internal_api_key"
fi

install_managed_file "$SERVICE_TEMPLATE" "$SERVICE_FILE" 0644 root root
install_managed_file "$TIMER_TEMPLATE" "$TIMER_FILE" 0644 root root

chown -R coldstorage:coldstorage "$REMOTE_DIR"

systemctl daemon-reload
systemctl reset-failed cold-storage-buyer-discovery.service || true
systemctl start cold-storage-buyer-discovery.service

if [ "$ENABLE_TIMER" = "true" ]; then
    systemctl enable --now cold-storage-buyer-discovery.timer
    echo "[$PROJECT] Timer enabled"
else
    systemctl disable --now cold-storage-buyer-discovery.timer >/dev/null 2>&1 || true
    echo "[$PROJECT] Timer installed but left disabled"
fi

echo "[$PROJECT] ✅ Deploy complete"
