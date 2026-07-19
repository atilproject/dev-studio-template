#!/usr/bin/env bash
# d108-context-watchdog-instant-fire.sh — Sprint 32 Wave-extension d-test
# (S32-XXX-B regression-update sister-test, tmpl#191, ADR-0073)
#
# Purpose: Validates the watchdog instant-fire / clear-escalation behavior under
# the new STUCK_AFTER_MIN defaults (10 / 5). The previous defaults (20 / 3)
# caused 214 false-positive reprimes in 7-day journal evidence (ADR-0072 §Layer 1).
# This test verifies:
#   - Header rationale present (documents the revision in-script)
#   - STUCK_AFTER_MIN_DEFAULT matches new defaults
#   - Saturation threshold table reference present (≥4 thresholds)
#   - agent_likely_stuck logic uses the env-overridable STUCK_AFTER_MIN vars
#   - Cadence Rule 1 atomic — INDEX.md mentions this test (ADR-0055 §1)
#
# Sister-tests: d108-tasklist-snapshot-write-through.sh, d1XX-compact-breathing-room.sh.
# Per ADR-0049 ≥3 sister-pattern coverage (3 members cited).
#
# Test cases (T1..T6) — RED-first per ADR-0044:
#   T1: agent-context-monitor.sh header has rationale comment about ADR-0072 revision
#   T2: agent-context-monitor.sh declares STUCK_AFTER_MIN_DEFAULT (or similar) with value 10
#   T3: agent-context-monitor.sh header documents ≥4 saturation thresholds
#   T4: agent-context-monitor.sh agent_likely_stuck uses STUCK_AFTER_MIN env (overridable)
#   T5: agent-context-monitor.sh uses new defaults in saturation threshold table
#   T6: Cadence Rule 1 atomic — INDEX.md mentions this test (ADR-0055 §1)
#
# Pre-impl RED expected: 1 PASS (T6), 5 FAIL (T1-T5).
# Post-impl GREEN target: 6/6 PASS on S32-XXX-B commit cluster.
#
# Exit code: 0 = all pass, 1 = at least one fail.
#
# Run standalone: bash scripts/tests/d108-context-watchdog-instant-fire.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MONITOR_SH="$SCRIPT_DIR/../agent-context-monitor.sh"
INDEX_FILE="$SCRIPT_DIR/INDEX.md"

# Colors (TTY-aware)
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; Y=$'\033[1;33m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; Y=""; B=""; D=""; fi

PASS=0; FAIL=0
declare -a FAIL_DETAILS=()
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() {
  printf "  ${R}✗ FAIL${D} — %s\n" "$1"
  [ -n "${2:-}" ] && printf "    ${R}%s${D}\n" "$2"
  FAIL=$((FAIL+1))
  FAIL_DETAILS+=("$1")
}
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }
info() { printf "  ${Y}ℹ${D} %s\n" "$1"; }

# ============================================================================
# T1: agent-context-monitor.sh header has rationale about ADR-0072 revision
# ============================================================================
section "T1: monitor header documents ADR-0072 revision rationale"
# Pattern: Per ADR-0072 §Layer 1 + ADR-0073, the script's header comment block
# must reference the 7-day 214-false-positive journal evidence and the
# saturation threshold table. Sister-pattern to d1XX-compact-breathing-room
# (config boundary).
if [[ -r "$MONITOR_SH" ]]; then
  HEADER=$(head -50 "$MONITOR_SH")
  if echo "$HEADER" | grep -qiE "ADR-0072|214.false.positive|saturation threshold|watchdog tuning"; then
    pass "monitor header references ADR-0072 revision evidence"
  else
    fail "monitor header missing revision rationale" \
         "expected 'ADR-0072', '214 false-positive', or 'saturation threshold' reference in first 50 lines per ADR-0072 §Layer 1"
  fi
else
  fail "agent-context-monitor.sh not readable" "expected '$MONITOR_SH' to exist"
fi

# ============================================================================
# T2: monitor declares STUCK_AFTER_MIN_DEFAULT with value 10
# ============================================================================
section "T2: monitor declares new default STUCK_AFTER_MIN=10"
# Pattern: Either a literal `STUCK_AFTER_MIN=10` assignment, or a DEFAULT
# variable name like `STUCK_AFTER_MIN_DEFAULT=10`. The previous default 20
# must NOT appear as a default.
if [[ -r "$MONITOR_SH" ]]; then
  # Permissive regex: any line where STUCK_AFTER_MIN appears with value 10
  # (e.g. `STUCK_AFTER_MIN="${STUCK_AFTER_MIN:-10}"` or `STUCK_AFTER_MIN=10`)
  if grep -Eq 'STUCK_AFTER_MIN.*[^0-9]10([^0-9]|$)' "$MONITOR_SH"; then
    # Verify the OLD default 20 is NOT used as default
    if ! grep -Eq 'STUCK_AFTER_MIN.*-:-"?20|"20"|:-20' "$MONITOR_SH"; then
      pass "monitor declares new STUCK_AFTER_MIN=10 default (no stale 20)"
    else
      fail "monitor still has STUCK_AFTER_MIN=20 as default" \
           "expected no STUCK_AFTER_MIN=20 default per ADR-0072 §Layer 1 revision (20 → 10)"
    fi
  else
    fail "monitor missing new STUCK_AFTER_MIN=10 default" \
         "expected STUCK_AFTER_MIN=10 in script per ADR-0072 §Layer 1"
  fi
else
  fail "T2 skipped — monitor not readable" "cascade from T1"
fi

# ============================================================================
# T3: monitor header documents ≥4 saturation thresholds
# ============================================================================
section "T3: monitor header documents ≥4 saturation thresholds"
# Pattern: Per ADR-0072 §Layer 1 + ADR-0073, monitor header should document
# the saturation threshold table (90-95%, 95-99%, 100%, 100%>15min). ≥4 rows.
if [[ -r "$MONITOR_SH" ]]; then
  HEADER=$(head -100 "$MONITOR_SH")
  # Count distinct threshold percentage references in header
  THRESHOLD_COUNT=$(echo "$HEADER" | grep -cE '(90-95|95-99|100%|>15min|>5min|>3min|>= ?(90|95|99|100))')
  if [[ "$THRESHOLD_COUNT" -ge 4 ]]; then
    pass "monitor header documents ≥4 saturation thresholds ($THRESHOLD_COUNT found)"
  else
    fail "monitor header missing saturation threshold table" \
         "expected ≥4 saturation threshold references (90-95%, 95-99%, 100%, etc.) in header per ADR-0072 §Layer 1 (got $THRESHOLD_COUNT)"
  fi
else
  fail "T3 skipped — monitor not readable" "cascade from T1"
fi

# ============================================================================
# T4: agent_likely_stuck function uses STUCK_AFTER_MIN env (overridable)
# ============================================================================
section "T4: agent_likely_stuck uses STUCK_AFTER_MIN env (overridable)"
# Pattern: The stuck-detection function MUST reference ${STUCK_AFTER_MIN} (not
# hardcoded 20). This is the env-override hook that ADR-0072 §Layer 1 enables.
if [[ -r "$MONITOR_SH" ]]; then
  # Look for agent_likely_stuck function block + env var reference inside
  if grep -A 10 "agent_likely_stuck" "$MONITOR_SH" 2>/dev/null | grep -Eq '\$\{?STUCK_AFTER_MIN'; then
    pass "agent_likely_stuck references \${STUCK_AFTER_MIN} (env-overridable)"
  else
    fail "agent_likely_stuck does not use STUCK_AFTER_MIN env" \
         "expected '\${STUCK_AFTER_MIN}' reference inside agent_likely_stuck function body per ADR-0072 §Layer 1 env-override pattern"
  fi
else
  fail "T4 skipped — monitor not readable" "cascade from T1"
fi

# ============================================================================
# T5: monitor uses new defaults in saturation threshold table (header)
# ============================================================================
section "T5: monitor header saturation table uses new defaults"
# Pattern: The saturation threshold table in monitor header should reference
# STUCK_AFTER_MIN=10 (not 20). Look for the table block.
if [[ -r "$MONITOR_SH" ]]; then
  HEADER=$(head -100 "$MONITOR_SH")
  # Should mention STUCK_AFTER_MIN with value 10 in saturation table
  if echo "$HEADER" | grep -Eq "STUCK_AFTER_MIN.*[^0-9]10([^0-9]|$)"; then
    pass "monitor header saturation table uses STUCK_AFTER_MIN=10"
  else
    # Fallback: check any saturation table mention references the value
    if echo "$HEADER" | grep -qiE "saturation" && echo "$HEADER" | grep -qE "10 min"; then
      pass "monitor header saturation context mentions '10 min'"
    else
      fail "monitor header saturation table does not reference new default" \
           "expected '10 min' or 'STUCK_AFTER_MIN=10' reference in monitor header per ADR-0072 §Layer 1"
    fi
  fi
else
  fail "T5 skipped — monitor not readable" "cascade from T1"
fi

# ============================================================================
# T6: Cadence Rule 1 atomic — INDEX.md mentions this test (ADR-0055 §1)
# ============================================================================
section "T6: Cadence Rule 1 atomic per ADR-0055 §1"
# Pattern: Per ADR-0055 §1, this test file + INDEX.md row + impl files must land
# in the SAME commit. Verify INDEX.md has a row referencing d108-context-watchdog-instant-fire.
if [[ -r "$INDEX_FILE" ]] && grep -q "d108-context-watchdog-instant-fire" "$INDEX_FILE"; then
  pass "INDEX.md references this test file (Cadence Rule 1 atomic verified)"
else
  fail "INDEX.md missing d108-context-watchdog-instant-fire row" \
       "expected '$INDEX_FILE' to contain 'd108-context-watchdog-instant-fire' row (Cadence Rule 1 atomic per ADR-0055 §1)"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
TOTAL=$((PASS + FAIL))
printf "${B}==== Summary ====${D}\n"
echo "PASS: $PASS"
echo "FAIL: $FAIL"
echo "TOTAL: $TOTAL"
if [[ $FAIL -gt 0 ]]; then
  printf "${R}${B}RED STATE CONFIRMED${D} — ${R}%d/%d TESTS FAIL${D}\n" "$FAIL" "$TOTAL"
  echo "Failed TCs (impl gap signals):"
  for d in "${FAIL_DETAILS[@]}"; do echo "  - $d"; done
  echo ""
  echo "Per ADR-0044 RED-first TDD: this is the EXPECTED state before S32-XXX-B impl lands."
  echo "Once agent-context-monitor.sh header + saturation table updates land in same commit cluster,"
  echo "this test should turn 6/6 GREEN."
  exit 1
else
  printf "${G}${B}GREEN — ALL %d TESTS PASSED${D}\n" "$PASS"
  exit 0
fi
