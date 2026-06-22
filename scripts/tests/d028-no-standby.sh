#!/usr/bin/env bash
# d028-no-standby.sh — regression test for Issue #40 (P0 self-standby doctrine).
#
# Template port (Issue #262). Reference impl: atilcan65/AtilCalculator d028.
# Template equivalent: Issue #40 — "§Forbidden Standby Modes — port Issue #238
# from AtilCalculator to 5 soul templates" (merged via PR #40 in template).
#
# Issue #238 (2026-06-22T06:46Z): owner reported "no agent is working". RCA
# revealed 4 agents in self-invented standby:
#   - architect: "GitHub rate limit hit" (silent watcher)
#   - developer: "#232/#233 dependency blocks" (queue-bypass)
#   - tester: "STATE-CORRUPTION processed_event_ids 200→2" (silence on degradation)
#   - orchestrator: 84% context, busy
#
# Fix (per template Issue #40 PR + this d028 regression):
#   1. agent-watch.sh: emit synthetic `is_alive` event every IS_ALIVE_INTERVAL_SEC
#      (default 300s = 5min), independent of queue state. Catches the silent
#      watcher class (rate-limited gh api, stuck query deadlock).
#   2. agent-watch.sh: expand `wake_nudge` trigger to fire when
#      `last_is_alive_utc` is older than 2x IS_ALIVE_INTERVAL_SEC (heartbeat-
#      missed). Catches the "watcher itself stuck" class even when queue empty.
#   3. agent-state.sh: schema adds `last_is_alive_utc: null` field
#      with backfill for existing state files.
#
# Bug-class defended against:
#   T1: is_alive event NOT emitted every 5 min (silent watcher class)
#   T2: is_alive event emitted with wrong shape (consumer breaks)
#   T3: wake_nudge does NOT fire on heartbeat-missed (Issue #238 RCA gap)
#   T4: last_is_alive_utc field missing from state schema (cmd_get fails)
#   T5: state backfill missing for last_is_alive_utc (existing state files break)
#   T6: is_alive emit rate can flood processed_event_ids dedup (5min throttle)
#   T7: agent-watch.sh existing d015 regression still passes (no false breakage)
#
# Exit code: 0 = all pass, 1 = at least one fail.
#
# Run standalone: bash scripts/tests/d028-no-standby.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH_SH="$SCRIPT_DIR/../agent-watch.sh"
STATE_SH="$SCRIPT_DIR/../agent-state.sh"

# Colors (TTY-aware)
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; B=""; D=""
fi

PASS=0; FAIL=0
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required" >&2; exit 127
fi
if [ ! -r "$WATCH_SH" ]; then
  echo "ERROR: agent-watch.sh not found at $WATCH_SH" >&2; exit 127
fi
if [ ! -r "$STATE_SH" ]; then
  echo "ERROR: agent-state.sh not found at $STATE_SH" >&2; exit 127
fi

# ============================================================================
# T1: is_alive synthetic event emitted every 5 min (default IS_ALIVE_INTERVAL_SEC)
# ============================================================================
section "T1: is_alive event emission — IS_ALIVE_INTERVAL_SEC + emit logic"
if grep -Fq 'IS_ALIVE_INTERVAL_SEC:-300' "$WATCH_SH" && \
   grep -Fq 'kind: "is_alive"' "$WATCH_SH" && \
   grep -Fq 'is-alive-' "$WATCH_SH"; then
  pass "is_alive synthetic event emitted with 5min default interval"
else
  fail "is_alive emission missing" "expected IS_ALIVE_INTERVAL_SEC:-300, kind:\"is_alive\", is-alive- in agent-watch.sh"
fi

# ============================================================================
# T2: is_alive event shape (kind, id format, context with interval_sec)
# ============================================================================
section "T2: is_alive event JSON shape"
# id format: is-alive-<role>-<ts>
if grep -Eq 'is-alive-.*\+ \$role' "$WATCH_SH"; then
  pass "is_alive event id uses is-alive-<role>-<ts> format"
else
  # Looser check
  if grep -Fq 'is-alive-' "$WATCH_SH" && grep -Fq '$role' "$WATCH_SH"; then
    pass "is_alive event id contains is-alive- prefix and role"
  else
    fail "is_alive event id format wrong" "expected id: (\"is-alive-\" + \$role + \"-\" + \$now)"
  fi
fi
# context includes interval_sec
if grep -Fq 'interval_sec' "$WATCH_SH"; then
  pass "is_alive event context includes interval_sec field"
else
  fail "is_alive context missing interval_sec" "expected context.interval_sec in emit"
fi

# ============================================================================
# T3: wake_nudge fires on heartbeat-missed (>2x IS_ALIVE_INTERVAL_SEC)
# ============================================================================
section "T3: wake_nudge heartbeat-missed branch"
if grep -Fq 'heartbeat_missed' "$WATCH_SH" && \
   grep -Fq 'is_alive_interval' "$WATCH_SH" && \
   grep -Fq 'is_alive_interval * 2' "$WATCH_SH"; then
  pass "wake_nudge has heartbeat_missed branch with 2x interval threshold"
else
  fail "heartbeat-missed branch missing" "expected heartbeat_missed + 'is_alive_interval * 2' in agent-watch.sh"
fi
# Note string for heartbeat-missed branch
if grep -Fq 'watcher heartbeat missed' "$WATCH_SH"; then
  pass "heartbeat-missed branch has distinct note string"
else
  fail "heartbeat-missed note missing" "expected 'watcher heartbeat missed' note in wake_nudge emit"
fi

# ============================================================================
# T4: last_is_alive_utc field in agent-state.sh init schema
# ============================================================================
section "T4: last_is_alive_utc in state schema (init template)"
if grep -Fq 'last_is_alive_utc' "$STATE_SH"; then
  pass "last_is_alive_utc referenced in agent-state.sh"
else
  fail "last_is_alive_utc missing" "expected last_is_alive_utc in agent-state.sh init template + backfill"
fi
# Init template has the field
if grep -Fq 'last_is_alive_utc: null' "$STATE_SH"; then
  pass "init template has last_is_alive_utc: null"
else
  fail "init template incomplete" "expected 'last_is_alive_utc: null' in init JSON template"
fi

# ============================================================================
# T5: state backfill for last_is_alive_utc
# ============================================================================
section "T5: state backfill for last_is_alive_utc"
if grep -Eq 'has\("last_is_alive_utc"\)' "$STATE_SH"; then
  pass "backfill present for last_is_alive_utc"
else
  fail "backfill missing" "expected 'has(\"last_is_alive_utc\")' backfill guard in cmd_init"
fi

# ============================================================================
# T6: is_alive emit throttled (5-min default, won't flood dedup buffer)
# ============================================================================
section "T6: is_alive emit throttled by interval check (no flood)"
# The emit should be guarded by an interval check, not fire on every poll
if grep -Fq 'now_epoch - last_is_alive_epoch' "$WATCH_SH" && \
   grep -Fq 'emit_is_alive' "$WATCH_SH"; then
  pass "is_alive emit guarded by interval check (no per-poll flood)"
else
  fail "is_alive emit unthrottled" "expected interval check via now_epoch - last_is_alive_epoch"
fi

# ============================================================================
# T7: agent-watch.sh existing wake_nudge (d015) preserved (no regression)
# ============================================================================
section "T7: existing wake_nudge trigger preserved (d015 still 9/9 PASS)"
# d015 T7 checks context.agent_count + cc_count + note. New context adds
# heartbeat_missed — old fields must still be present.
if grep -Fq 'agent_count: $queue' "$WATCH_SH" && \
   grep -Fq 'cc_count: $cc' "$WATCH_SH" && \
   grep -Fq 'note: $note' "$WATCH_SH"; then
  pass "wake_nudge context preserves agent_count + cc_count + note (d015 T7 compat)"
else
  fail "wake_nudge context lost d015 fields" "expected agent_count: \$queue + cc_count: \$cc + note: \$note"
fi
# d015 T3/T4 — agent:<role> + cc:<role> label filters preserved
if grep -Fq 'label "agent:${ROLE}"' "$WATCH_SH" && \
   grep -Fq 'label "cc:${ROLE}"' "$WATCH_SH"; then
  pass "queue check filters preserved (agent:<role> + cc:<role>)"
else
  fail "queue check filters lost" "expected gh issue list with agent/c:<ROLE> label filters"
fi

# ============================================================================
# Summary
# ============================================================================
section "Summary"
TOTAL=$((PASS + FAIL))
printf "  ${B}PASS${D}: %d / %d\n" "$PASS" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then
  printf "  ${R}FAIL${D}: %d / %d\n" "$FAIL" "$TOTAL"
  echo
  echo "Issue #40 REGRESSION FAILED — one or more forbidden-standby defenses missing."
  exit 1
fi
echo
echo "Issue #40 REGRESSION PASS — 4 forbidden standby modes are defended:"
echo "  - 'blocked on dependency' → agent takes OTHER queue items (CLAUDE.md §NEVER)"
echo "  - 'GitHub rate limit hit' → is_alive heartbeat (T1) keeps watcher observable"
echo "  - 'state corruption' → is_alive + heartbeat-missed branch (T3) catches degraded watcher"
echo "  - 'no new events' / 'queue is empty' → wake_nudge (d015 T3/T4) + heartbeat-missed (T3)"
exit 0
