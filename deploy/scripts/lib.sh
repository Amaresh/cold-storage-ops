#!/bin/bash

normalize_github_token() {
    if [ -z "${GITHUB_TOKEN:-}" ]; then
        return
    fi

    GITHUB_TOKEN="$(printf '%s' "$GITHUB_TOKEN" | tr -d '\r\n')"
    export GITHUB_TOKEN
}

run_git_with_optional_token() {
    normalize_github_token

    if [ -z "${GITHUB_TOKEN:-}" ]; then
        git "$@"
        return
    fi

    local askpass_script
    askpass_script="$(mktemp)"
    cat >"$askpass_script" <<'EOF'
#!/bin/sh
case "$1" in
    *Username*) printf '%s\n' 'x-access-token' ;;
    *Password*) printf '%s\n' "$GITHUB_TOKEN" ;;
    *) printf '\n' ;;
esac
EOF
    chmod 700 "$askpass_script"

    GIT_ASKPASS="$askpass_script" GIT_TERMINAL_PROMPT=0 git "$@"
    local status=$?
    rm -f "$askpass_script"
    return "$status"
}

ensure_git_safe_directory() {
    local remote_dir="$1"

    if git config --global --get-all safe.directory 2>/dev/null | grep -Fxq "$remote_dir"; then
        return
    fi

    git config --global --add safe.directory "$remote_dir"
}

ensure_repo() {
    local project="$1"
    local remote_dir="$2"
    local clone_url="$3"
    local target_name="${4:-Repository}"

    if [ -d "$remote_dir/.git" ]; then
        return
    fi

    if [ -e "$remote_dir" ]; then
        local backup_dir="${remote_dir}.pre-git-$(date +%Y%m%d%H%M%S)"
        mv "$remote_dir" "$backup_dir"
        echo "[$project] Existing unmanaged directory moved to $backup_dir"
    fi

    mkdir -p "$(dirname "$remote_dir")"
    run_git_with_optional_token clone "$clone_url" "$remote_dir" --quiet
    ensure_git_safe_directory "$remote_dir"
    echo "[$project] ${target_name} cloned into $remote_dir"
}

update_repo() {
    local project="$1"
    local remote_dir="$2"
    local target_name="${3:-Code}"
    local requested_ref="${4:-}"
    local target_ref=""

    ensure_git_safe_directory "$remote_dir"
    cd "$remote_dir"
    if run_git_with_optional_token fetch origin main --quiet 2>/dev/null; then
        target_ref="origin/main"
    else
        run_git_with_optional_token fetch origin master --quiet
        target_ref="origin/master"
    fi

    if [ -n "$requested_ref" ]; then
        if ! git cat-file -e "${requested_ref}^{commit}" 2>/dev/null; then
            echo "[$project] ❌ Requested ref not found: $requested_ref" >&2
            exit 1
        fi
        git reset --hard "$requested_ref" --quiet
        echo "[$project] ${target_name} updated to $(git rev-parse --short HEAD) (requested $requested_ref)"
    else
        git reset --hard "$target_ref" --quiet
        echo "[$project] ${target_name} updated to $(git rev-parse --short HEAD)"
    fi
}

install_if_missing() {
    local source_path="$1"
    local destination_path="$2"
    local mode="${3:-0644}"
    local owner="${4:-root}"
    local group="${5:-root}"

    if [ -f "$destination_path" ]; then
        return
    fi

    install -D -m "$mode" -o "$owner" -g "$group" "$source_path" "$destination_path"
}

install_managed_file() {
    local source_path="$1"
    local destination_path="$2"
    local mode="${3:-0644}"
    local owner="${4:-root}"
    local group="${5:-root}"

    install -D -m "$mode" -o "$owner" -g "$group" "$source_path" "$destination_path"
}

append_env_if_missing() {
    local file_path="$1"
    local key="$2"
    local value="$3"

    if grep -q "^${key}=" "$file_path" 2>/dev/null; then
        return
    fi

    printf '%s=%s\n' "$key" "$value" >> "$file_path"
}

read_env_value() {
    local file_path="$1"
    local key="$2"
    python3 - "$file_path" "$key" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
key = sys.argv[2]
if not path.exists():
    raise SystemExit(1)
for raw_line in path.read_text().splitlines():
    if not raw_line.startswith(f"{key}="):
        continue
    value = raw_line.split("=", 1)[1].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    print(value)
    break
PY
}

ensure_internal_api_key() {
    local project="$1"
    local env_file="$2"
    local key_name="$3"

    if [ ! -f "$env_file" ]; then
        install -D -m 0600 -o root -g root /dev/null "$env_file"
    fi

    if grep -q "^${key_name}=" "$env_file" 2>/dev/null; then
        echo "[$project] Internal API key already present in $(basename "$env_file")"
        return
    fi

    local generated_key
    generated_key="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
)"
    printf '\n%s=%s\n' "$key_name" "$generated_key" >> "$env_file"
    echo "[$project] Generated ${key_name} in $(basename "$env_file")"
}

wait_for_http_ok() {
    local project="$1"
    local url="$2"
    local attempts="${3:-30}"
    local delay_seconds="${4:-2}"

    for _ in $(seq 1 "$attempts"); do
        if curl -sf "$url" >/dev/null 2>&1; then
            echo "[$project] HTTP check passed: $url"
            return 0
        fi
        sleep "$delay_seconds"
    done

    echo "[$project] ❌ HTTP check failed: $url" >&2
    return 1
}
