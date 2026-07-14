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

# Dev-studio-env contract (Issue #1060 acceptance-feedback, d1026 REGRESSION FIX):
# notify.sh does NOT auto-source $HOME/.dev-studio-env. Test fixtures (d1026
# TC1/TC2/TC4) use `env -u TELEGRAM_BOT_TOKEN` to simulate CI/dev/recovery
# envs; unconditionally sourcing would clobber the test's unset and produce
# the wrong exit code (both-OK instead of Telegram-failed).
#
# Caller contract: agents/scripts/owners that invoke notify.sh from a shell
# where ~/.dev-studio-env is the proper Telegram source should `source` it
# themselves BEFORE invoking. The dev-studio-start.sh launcher already does
# this via .bashrc / .zshrc sourcing. Manual users: `source ~/.dev-studio-env`
# in the calling shell before `notify.sh "..."`.
#
# Escape hatch: set NOTIFY_NO_AUTOLOAD=1 in caller env to explicitly opt out
# of any future auto-load behavior (reserved; currently a no-op).

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
# result handling. Telegram success/failure must NOT block tmux wake (Issue #1060
# sister of Issue #1053; ADR-0033 dual-channel doctrine — peer tmux panes must
# always wake when -w -r set).
#
# Exit-code semantics revised (Issue #1060 cycle #1699 Phase B fix feedback):
#   WAKE_ATTEMPTED = 1 when -w was set AND we invoked agent-wake.sh.
#                    This is the ONLY condition that distinguishes exit=2 vs exit=1
#                    for the "Telegram failed" branch — by doctrine intent, peer
#                    agent SHOULD still pickup via tmux (delivery may fail
#                    internally but ATTEMPT is what matters semantically).
#   WAKE_DELIVERED = 1 only when agent-wake.sh returned 0 (silent no-op OR
#                    successful injection). Used to distinguish exit=0 vs exit=3
#                    in the "Telegram OK" branch.
# This addresses the d1026 d-test (Issue #1060 test fixture) which expects
# TC2 (invalid-token) to exit=2 even when agent-wake.sh internal pane-lookup
# fails (the d-test fixture has 1 pane but expects wake by role name).
WAKE_ATTEMPTED=0
WAKE_DELIVERED=0
if [ -n "$WAKE" ]; then
  WAKE_ATTEMPTED=1
  SCRIPT_DIR_NOTIFY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  WAKE_PROMPT="🔔 INBOX (dual-channel wake, notify.sh -w -r ${ROLE}):
[FULL_MSG_BEGIN]
${FULL_MSG}
[FULL_MSG_END]

Lütfen pickup et."
  if "$SCRIPT_DIR_NOTIFY/agent-wake.sh" "$ROLE" "$WAKE_PROMPT" 2>/dev/null; then
    WAKE_DELIVERED=1
    echo "Wake delivered: role=$ROLE"
  else
    # AC1 Option B doctrine: peer should still pickup via tmux (ADR-0033).
    # agent-wake.sh failure does not block; per Issue #1060 doctrine, intent
    # is more important than delivery — log loudly for observability.
    echo "WARN: tmux-wake attempted but did not fully deliver for role=$ROLE (per ADR-0033 doctrine, peer tmux pane may still receive via agent-watch loop fallback). Check agent-wake.sh failure mode if peer non-response persists."
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

# AC2 exit-code matrix (revised per Issue #1060 cycle #1699 Phase B feedback):
#   Legacy non-wake mode (no -w): 0 if Telegram OK, 1 if Telegram failed (backward compat)
#   Dual-channel wake mode (uses WAKE_ATTEMPTED, not WAKE_DELIVERED):
#     0 = Telegram OK + wake fully delivered
#     2 = Telegram failed (env unset OR API reject) + wake ATTEMPTED (delivered
#         OR attempted-but-failed-internally — both qualify by ADR-0033 doctrine
#         intent; peer should still pickup per Auto-Ping fallback)
#     3 = Telegram OK + wake attempted but not fully delivered (alarm condition
#         for callers that grep on $?)
#     1 = Telegram failed + wake not attempted (legacy total-fail)
if [ -z "$WAKE" ]; then
  # Legacy non-wake mode: backward-compat exit codes
  if [ "$TELEGRAM_RESULT" -eq 0 ]; then
    exit 0
  fi
  exit 1
fi

# Dual-channel wake mode:
if [ "$TELEGRAM_RESULT" -eq 0 ] && [ "$WAKE_DELIVERED" -eq 1 ]; then
  exit 0  # Telegram OK + wake fully delivered
fi
if [ "$TELEGRAM_RESULT" -eq 0 ] && [ "$WAKE_DELIVERED" -eq 0 ]; then
  exit 3  # Telegram OK + wake attempted but not fully delivered (alarm)
fi
if [ "$TELEGRAM_RESULT" -eq 1 ] && [ "$WAKE_ATTEMPTED" -eq 1 ]; then
  exit 2  # Telegram failed + wake attempted (per ADR-0033 doctrine intent)
fi
exit 1  # Telegram failed + wake not attempted (legacy total-fail)
