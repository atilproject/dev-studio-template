#!/usr/bin/env bash
# dev-studio-install-env.sh — Telegram env-provisioning helper
#
# Writes TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID to:
#   - $HOME/.dev-studio-env (with `export ` prefix — sourced by interactive shells)
#   - $HOME/.config/dev-studio/instances/<project>--<role>.env
#     (KEY=VALUE form, no `export` prefix — systemd `EnvironmentFile=` consumes this)
#
# Sister-pattern: dev-studio-install-systemd.sh (header + color/output + preflight + idempotent).
# Per Issue #100 AC1 spec (Sprint 29 W2 gap-closing, env-PROVISIONING affordance).
# Idempotent: skips silently if vars already set with same value.
#
# Env vars:
#   PROJECT_NAME     override project name (default: basename of REPO_ROOT)
#   REPO_ROOT        override repo root (default: auto-detect from script path)
#   HOME             override HOME for testing (default: $HOME — d-test fake-home isolation)
#
# Exit codes:
#   0  success (including no-op idempotent re-run)
#   1  chmod / write failure
#   2  refusal (no CLI args + no env vars + usage to stderr)

set -euo pipefail

# --- paths ---------------------------------------------------------------
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PROJECT_NAME="${PROJECT_NAME:-$(basename "$REPO_ROOT")}"
MAIN_ENV="${HOME:+$HOME/}.dev-studio-env"
INSTANCES_DIR="${HOME:+$HOME/}.config/dev-studio/instances"
ROLES=(orchestrator product-manager architect developer tester)

# --- color/output --------------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    C_GREEN="$(tput setaf 2)"; C_YELLOW="$(tput setaf 3)"; C_RED="$(tput setaf 1)"
    C_BOLD="$(tput bold)"; C_RESET="$(tput sgr0)"
else
    C_GREEN=""; C_YELLOW=""; C_RED=""; C_BOLD=""; C_RESET=""
fi
log() { printf '%s[install-env]%s %s\n' "$C_BOLD" "$C_RESET" "$*"; }
ok()  { printf '%s[install-env]%s %s%s%s\n' "$C_BOLD" "$C_RESET" "$C_GREEN" "$*" "$C_RESET"; }
warn(){ printf '%s[install-env]%s %s%s%s\n' "$C_BOLD" "$C_RESET" "$C_YELLOW" "$*" "$C_RESET"; }
fail(){ printf '%s[install-env]%s %s%s%s\n' "$C_BOLD" "$C_RESET" "$C_RED" "$*" "$C_RESET" >&2; exit 1; }

# --- usage ---------------------------------------------------------------
usage() {
    cat <<EOF >&2
Usage: $0 --telegram-bot-token <TOKEN> --telegram-chat-id <CHAT_ID>
   or:  TELEGRAM_BOT_TOKEN=<TOKEN> TELEGRAM_CHAT_ID=<CHAT_ID> $0

Writes Telegram credentials to:
  - \$HOME/.dev-studio-env                                 (with export prefix)
  - \$HOME/.config/dev-studio/instances/<project>--<role>.env   (KEY=VALUE form)
    where <project> defaults to basename of REPO_ROOT, and <role> ∈
    {orchestrator, product-manager, architect, developer, tester}

Idempotent: skips silently if vars already set with same value.
chmod 600 applied to every file written (per AC1).

Options:
  --telegram-bot-token <TOKEN>   Telegram bot token (also via \$TELEGRAM_BOT_TOKEN)
  --telegram-chat-id  <CHAT_ID>  Telegram chat/group ID (also via \$TELEGRAM_CHAT_ID)
  -h, --help                     show this help

Exit codes: 0 success, 1 chmod/write failure, 2 refusal (no args + no env vars).

Per Issue #100 AC1 spec. Sister-pattern: dev-studio-install-systemd.sh.
EOF
}

# --- CLI parsing ---------------------------------------------------------
BOT_TOKEN=""
CHAT_ID=""
while [ $# -gt 0 ]; do
    case "$1" in
        --telegram-bot-token)
            [ $# -ge 2 ] || { usage; exit 2; }
            BOT_TOKEN="$2"
            shift 2
            ;;
        --telegram-chat-id)
            [ $# -ge 2 ] || { usage; exit 2; }
            CHAT_ID="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            warn "unknown option: $1"
            usage
            exit 2
            ;;
    esac
done

# --- fallback to env vars ------------------------------------------------
if [ -z "$BOT_TOKEN" ]; then
    BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
fi
if [ -z "$CHAT_ID" ]; then
    CHAT_ID="${TELEGRAM_CHAT_ID:-}"
fi

# --- refusal: nothing to write ------------------------------------------
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    warn "refusing to run: --telegram-bot-token and --telegram-chat-id are required (or set TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID env vars)"
    usage
    exit 2
fi

# --- preflight -----------------------------------------------------------
[ -n "${HOME:-}" ] || fail "HOME is not set; cannot determine ~/.dev-studio-env path"
mkdir -p "$INSTANCES_DIR" || fail "cannot create $INSTANCES_DIR"

# --- detect project from existing instance env files ---------------------
# Per AC1 contract: "Detects all 5 instance env files
#   (~/.config/dev-studio/instances/<project>--{...}.env)".
# We scan $INSTANCES_DIR for files matching the pattern *--<role>.env
# (role ∈ ROLES) and extract the <project> prefix. If found, override
# PROJECT_NAME. This lets the script target an existing project the
# operator has already initialized via dev-studio-init.sh.
detect_project_from_instances() {
    local role f matches=()
    for role in "${ROLES[@]}"; do
        matches=()
        for f in "$INSTANCES_DIR"/*--"$role".env; do
            [ -f "$f" ] && matches+=("$f")
        done
        if [ "${#matches[@]}" -gt 0 ]; then
            local base
            base="$(basename "${matches[0]}")"
            echo "${base%--$role.env}"
            return 0
        fi
    done
    return 1
}

if [ -d "$INSTANCES_DIR" ]; then
    DETECTED_PROJECT="$(detect_project_from_instances || true)"
    if [ -n "$DETECTED_PROJECT" ]; then
        log "detected project from existing instance files: $DETECTED_PROJECT"
        PROJECT_NAME="$DETECTED_PROJECT"
    fi
fi

# --- write_var: idempotent append/update with chmod 600 ------------------
# Args: <file> <var-name> <value> <prefix-mode>
#   prefix-mode = "export" → "export VAR=\"VAL\"" (sourced shells)
#                "none"    → "VAR=\"VAL\""          (systemd EnvironmentFile)
# Returns 0 on success (incl. idempotent no-op), 1 on chmod/write failure.
# Critical for TC3 idempotency: if value already matches, returns 0 WITHOUT
# touching the file (mtime preserved).
write_var() {
    local file="$1"
    local var="$2"
    local val="$3"
    local prefix="$4"
    local line
    local wrote=0

    # Ensure file exists (empty)
    [ -f "$file" ] || : > "$file" || return 1

    if [ "$prefix" = "export" ]; then
        line="export ${var}=\"${val}\""
    else
        line="${var}=\"${val}\""
    fi

    # Idempotency: exact-line match (fixed-string) → no-op
    if grep -qxF "$line" "$file" 2>/dev/null; then
        return 0
    fi

    # Update existing line with different value (sed in-place)
    if grep -qE "^${prefix:-}${prefix:+\\ }${var}=" "$file" 2>/dev/null; then
        # Use a different delimiter to avoid issues with / in values
        local esc_val="${val//\//\\/}"
        if [ "$prefix" = "export" ]; then
            sed -i.bak "s|^export ${var}=.*|export ${var}=\"${esc_val}\"|" "$file" || { rm -f "${file}.bak"; return 1; }
        else
            sed -i.bak "s|^${var}=.*|${var}=\"${esc_val}\"|" "$file" || { rm -f "${file}.bak"; return 1; }
        fi
        rm -f "${file}.bak"
        wrote=1
    else
        # Append new line
        printf '%s\n' "$line" >> "$file" || return 1
        wrote=1
    fi

    # chmod 600 only when we actually wrote (preserves TC3 idempotency mtime)
    if [ "$wrote" -eq 1 ]; then
        chmod 600 "$file" || return 1
    fi
    return 0
}

# --- write 6 env files ---------------------------------------------------
log "writing Telegram env for project: $PROJECT_NAME"
log "  main env:   $MAIN_ENV"
log "  instances:  $INSTANCES_DIR/${PROJECT_NAME}--<role>.env (5 roles)"

# Main env: with `export` prefix
write_var "$MAIN_ENV" "TELEGRAM_BOT_TOKEN" "$BOT_TOKEN" "export" \
    || fail "failed to write TELEGRAM_BOT_TOKEN to $MAIN_ENV"
write_var "$MAIN_ENV" "TELEGRAM_CHAT_ID"  "$CHAT_ID"  "export" \
    || fail "failed to write TELEGRAM_CHAT_ID to $MAIN_ENV"

# 5 instance env files: KEY=VALUE form (no export, for systemd EnvironmentFile=)
for role in "${ROLES[@]}"; do
    inst="$INSTANCES_DIR/${PROJECT_NAME}--${role}.env"
    write_var "$inst" "TELEGRAM_BOT_TOKEN" "$BOT_TOKEN" "none" \
        || fail "failed to write TELEGRAM_BOT_TOKEN to $inst"
    write_var "$inst" "TELEGRAM_CHAT_ID"  "$CHAT_ID"  "none" \
        || fail "failed to write TELEGRAM_CHAT_ID to $inst"
done

ok "wrote 6 env files (chmod 600, idempotent on re-run)"
ok "next: source ~/.dev-studio-env in your interactive shell, then re-run scripts/dev-studio-init.sh if systemd units need reloading"
exit 0