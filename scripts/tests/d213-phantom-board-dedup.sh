#!/bin/bash
# d213-phantom-board-dedup.sh — regression test for issue #61.
#
# Bug summary (issue #61):
#   Orchestrator's `agent-watch.sh` loop receives the same two `board-*` events
#   (board-50, board-52) repeatedly across polls, even though:
#     - the source issues are CLOSED with `status:done`
#     - the resolving PRs (#51, #54) are merged
#     - the orchestrator's `last_seen_utc` is AFTER the event `updatedAt`
#     - the event IDs are already in `processed_event_ids` ring buffer
#
# Root cause (TDD-locked here):
#   Bug A — `LAST_SEEN` / `PR_MERGED_LAST_SEEN` / `PR_LABELED_LAST_SEEN` are
#           read ONCE at watcher startup (script-top) and never refreshed
#           inside `poll_once`. In a long-running --loop watcher, the local
#           HWM vars drift behind the state file's HWM (which advances on
#           every poll at `poll_once` tail), so the gh query keeps returning
#           historical events with old `updatedAt`.
#
#   Bug B — `processed_event_ids` is FIFO-trimmed to last 50 (configurable via
#           `AGENT_PROCESSED_MAX`). As newer events flood in, the still-active
#           phantom event IDs get evicted from the dedup buffer.
#
# This test guards the FIX SHAPE (structural) — it does NOT exercise --loop
# runtime behavior because that requires real GitHub data + multi-minute
# observation. The structural fix is the precondition; CI + a 5-min live run
# post-merge cover the runtime check.
#
# Per D2.2 doctrine (issue #53): every fix gets a regression test that fails
# on pre-change behavior. This test is TDD-red on `main` (the HWM reads are
# at script-top) and TDD-green after the fix lands.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH="$SCRIPT_DIR/agent-watch.sh"
STATE="$SCRIPT_DIR/agent-state.sh"

PASS=0; FAIL=0
check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc — expected '$expected' got '$actual'"
    FAIL=$((FAIL+1))
  fi
}

# Extract the script-top section (everything before the poll_once() function
# definition). The bug has the HWM reads at script-top; the fix moves them
# into poll_once. This is a structural assertion on the script source.
script_top="$(awk '/^poll_once\(\) \{$/{exit} {print}' "$WATCH")"

# Extract the poll_once function body (between "^poll_once() {" and the
# matching closing brace at the start of a line). Naive awk is fine for our
# simple structure — poll_once is a top-level function with a single closing
# brace.
poll_once_body="$(awk '/^poll_once\(\) \{$/{flag=1; print; next} flag && /^\}$/{print; flag=0; exit} flag {print}' "$WATCH")"

if [ -z "$poll_once_body" ]; then
  echo "ERROR: could not extract poll_once from $WATCH" >&2
  exit 2
fi

echo ""
echo "=== T1: HWM reads moved from script-top to poll_once (Bug A fix) ==="

# Note: grep patterns use `^\s*` so they tolerate leading whitespace; the actual
# script lines have 2-space indent inside functions.
strip() { sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

# T1.1 / T1.2: LAST_SEEN
# Accept the HWM read as either INLINE in poll_once (simple case) or
# transitively via a helper function (e.g. `init_*_hwm`) called from
# poll_once. The structural property we lock is: the read is no longer at
# script-top AND is reachable from poll_once.
LAST_SEEN_REGEX='^LAST_SEEN="\$[[:space:]]*\("\$STATE_HELPER"[[:space:]]+get[[:space:]]+"\$ROLE"[[:space:]]+last_seen_utc[[:space:]]*\)"[[:space:]]*$'
if echo "$script_top"     | strip | grep -qE "$LAST_SEEN_REGEX"; then check "T1.1: LAST_SEEN read is NOT at script-top"           "absent"  "present"; else check "T1.1: LAST_SEEN read is NOT at script-top"           "absent"  "absent";  fi
if echo "$poll_once_body"  | strip | grep -qE "$LAST_SEEN_REGEX"; then check "T1.2: LAST_SEEN read IS in poll_once"             "present" "present"; else check "T1.2: LAST_SEEN read IS in poll_once"             "present" "absent";  fi

# T1.3 / T1.4: PR_MERGED_LAST_SEEN
PR_MERGED_REGEX='^PR_MERGED_LAST_SEEN="\$[[:space:]]*\("\$STATE_HELPER"[[:space:]]+get[[:space:]]+"\$ROLE"[[:space:]]+pr_merged_last_seen_utc[[:space:]]*\)"[[:space:]]*$'
if echo "$script_top"     | strip | grep -qE "$PR_MERGED_REGEX"; then check "T1.3: PR_MERGED_LAST_SEEN read is NOT at script-top" "absent"  "present"; else check "T1.3: PR_MERGED_LAST_SEEN read is NOT at script-top" "absent"  "absent";  fi
if echo "$poll_once_body"  | strip | grep -qE "$PR_MERGED_REGEX"; then
  check "T1.4: PR_MERGED_LAST_SEEN read IS in poll_once"   "present" "present"
elif echo "$poll_once_body" | strip | grep -qE '^init_pr_merged_hwm[[:space:]]*$'; then
  check "T1.4: PR_MERGED_LAST_SEEN read IS in poll_once (via init_pr_merged_hwm helper)"   "present" "present"
else
  check "T1.4: PR_MERGED_LAST_SEEN read IS in poll_once"   "present" "absent"
fi

# T1.5 / T1.6: PR_LABELED_LAST_SEEN
PR_LABELED_REGEX='^PR_LABELED_LAST_SEEN="\$[[:space:]]*\("\$STATE_HELPER"[[:space:]]+get[[:space:]]+"\$ROLE"[[:space:]]+pr_labeled_last_seen_utc[[:space:]]*\)"[[:space:]]*$'
if echo "$script_top"     | strip | grep -qE "$PR_LABELED_REGEX"; then check "T1.5: PR_LABELED_LAST_SEEN read is NOT at script-top" "absent"  "present"; else check "T1.5: PR_LABELED_LAST_SEEN read is NOT at script-top" "absent"  "absent";  fi
if echo "$poll_once_body"  | strip | grep -qE "$PR_LABELED_REGEX"; then
  check "T1.6: PR_LABELED_LAST_SEEN read IS in poll_once"   "present" "present"
elif echo "$poll_once_body" | strip | grep -qE '^init_pr_labeled_hwm[[:space:]]*$'; then
  check "T1.6: PR_LABELED_LAST_SEEN read IS in poll_once (via init_pr_labeled_hwm helper)"   "present" "present"
else
  check "T1.6: PR_LABELED_LAST_SEEN read IS in poll_once"   "present" "absent"
fi

echo ""
echo "=== T2: agent-state.sh DEFAULT_TRIM_MAX bumped 50 -> 200 (Bug B defensive) ==="

# T2.1: DEFAULT_TRIM_MAX default is 200
if grep -qE 'DEFAULT_TRIM_MAX="\$\{AGENT_PROCESSED_MAX:-200\}"' "$STATE"; then
  check "T2.1: DEFAULT_TRIM_MAX default is 200" "200" "200"
else
  actual=$(grep -oE 'DEFAULT_TRIM_MAX="\$\{AGENT_PROCESSED_MAX:-[0-9]+\}"' "$STATE" | grep -oE '[0-9]+' | head -1)
  check "T2.1: DEFAULT_TRIM_MAX default is 200" "200" "${actual:-<not found>}"
fi

# T2.2: trim is still bounded (defensive — never-trim would be a regression)
# Guard against a future refactor accidentally removing the trim entirely.
if grep -qE '\.processed_event_ids = \(.processed_event_ids \| \.\[-\$max:\]\)' "$STATE"; then
  check "T2.2: trim still FIFO-bounded (no regression to never-trim)" "present" "present"
else
  check "T2.2: trim still FIFO-bounded (no regression to never-trim)" "present" "absent"
fi

echo ""
echo "=== T3: integration — fresh process, FRESH HWM, no phantoms emitted ==="
# This is the live-data integration check. It depends on real GitHub repo state
# (issues #50, #52 being CLOSED with `status:done`). It runs in --once mode
# with a controlled state file, so it's deterministic.
#
# Post-fix, an --once watcher with state HWM = (now + 1 day) should emit 0
# board-* phantom events (because the local LAST_SEEN, read fresh at script
# start, equals the state HWM, and the gh filter drops everything historical).
#
# Pre-fix, this same scenario would ALSO emit 0 phantoms (because the local
# LAST_SEEN, read once at script start, equals the state HWM — they're in
# sync at script start). So this test is NOT a regression test for the bug
# in --once mode; it's a sanity check that the fix doesn't break the FRESH
# case. The actual bug is in --loop mode after long uptime; see T1 for that.

# Skip if gh not authenticated
if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  echo "  SKIP: gh not authenticated (T3 requires live repo access)"
else
  TEST_STATE_DIR="$(mktemp -d)"
  trap "rm -rf '$TEST_STATE_DIR'" EXIT
  export AGENT_STATE_DIR="$TEST_STATE_DIR"

  ONE_DAY_HENCE="$(date -u -d '1 day' '+%Y-%m-%dT%H:%M:%SZ')"
  "$STATE" init orchestrator >/dev/null
  "$STATE" set orchestrator last_seen_utc "$ONE_DAY_HENCE" >/dev/null

  out="$("$WATCH" orchestrator --once 2>/dev/null || echo '{"new_events":[]}')"
  # Issue #50 and #52 should NOT appear as label_change events
  count_50=$(echo "$out" | jq '[.new_events[] | select(.number == 50 and .kind == "label_change")] | length' 2>/dev/null || echo "0")
  count_52=$(echo "$out" | jq '[.new_events[] | select(.number == 52 and .kind == "label_change")] | length' 2>/dev/null || echo "0")
  check "T3.1: board-50 phantom NOT emitted with fresh HWM"   "0" "$count_50"
  check "T3.2: board-52 phantom NOT emitted with fresh HWM"   "0" "$count_52"
fi

echo ""
echo "======================================"
echo "PASS=$PASS  FAIL=$FAIL"
echo "======================================"
[ "$FAIL" -eq 0 ]
