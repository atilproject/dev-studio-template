#!/usr/bin/env bash
# notify.sh — Send notification to Telegram via Bot API (+ optional tmux wake)
#
# Usage:
#   ./notify.sh "Message text"
#   ./notify.sh -l info "Sprint 1 kicked off"
#   ./notify.sh -l warn "CI flaky on PR #42"
#   ./notify.sh -l error "P0 BLOCKER: Production down"
#   ./notify.sh -l info -w -r developer "PR #42 ready for review"
#
# Env vars required (load from ~/.dev-studio-env):
#   TELEGRAM_BOT_TOKEN — Bot API token from @BotFather
#   TELEGRAM_CHAT_ID   — Target chat ID (user or group)
#
# Flags:
#   -l <level>   info | warn | error | ok (default: info)
#   -w           wake target agent via tmux pane (ADR-0033 dual-channel)
#   -r <role>    target agent role when -w is set: orchestrator |
#                product-manager | architect | developer | tester | human
#   -h           show this help
#
# ADR-0033 (Issue #221): -w requires -r. If -w set without -r, exit 2.
# ADR-0033 (Issue #320 + owner directive 2026-06-25): tmux-context callers
# (agents in their tmux panes, or owner in their tmux session) MUST use
# dual-channel. Direct notify.sh from tmux without -w -r silently falls
# through to Telegram-only delivery — peer tmux panes never wake. Force
# explicit -w -r here so the misuse is caught at the tool level.
#
# AC1 Option B (Issue #1055): Telegram-first early-exit SPLIT into two paths.
# Previously, missing TELEGRAM_BOT_TOKEN/CHAT_ID caused `exit 1` BEFORE tmux-wake
# fired, breaking dual-channel doctrine in CI/dev/recovery envs (Issue #1053).
# New behavior: env-missing or API-fail logs WARN/ERROR + marks Telegram failed,
# BUT tmux-wake fires UNCONDITIONALLY (when -w is set), so peer panes still wake.
# Exit-code matrix (AC2):
#   0 = both OK (Telegram sent + tmux wake fired)
#   2 = Telegram failed (env-missing OR API reject) + tmux OK
#   3 = Telegram OK + tmux wake failed (NEW branch — was implicit 1)
#   1 = both failed (legacy total-fail)
# Legacy non-wake mode (no -w): 0/1 backward-compat preserved.
#
# Bypass: set TMUX='' in the calling shell, or run from a non-tmux shell,
# if you genuinely need Telegram-only delivery from a tmux session.

set -euo pipefail

# Load env if not already in scope
[ -f "$HOME/.dev-studio-env" ] && source "$HOME/.dev-studio-env"

# Defaults
LEVEL="info"
WAKE=""
ROLE=""
HOSTNAME_TAG="$(hostname)"

# Parse flags
while getopts "l:wr:h" opt; do
  case "$opt" in
    l) LEVEL="$OPTARG" ;;
    w) WAKE="true" ;;
    r) ROLE="$OPTARG" ;;
    h) echo "Usage: $0 [-l info|warn|error] [-w -r <role>] \"message\""; exit 0 ;;
    *) echo "Unknown flag"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

MSG="${1:-}"
if [ -z "$MSG" ]; then
  echo "ERROR: no message provided" >&2
  echo "Usage: $0 [-l info|warn|error] [-w -r <role>] \"message\"" >&2
  exit 2
fi

# ADR-0033: -w requires -r. If wake mode requested without a role, fail loud.
if [ -n "$WAKE" ] && [ -z "$ROLE" ]; then
  echo "ERROR: -w (wake) requires -r <role> (ADR-0033 dual-channel)" >&2
  echo "       roles: orchestrator | product-manager | architect | developer | tester" >&2
  exit 2
fi

# ADR-0033 enforcement (owner directive 2026-06-25, branch fix/dual-channel-enforcement-for-agents):
# tmux-context callers MUST use dual-channel (-w -r). Direct notify.sh from
# a tmux session without -w -r falls through to Telegram-only and silently
# misses peer tmux panes (the agent-watch loop never wakes). Force explicit
# -w -r here so misuse is caught at the tool level, not at peer non-response.
# Bypass options: (a) pass -w -r explicitly, (b) set TMUX='' in caller env,
# (c) run from a non-tmux shell.
if [ -n "${TMUX:-}" ] && [ -z "$WAKE" ]; then
  echo "ERROR: notify.sh from tmux context requires -w -r <role> (ADR-0033 dual-channel)" >&2
  echo "       TMUX detected: caller is in an agent pane or owner's tmux session." >&2
  echo "       Peer tmux panes will NOT wake without -w -r (silent Telegram-only fallback)." >&2
  echo "       Pass -w -r <role> explicitly so misuse is caught at the tool level." >&2
  echo "       roles: orchestrator | product-manager | architect | developer | tester | human" >&2
  echo "       Bypass (genuine Telegram-only from tmux): set TMUX='' in caller env," >&2
  echo "       or run from a non-tmux shell. See CLAUDE.md §Auto-Ping Hard-Rule." >&2
  exit 2
fi

# Validate env (AC1 Option B: do NOT exit on missing — warn + treat as Telegram fail).
# Telegram failure must not block tmux-wake (Issue #1060 / sister of Issue #1053 —
# Telegram missing in CI/dev/recovery envs must still allow peer pane wake per ADR-0033).
TELEGRAM_RESULT=0  # 0 = sent OK, 1 = failed (env unset OR API reject)
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
  TELEGRAM_RESULT=1
  echo "WARN: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set — Telegram delivery skipped (tmux-wake still fires per ADR-0033 dual-channel)" >&2
  echo "       Source ~/.dev-studio-env or set them manually" >&2
fi

# Pick emoji based on level
case "$LEVEL" in
  info)  ICON="ℹ️" ;;
  warn)  ICON="⚠️" ;;
  error) ICON="🚨" ;;
  ok)    ICON="✅" ;;
  *)     ICON="🤖" ;;
esac

# ADR-0033 / Issue #320 deprecation guard: detect role-like -l arg.
# When invoked as `notify.sh -l <role> ...` (e.g., -l developer), the script
# silently falls through to the default 🤖 emoji and Telegram-only delivery.
# The target agent's tmux pane NEVER wakes. Detect this misuse and emit a
# stderr warning + usage hint. Exit code unchanged (still sends message —
# backward compat per Issue #320 AC2). Owners can grep CI logs for the
# WARNING line to find doctrine violations in peer-ping scripts.
case "$LEVEL" in
  orchestrator|product-manager|architect|developer|tester|human)
    echo "WARNING: -l $LEVEL looks like a ROLE, not a log level." >&2
    echo "         Did you mean: notify.sh -l info -w -r $LEVEL \"...\"?" >&2
    echo "         See CLAUDE.md §Auto-Ping Hard-Rule (ADR-0033 dual-channel)." >&2
    echo "         Message will still be sent (backward compat); fix syntax next time." >&2
    ;;
esac

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"

# Build message (Markdown V2 escaping is fussy; use plain text for safety)
FULL_MSG="${ICON} [${LEVEL^^}] ${HOSTNAME_TAG}
${TIMESTAMP}

${MSG}"

# AC1 Option B: tmux-wake fires UNCONDITIONALLY (when -w is set), BEFORE Telegram
# result handling. Telegram success/failure must NOT block tmux wake (Issue #1053,
# ADR-0033 dual-channel doctrine — peer tmux panes must always wake when -w -r set).
WAKE_RESULT=0  # 0 = success or no-wake-mode, 1 = wake failed
if [ -n "$WAKE" ]; then
  SCRIPT_DIR_NOTIFY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  WAKE_PROMPT="🔔 INBOX (dual-channel wake, notify.sh -w -r ${ROLE}):
[FULL_MSG_BEGIN]
${FULL_MSG}
[FULL_MSG_END]

Lütfen pickup et."
  if "$SCRIPT_DIR_NOTIFY/agent-wake.sh" "$ROLE" "$WAKE_PROMPT" 2>/dev/null; then
    echo "Wake injected: role=$ROLE"
  else
    WAKE_RESULT=1
    echo "ERROR: tmux-wake failed for role=$ROLE" >&2
  fi
fi

# Telegram independent try-block (AC1 Option B): wrapped so Telegram API failures
# cannot block tmux-wake (already fired above). Skipped entirely if env was unset.
if [ "$TELEGRAM_RESULT" -eq 0 ]; then
  RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${FULL_MSG}" \
    --data-urlencode "disable_web_page_preview=true")
  if echo "$RESPONSE" | grep -q '"ok":true'; then
    echo "Notification sent: [$LEVEL] $MSG"
  else
    TELEGRAM_RESULT=1
    echo "ERROR: Telegram API rejected the message" >&2
    echo "$RESPONSE" >&2
  fi
fi

# AC2 exit-code matrix (per Issue #1055):
#   Legacy non-wake mode (no -w): 0 if Telegram OK, 1 if Telegram failed (backward compat)
#   Dual-channel wake mode:
#     0 = both OK (Telegram sent + tmux wake fired)
#     2 = Telegram failed (env unset OR API reject) + tmux OK
#     3 = Telegram OK + tmux wake failed (NEW branch)
#     1 = both failed (total failure)
if [ -z "$WAKE" ]; then
  # Legacy non-wake mode: backward-compat exit codes
  if [ "$TELEGRAM_RESULT" -eq 0 ]; then
    exit 0
  fi
  exit 1
fi

# Dual-channel wake mode:
if [ "$TELEGRAM_RESULT" -eq 0 ] && [ "$WAKE_RESULT" -eq 0 ]; then
  exit 0  # both OK
fi
if [ "$TELEGRAM_RESULT" -eq 1 ] && [ "$WAKE_RESULT" -eq 0 ]; then
  exit 2  # Telegram failed, tmux OK
fi
if [ "$TELEGRAM_RESULT" -eq 0 ] && [ "$WAKE_RESULT" -eq 1 ]; then
  exit 3  # Telegram OK, tmux wake failed (NEW branch)
fi
exit 1  # both failed (legacy total-fail)
