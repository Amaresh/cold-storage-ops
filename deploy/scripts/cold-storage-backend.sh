#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=deploy/scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

PROJECT="cold-storage-backend"
REMOTE_DIR="/opt/cold-storage-backend-src"
CLONE_URL="https://github.com/Amaresh/cold-storage-backend.git"
RUNTIME_DIR="/srv/cold-storage-backend"
BACKUP_DIR="${RUNTIME_DIR}/backups"
SERVICE_NAME="cold-storage-backend.service"
ENV_FILE="/etc/cold-storage-backend.env"
DEPLOY_REF="${DEPLOY_REF:-}"

echo "[$PROJECT] Starting deploy..."

ensure_repo "$PROJECT" "$REMOTE_DIR" "$CLONE_URL" "Backend source"
update_repo "$PROJECT" "$REMOTE_DIR" "Backend source" "$DEPLOY_REF"
ensure_internal_api_key "$PROJECT" "$ENV_FILE" "APP_SECURITY_INTERNAL_API_KEY"

cd "$REMOTE_DIR"
./mvnw --no-transfer-progress -q -DskipTests package

jar_path="$(find target -maxdepth 1 -type f -name '*.jar' ! -name 'original-*' | sort | tail -n 1)"
if [ -z "$jar_path" ]; then
    echo "[$PROJECT] ❌ Built jar not found in target/" >&2
    exit 1
fi

install -d -o coldstorage -g coldstorage "$BACKUP_DIR"
if [ -f "${RUNTIME_DIR}/app.jar" ]; then
    cp "${RUNTIME_DIR}/app.jar" "${BACKUP_DIR}/app-$(date +%Y%m%d%H%M%S).jar"
fi

install -m 0644 -o coldstorage -g coldstorage "$jar_path" "${RUNTIME_DIR}/app.jar"

systemctl restart "$SERVICE_NAME"
systemctl is-active --quiet "$SERVICE_NAME"
wait_for_http_ok "$PROJECT" "http://localhost:9090/actuator/health"

echo "[$PROJECT] ✅ Deploy complete"

