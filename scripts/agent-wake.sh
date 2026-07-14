#!/usr/bin/env bash
# agent-wake.sh — Inject a wake-up prompt into a named agent's tmux pane.
#
# ADR-0033 Auto-Ping dual-channel doctrine (Issue #221, PR #223) requires that
# peer-agent pings reach both Telegram (human mirror, via notify.sh) AND the
# target agent's tmux pane (agent wake). This script is the second half of
# that dual-channel wiring.
#
# Template port: Issue #222. Reference impl: atilcan65/AtilCalculator commit
# ecbf21a (PR #239). All projects bootstrapped from this template ship with
# the dual-channel wake capability.
#
# Usage:
#   scripts/agent-wake.sh <role> "<message>"
#
# Where:
#   <role>     — agent role: orchestrator | product-manager | architect |
#                developer | tester | human (silent no-op for unknown roles)
#   <message>  — free-form text; backticks/$VAR preserved (literal mode)
#
# Exit codes:
#   0  — success (delivery verified via capture-pane) or silent no-op
#        (tmux missing, unknown role, no session)
#   1  — delivery failure (send-keys rc!=0, pane lookup failed,
#        capture-pane verify mismatch — Issue #1063 hotfix)
#   2  — missing args (usage error)
#
# Env vars:
#   TMUX_SESSION  — tmux session name (default: dev-studio)
#
# Backward-compat:
#   Safe to call when tmux is not installed or no session is running.
#   Silent no-op so callers don't need to guard.

set -uo pipefail

TMUX_SESSION="${TMUX_SESSION:-dev-studio}"

ROLE="${1:-}"
MSG="${2:-}"

# --- T4: missing args → usage error, exit 2 ---
if [ -z "$ROLE" ] || [ -z "$MSG" ]; then
  echo "Usage: $0 <role> \"<message>\"" >&2
  echo "Roles: orchestrator | product-manager | architect | developer | tester | human" >&2
  exit 2
fi

# --- T2: no tmux → silent no-op ---
command -v tmux >/dev/null 2>&1 || exit 0
tmux has-session -t "$TMUX_SESSION" 2>/dev/null || exit 0

# --- Fix 2 (Issue #1063): deterministic pane_index lookup ---
# Replaces fragile title-match (descriptive pane titles like "Reprime developer
# doctrine..." never equal UPPERCASE_ROLE) + undocumented :main.N fallback
# (works only via tmux's lenient parser; wrong format per Issue #1063 Fix 2).
#
# Role→pane_index map (matches dev-studio-start.sh layout):
#   orchestrator=0, product-manager=1, architect=2, developer=3,
#   tester=4, human=5
case "$ROLE" in
  orchestrator)    pane_index=0 ;;
  product-manager) pane_index=1 ;;
  architect)       pane_index=2 ;;
  developer)       pane_index=3 ;;
  tester)          pane_index=4 ;;
  human)           pane_index=5 ;;
  # --- T3: unknown role → silent no-op, exit 0 ---
  *) exit 0 ;;
esac

pane_id="$(tmux list-panes -t "$TMUX_SESSION" -F '#{pane_id} #{pane_index}' 2>/dev/null \
  | awk -v idx="$pane_index" '$2 == idx { print $1; exit }')"

if [ -z "$pane_id" ]; then
  echo "ERROR: pane lookup failed for role=$ROLE index=$pane_index session=$TMUX_SESSION rc=empty-pane-id" >&2
  exit 1
fi

# T7: literal-mode (-l) so backticks and $VAR in the message survive intact.
# TD-068b (Issue #935): env-override sleep between text and Enter (default 0.5s, override via WAKE_KEYS_GAP_SEC) prevents tmux from collapsing both into a single literal keystroke under load.
# Fix 1 (Issue #1063): explicit rc check — no `|| exit 0` mask. Caller (notify.sh)
# must see the real delivery status instead of a silent success.
# Note: bash `$?` inside `if ! cmd; then BODY; fi` is the rc of `! cmd` (0 when cmd
# failed), NOT the rc of cmd. Capture rc explicitly via `|| tmux_rc=$?`.
tmux_rc=0
tmux send-keys -t "$pane_id" -l "$MSG" 2>/dev/null || tmux_rc=$?
if [ "$tmux_rc" -ne 0 ]; then
  echo "ERROR: send-keys returned rc=$tmux_rc for pane=$pane_id role=$ROLE" >&2
  exit 1
fi
sleep "${WAKE_KEYS_GAP_SEC:-0.5}"

tmux_rc=0
tmux send-keys -t "$pane_id" Enter 2>/dev/null || tmux_rc=$?
if [ "$tmux_rc" -ne 0 ]; then
  echo "ERROR: send-keys Enter returned rc=$tmux_rc for pane=$pane_id role=$ROLE" >&2
  exit 1
fi

# --- Fix 3 (Issue #1063): capture-pane post-send verify ---
# End-to-end delivery check: did the wake text actually land in the pane?
# Without this, "Wake injected" log was a lie (silent miss on partial
# delivery, dropped keystrokes, slow pane renders).
# 1s timeout covers slow tmux renders; grep -F for literal substring match
# against MSG_PREFIX (first line of MSG, truncated to 80 chars for stability).
MSG_PREFIX="${MSG%%$'\n'*}"
if [ "${#MSG_PREFIX}" -gt 80 ]; then
  MSG_PREFIX="${MSG_PREFIX:0:80}"
fi

if timeout 1 tmux capture-pane -t "$pane_id" -p 2>/dev/null | grep -qF "$MSG_PREFIX"; then
  echo "Wake verified: role=$ROLE pane=$pane_id"
  exit 0
fi
# Fix 3 verify failed — capture grep rc (rc=0 means match, rc=1 means mismatch/timeout).
# Note: pipefail in set -uo pipefail propagates the rightmost non-zero rc; explicit
# capture via `|| verify_rc=$?` keeps rc=$? semantics unambiguous in all bash versions.
verify_rc=0
timeout 1 tmux capture-pane -t "$pane_id" -p 2>/dev/null | grep -qF "$MSG_PREFIX" || verify_rc=$?
echo "ERROR: capture-pane verify failed for role=$ROLE pane=$pane_id rc=$verify_rc (no match for prefix: $MSG_PREFIX)" >&2
exit 1
