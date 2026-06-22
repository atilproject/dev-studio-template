#!/usr/bin/env bash
# orchestrator-status-flip.sh — atomic status transition + wake signal
# Per ADR-0036 Part C (RCA-19 fix). Owner-only helper.
#
# Usage:
#   orchestrator-status-flip.sh <issue_number> <new_status> [next_role]
#
# Examples:
#   orchestrator-status-flip.sh 222 in-progress developer
#   orchestrator-status-flip.sh 233 blocked
#
# Template port notes (Issue #233):
#   - Sister to AtilCalculator scripts/orchestrator-status-flip.sh
#   - Template notify.sh does NOT yet have -w flag, so this helper uses
#     the legacy -l fallback path. Future work: port notify.sh -w from
#     AtilCalculator (see PR body N1) and add -w first / -l fallback here.
#
# Properties (per ADR-0036 §Part C):
#   1. Role guard: requires ROLE=orchestrator (exit 3 if not)
#   2. Input validation: status must be in {backlog,ready,in-progress,in-review,blocked,done} (exit 2 on invalid)
#   3. Idempotent: if issue already has the target status, exit 0 (no-op, no flip, no wake)
#   4. Atomic flip: single `gh issue edit --remove-label "status:*" --add-label "status:X"`
#   5. Wake next role: notify.sh -l <role> (template legacy path; -w deferred)
#   6. Audit log: /var/log/dev-studio/<project>/status-flips.log
#   7. Closed-state guard: if issue is state:closed, exit 4 (no-op, terminal)
#
# Exit codes:
#   0   success (incl. idempotent no-op)
#   1   invalid invocation (usage)
#   2   invalid status enum
#   3   non-orchestrator caller
#   4   issue is closed (no-op)
#   5   gh CLI failure
#   6   audit log write failure

set -uo pipefail

# ----- role guard (property 1) -----------------------------------------------
if [ "${ROLE:-}" != "orchestrator" ]; then
  echo "ERROR: orchestrator-only tool (ROLE=${ROLE:-unset})" >&2
  exit 3
fi

# ----- input validation -------------------------------------------------------
ISSUE="${1:-}"
NEW_STATUS="${2:-}"
NEXT_ROLE="${3:-}"

if [ -z "$ISSUE" ] || [ -z "$NEW_STATUS" ]; then
  echo "usage: orchestrator-status-flip.sh <issue_number> <new_status> [next_role]" >&2
  echo "  new_status: backlog|ready|in-progress|in-review|blocked|done" >&2
  exit 1
fi

# Validate status enum (property 2)
case "$NEW_STATUS" in
  backlog|ready|in-progress|in-review|blocked|done) ;;
  *) echo "ERROR: invalid status: $NEW_STATUS (allowed: backlog|ready|in-progress|in-review|blocked|done)" >&2; exit 2 ;;
esac

# ----- preflight --------------------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not found" >&2
  exit 5
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not found" >&2
  exit 5
fi

# ----- fetch current state ----------------------------------------------------
ISSUE_JSON="$(gh issue view "$ISSUE" --json state,labels 2>/dev/null)"
GH_EXIT=$?
if [ $GH_EXIT -ne 0 ]; then
  echo "ERROR: gh issue view $ISSUE failed (exit $GH_EXIT)" >&2
  exit 5
fi

CURRENT_STATE="$(echo "$ISSUE_JSON" | jq -r '.state')"
CURRENT_STATUS="$(echo "$ISSUE_JSON" | jq -r '[.labels[].name] | map(select(startswith("status:"))) | first // ""')"

# Closed-state guard (property 7)
if [ "$CURRENT_STATE" = "CLOSED" ]; then
  echo "WARN: issue #$ISSUE is closed, no-op (exit 4)" >&2
  exit 4
fi

# Idempotency check (property 3)
if [ "$CURRENT_STATUS" = "status:$NEW_STATUS" ]; then
  echo "noop (already status:$NEW_STATUS on #$ISSUE)"
  exit 0
fi

# ----- atomic flip (property 4) -----------------------------------------------
if ! gh issue edit "$ISSUE" --remove-label "status:*" --add-label "status:$NEW_STATUS" >/dev/null 2>&1; then
  echo "ERROR: gh issue edit $ISSUE failed" >&2
  exit 5
fi

# ----- wake signal (property 5) -----------------------------------------------
# Template port: notify.sh has only -l flag (no -w dual-channel yet).
# When notify.sh -w is ported from AtilCalculator, this block should be
# upgraded to dual-channel (try -w first, fall back to -l).
WAKE_MSG="[ORCH→${NEXT_ROLE^^}] status flip on #${ISSUE}: ${CURRENT_STATUS:-none} → status:${NEW_STATUS}"
WAKE_RESULT=""
if [ -n "$NEXT_ROLE" ] && [ -x "$(dirname "$0")/notify.sh" ]; then
  NOTIFY_SH="$(dirname "$0")/notify.sh"
  if "$NOTIFY_SH" -l "$NEXT_ROLE" "$WAKE_MSG" 2>/dev/null; then
    WAKE_RESULT="legacy-fallback"
  else
    WAKE_RESULT="failed"
  fi
else
  WAKE_RESULT="none"
fi

# ----- audit log (property 6) -------------------------------------------------
AUDIT_DIR="${DEV_STUDIO_LOG_BASE:-/var/log/dev-studio}/${PROJECT:-$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")}"
AUDIT_FILE="$AUDIT_DIR/status-flips.log"
if ! mkdir -p "$AUDIT_DIR" 2>/dev/null; then
  echo "WARN: cannot create audit dir $AUDIT_DIR, skipping log" >&2
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
AUDIT_LINE="{\"ts\":\"$TS\",\"issue\":$ISSUE,\"old\":\"${CURRENT_STATUS:-none}\",\"new\":\"status:$NEW_STATUS\",\"next_role\":\"${NEXT_ROLE:-}\",\"wake\":\"$WAKE_RESULT\"}"
if [ -d "$AUDIT_DIR" ]; then
  echo "$AUDIT_LINE" >> "$AUDIT_FILE" 2>/dev/null || echo "WARN: audit log write failed" >&2
fi

# ----- summary ----------------------------------------------------------------
echo "flipped #${ISSUE}: ${CURRENT_STATUS:-none} → status:${NEW_STATUS} (wake: ${NEXT_ROLE:-none}/${WAKE_RESULT})"
exit 0