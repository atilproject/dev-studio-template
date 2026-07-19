#!/usr/bin/env bash
# d1XX-compact-breathing-room.sh — Sprint 32 Wave-extension d-test
# (S32-XXX-B sister-test, tmpl#191, ADR-0073 — STUCK_AFTER_MIN defaults verification)
#
# Purpose: Validates the ADR-0072 §Layer 1 watchdog tuning revision:
#   - STUCK_AFTER_MIN: 20 → 10 (7-day 214-false-positive journal evidence)
#   - STUCK_AFTER_MIN_CRITICAL: 3 → 5 (catches genuine stuck-at-100% without
#     premature /clear escalation)
#
# Sister-tests: d108-tasklist-snapshot-write-through.sh (write boundary),
#   e2e-tasklist-persistence-through-clear.sh (lifecycle integration).
#
# Test cases (T1..T7) — RED-first per ADR-0044:
#   T1: scripts/agent-context-monitor.sh has STUCK_AFTER_MIN=10 (default)
#   T2: scripts/agent-context-monitor.sh has STUCK_AFTER_MIN_CRITICAL=5 (default)
#   T3: systemd/dev-studio-context-monitor@.service Environment= STUCK_AFTER_MIN=10
#   T4: systemd/dev-studio-context-monitor@.service Environment= STUCK_AFTER_MIN_CRITICAL=5
#   T5: docs/CONTEXT-HYGIENE.md §6.3 reflects new defaults (10/5 not 20/3)
#   T6: docs/CONTEXT-HYGIENE.md §6.4 tunables table reflects new defaults
#   T7: Cadence Rule 1 atomic — INDEX.md mentions this test (ADR-0055 §1)
#
# Pre-impl RED expected (impl lands in same commit, this test goes GREEN):
#   PASS: T7 (INDEX.md row added same commit)
#   FAIL: T1-T6 (impl missing or pre-revision defaults)
# Post-impl GREEN target: 7/7 PASS on S32-XXX-B commit cluster.
#
# Exit code: 0 = all pass, 1 = at least one fail.
#
# Run standalone: bash scripts/tests/d1XX-compact-breathing-room.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MONITOR_SH="$SCRIPT_DIR/../agent-context-monitor.sh"
SYSTEMD_UNIT="$REPO_ROOT/systemd/dev-studio-context-monitor@.service"
DOC_FILE="$REPO_ROOT/docs/CONTEXT-HYGIENE.md"
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
# T1: scripts/agent-context-monitor.sh has STUCK_AFTER_MIN=10 (default)
# ============================================================================
section "T1: agent-context-monitor.sh STUCK_AFTER_MIN default = 10"
# Pattern: Per ADR-0072 §Layer 1, STUCK_AFTER_MIN default revision 20 → 10.
# Sister-pattern to d108 (write boundary) — this test is the CONFIG boundary.
if [[ -r "$MONITOR_SH" ]]; then
  # Match either: STUCK_AFTER_MIN=10  OR  STUCK_AFTER_MIN="${STUCK_AFTER_MIN:-10}"
  if grep -Eq '^STUCK_AFTER_MIN=(\"?\$?\{?STUCK_AFTER_MIN:-?\"?10|\"?10)' "$MONITOR_SH"; then
    pass "STUCK_AFTER_MIN default = 10 (post-ADR-0072 revision)"
  else
    # Fallback: check that the value is present somewhere as default
    if grep -Eq 'STUCK_AFTER_MIN.*[^0-9]10([^0-9]|$)' "$MONITOR_SH"; then
      pass "STUCK_AFTER_MIN value 10 detected (any form)"
    else
      fail "STUCK_AFTER_MIN default not 10" \
           "expected STUCK_AFTER_MIN=10 (or :-\"10\") per ADR-0072 §Layer 1 watchdog tuning revision (was 20)"
    fi
  fi
else
  fail "agent-context-monitor.sh not readable" "expected '$MONITOR_SH' to exist"
fi

# ============================================================================
# T2: scripts/agent-context-monitor.sh has STUCK_AFTER_MIN_CRITICAL=5 (default)
# ============================================================================
section "T2: agent-context-monitor.sh STUCK_AFTER_MIN_CRITICAL default = 5"
# Pattern: Per ADR-0072 §Layer 1, STUCK_AFTER_MIN_CRITICAL default revision 3 → 5.
if [[ -r "$MONITOR_SH" ]]; then
  if grep -Eq '^STUCK_AFTER_MIN_CRITICAL=(\"?\$?\{?STUCK_AFTER_MIN_CRITICAL:-?\"?5|\"?5)' "$MONITOR_SH"; then
    pass "STUCK_AFTER_MIN_CRITICAL default = 5 (post-ADR-0072 revision)"
  else
    if grep -Eq 'STUCK_AFTER_MIN_CRITICAL.*[^0-9]5([^0-9]|$)' "$MONITOR_SH"; then
      pass "STUCK_AFTER_MIN_CRITICAL value 5 detected (any form)"
    else
      fail "STUCK_AFTER_MIN_CRITICAL default not 5" \
           "expected STUCK_AFTER_MIN_CRITICAL=5 (or :-\"5\") per ADR-0072 §Layer 1 (was 3)"
    fi
  fi
else
  fail "T2 skipped — agent-context-monitor.sh not readable" "cascade from T1"
fi

# ============================================================================
# T3: systemd unit Environment= STUCK_AFTER_MIN=10
# ============================================================================
section "T3: systemd unit Environment= STUCK_AFTER_MIN=10"
# Pattern: Per ADR-0072 §Implementation list line 133, systemd unit needs
# `Environment=STUCK_AFTER_MIN=10` line.
if [[ -r "$SYSTEMD_UNIT" ]]; then
  if grep -Eq '^Environment=STUCK_AFTER_MIN=10$' "$SYSTEMD_UNIT"; then
    pass "systemd unit has Environment=STUCK_AFTER_MIN=10"
  else
    fail "systemd unit missing STUCK_AFTER_MIN=10" \
         "expected '^Environment=STUCK_AFTER_MIN=10$' line in $SYSTEMD_UNIT per ADR-0072 §Implementation list"
  fi
else
  fail "systemd unit not readable" "expected '$SYSTEMD_UNIT' to exist"
fi

# ============================================================================
# T4: systemd unit Environment= STUCK_AFTER_MIN_CRITICAL=5
# ============================================================================
section "T4: systemd unit Environment= STUCK_AFTER_MIN_CRITICAL=5"
# Pattern: Per ADR-0072 §Implementation list line 133, systemd unit needs
# `Environment=STUCK_AFTER_MIN_CRITICAL=5` line.
if [[ -r "$SYSTEMD_UNIT" ]]; then
  if grep -Eq '^Environment=STUCK_AFTER_MIN_CRITICAL=5$' "$SYSTEMD_UNIT"; then
    pass "systemd unit has Environment=STUCK_AFTER_MIN_CRITICAL=5"
  else
    fail "systemd unit missing STUCK_AFTER_MIN_CRITICAL=5" \
         "expected '^Environment=STUCK_AFTER_MIN_CRITICAL=5$' line in $SYSTEMD_UNIT per ADR-0072 §Implementation list"
  fi
else
  fail "T4 skipped — systemd unit not readable" "cascade from T3"
fi

# ============================================================================
# T5: docs/CONTEXT-HYGIENE.md §6.3 reflects new defaults (10/5 not 20/3)
# ============================================================================
section "T5: docs/CONTEXT-HYGIENE.md §6.3 reflects new defaults (10 / 5)"
# Pattern: §6.3 decision logic block shows `window = STUCK_AFTER_MIN_CRITICAL (5 min)`
# and `window = STUCK_AFTER_MIN (10 min)`. Old text had 3 / 20.
if [[ -r "$DOC_FILE" ]]; then
  # Look for the §6.3 decision logic block markers
  if grep -A 6 "if pane is likely STUCK:" "$DOC_FILE" 2>/dev/null | grep -q "STUCK_AFTER_MIN_CRITICAL (5 min)" \
     && grep -A 6 "if pane is likely STUCK:" "$DOC_FILE" 2>/dev/null | grep -q "STUCK_AFTER_MIN          (10 min)"; then
    pass "§6.3 decision logic shows new defaults (10 / 5)"
  else
    fail "§6.3 still has old defaults" \
         "expected 'STUCK_AFTER_MIN_CRITICAL (5 min)' and 'STUCK_AFTER_MIN (10 min)' in §6.3 block per ADR-0072 §Layer 1"
  fi
else
  fail "docs/CONTEXT-HYGIENE.md not readable" "expected '$DOC_FILE' to exist"
fi

# ============================================================================
# T6: docs/CONTEXT-HYGIENE.md §6.4 tunables table reflects new defaults
# ============================================================================
section "T6: docs/CONTEXT-HYGIENE.md §6.4 tunables table reflects new defaults"
# Pattern: §6.4 table rows `| STUCK_AFTER_MIN | 10 |` and `| STUCK_AFTER_MIN_CRITICAL | 5 |`.
if [[ -r "$DOC_FILE" ]]; then
  if grep -Eq '\| `?STUCK_AFTER_MIN`? \| 10 \|' "$DOC_FILE" \
     && grep -Eq '\| `?STUCK_AFTER_MIN_CRITICAL`? \| 5 \|' "$DOC_FILE"; then
    pass "§6.4 tunables table shows new defaults (10 / 5)"
  else
    fail "§6.4 tunables table has wrong defaults" \
         "expected '| STUCK_AFTER_MIN | 10 |' and '| STUCK_AFTER_MIN_CRITICAL | 5 |' rows per ADR-0072 §Layer 1"
  fi
else
  fail "T6 skipped — docs/CONTEXT-HYGIENE.md not readable" "cascade from T5"
fi

# ============================================================================
# T7: Cadence Rule 1 atomic — INDEX.md mentions this test (ADR-0055 §1)
# ============================================================================
section "T7: Cadence Rule 1 atomic per ADR-0055 §1"
# Pattern: Per ADR-0055 §1, this test file + INDEX.md row + impl files must land
# in the SAME commit. Verify INDEX.md has a row referencing d1XX-compact-breathing-room.
if [[ -r "$INDEX_FILE" ]] && grep -q "d1XX-compact-breathing-room" "$INDEX_FILE"; then
  pass "INDEX.md references this test file (Cadence Rule 1 atomic verified)"
else
  fail "INDEX.md missing d1XX row" \
       "expected '$INDEX_FILE' to contain 'd1XX-compact-breathing-room' row (AC7 — Cadence Rule 1 atomic per ADR-0055 §1)"
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
  echo "Once agent-context-monitor.sh + systemd + CONTEXT-HYGIENE.md land in same commit cluster,"
  echo "this test should turn 7/7 GREEN."
  exit 1
else
  printf "${G}${B}GREEN — ALL %d TESTS PASSED${D}\n" "$PASS"
  exit 0
fi
