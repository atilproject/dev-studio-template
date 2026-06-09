#!/usr/bin/env bash
# notify.sh — Send notification to Telegram via Bot API
#
# Usage:
#   ./notify.sh "Message text"
#   ./notify.sh -l info "Sprint 1 kicked off"
#   ./notify.sh -l warn "CI flaky on PR #42"
#   ./notify.sh -l error "P0 BLOCKER: Production down"
#
# Env vars required (load from ~/.dev-studio-env):
#   TELEGRAM_BOT_TOKEN — Bot API token from @BotFather
#   TELEGRAM_CHAT_ID   — Target chat ID (user or group)

set -euo pipefail

# Load env if not already in scope
[ -f "$HOME/.dev-studio-env" ] && source "$HOME/.dev-studio-env"

# Defaults
LEVEL="info"
HOSTNAME_TAG="$(hostname)"

# Parse flags
while getopts "l:h" opt; do
  case "$opt" in
    l) LEVEL="$OPTARG" ;;
    h) echo "Usage: $0 [-l info|warn|error] \"message\""; exit 0 ;;
    *) echo "Unknown flag"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

MSG="${1:-}"
if [ -z "$MSG" ]; then
  echo "ERROR: no message provided" >&2
  echo "Usage: $0 [-l info|warn|error] \"message\"" >&2
  exit 2
fi

# Validate env
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
  echo "ERROR: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set" >&2
  echo "Source ~/.dev-studio-env or set them manually" >&2
  exit 1
fi

# Pick emoji based on level
case "$LEVEL" in
  info)  ICON="ℹ️" ;;
  warn)  ICON="⚠️" ;;
  error) ICON="🚨" ;;
  ok)    ICON="✅" ;;
  *)     ICON="🤖" ;;
esac

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"

# Build message (Markdown V2 escaping is fussy; use plain text for safety)
FULL_MSG="${ICON} [${LEVEL^^}] ${HOSTNAME_TAG}
${TIMESTAMP}

${MSG}"

# POST to Telegram
RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${FULL_MSG}" \
  --data-urlencode "disable_web_page_preview=true")

# Check response
if echo "$RESPONSE" | grep -q '"ok":true'; then
  echo "Notification sent: [$LEVEL] $MSG"
  exit 0
else
  echo "ERROR: Telegram API rejected the message" >&2
  echo "$RESPONSE" >&2
  exit 1
fi
