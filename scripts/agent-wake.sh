#!/usr/bin/env bash
# agent-wake.sh — Inject a wake-up prompt into a named agent's tmux pane.
#
# ADR-0033 Auto-Ping dual-channel doctrine (Issue #221, PR #223) requires that
# peer-agent pings reach both Telegram (human mirror, via notify.sh) AND the
# target agent's tmux pane (agent wake). This script is the second half of
# that dual-channel wiring.
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

# --- Fix 4b (Issue #1138 / ADR-0066): lenient capture-pane verify + hierarchical exit code ---
# Issue #1063 Fix 3 had three failure modes that produced FALSE-failures on
# perfectly-delivered wakes (Sprint 31 cycles ~#2855/~#2857/~#2858/~#2861,
# 6/6 false-failures, 6/6 actual delivery success via GitHub artefact path):
#
#   1) Hardcoded `timeout 1` too tight — slow tmux renders on long-running
#      panes missed the verify window even though send-keys had succeeded.
#   2) Dynamic MSG_PREFIX derivation from `MSG` was render-drift-fragile —
#      first line wrapped differently across tmux versions, prefix mismatched
#      even though the text was actually in the pane.
#   3) Hierarchical exit code was binary — verify-FAIL was treated as hard
#      fail (rc=1), which polluted audit logs with noise on otherwise-good
#      wakes. GitHub artefact path (ADR-0033 dual-channel) is the PRIMARY
#      wake, so verify-uncertain should be lenient.
#
# Fix 4b (3 additive changes — additive evolution, NOT destructive rewrite):
#   D1: `WAKE_VERIFY_TIMEOUT_SEC` env override (default 3s, was hardcoded 1s).
#       Sister-pattern naming to d068b `WAKE_KEYS_GAP_SEC` (Issue #935).
#   D2: 16-char literal sentinel `"🔔 INBOX (dual-c"` replaces dynamic
#       MSG_PREFIX derivation. Sentinel is the canonical INBOX header prefix;
#       render-drift-immune (vs the prior 80-char prefix which could be
#       truncated mid-character at tmux wrap boundaries).
#   D3: Hierarchical exit codes:
#         Tier 1: send-keys OK + verify OK → rc=0 (preserved happy path)
#         Tier 2: send-keys OK + verify FAIL → rc=0 + stderr WARN (LENIENT)
#                 send-keys succeeded, GitHub artefact path is primary wake.
#         Tier 3: send-keys FAIL → rc=1 + stderr ERROR (preserved hard-fail)
#                 This block is at lines 84-87 above; D3 only changes Tier 2.
#   D4: WARN vs ERROR log discrimination — owner-greppable audit.
#         WARN: Wake injected but verify uncertain → uncertain-but-sent (Tier 2)
#         ERROR: send-keys returned ...            → definite failure (Tier 3)
#
# Sister-pattern lineage:
#   - Issue #1063 Fix 3 (additive evolution, NOT destructive rewrite)
#   - d068b (WAKE_KEYS_GAP_SEC env override naming, Issue #935)
#   - ADR-0033 (dual-channel doctrine — GitHub artefact path is primary wake)
#   - ADR-0066 (Fix 4b decision codification)
#   - Issue #1138 (P1 bug, Sprint 31 cluster-squash Path A v26 step 3/3)
VERIFY_SENTINEL="🔔 INBOX (dual-c"

# D1: env override for capture-pane timeout. Default 3s; was hardcoded 1s.
verify_timeout="${WAKE_VERIFY_TIMEOUT_SEC:-3}"

# Test contract (d1138 TC1): log verify_timeout to TMUX_LOG_FILE when set, so
# the d-test fixture's fake tmux log can verify which `timeout` value was
# passed. No-op in production (TMUX_LOG_FILE unset). This is a diagnostic
# hook, not a feature — does not affect the actual capture-pane invocation.
if [ -n "${TMUX_LOG_FILE:-}" ]; then
  printf 'capture-pane invoked with timeout %s\n' "$verify_timeout" >> "$TMUX_LOG_FILE"
fi

if timeout "$verify_timeout" tmux capture-pane -t "$pane_id" -p 2>/dev/null \
   | grep -qF "$VERIFY_SENTINEL"; then
  # Tier 1 (D3): send-keys OK + verify OK → rc=0 (happy path preserved).
  echo "Wake verified: role=$ROLE pane=$pane_id"
  exit 0
fi

# Tier 2 (D3): send-keys OK + verify FAIL → rc=0 + stderr WARN (LENIENT).
# send-keys succeeded at lines 82-87 above, so the wake text DID reach the
# pane (or at least was sent); the GitHub artefact path (ADR-0033) is the
# primary wake, so verify-uncertainty is non-blocking. Capture grep rc for
# audit log: rc=0 means match, rc=1 means mismatch/timeout.
# Note: pipefail in `set -uo pipefail` propagates the rightmost non-zero rc;
# explicit `|| verify_rc=$?` keeps semantics unambiguous in all bash versions.
verify_rc=0
timeout "$verify_timeout" tmux capture-pane -t "$pane_id" -p 2>/dev/null \
  | grep -qF "$VERIFY_SENTINEL" || verify_rc=$?
echo "WARN: Wake injected but verify uncertain for role=$ROLE pane=$pane_id rc=$verify_rc (pane may have scrolled past VERIFY_SENTINEL; text sent via send-keys — GitHub artefact path is primary wake per ADR-0033)" >&2
exit 0