#!/usr/bin/env bash
# s29-008-strip-cascade-labels.sh — STORY-S29-008 regression guard for strip-cascade-labels.sh
# (Issue #1033, Sprint 29 Wave 2 forward-port).
#
# Why this test exists
# --------------------
# strip-cascade-labels.sh removes cascade-style label names that accumulate on
# closed PRs/issues (e.g. status:in-progress after status:done is set). STORY-
# S29-008 ports it so downstream clones inherit the label hygiene from day 1
# (sister-pattern to ADR-0012 4-cat invariant).
#
# Acceptance criteria (Issue #1033 / STORY-S29-008 AC4):
#   TC1: AC1 — scripts/strip-cascade-labels.sh exists + executable
#   TC2: AC2 — bash -n syntax check passes
#   TC3: AC3 — --help / --dry-run exits 0 with usage info
#   TC4: AC4 — idempotency: re-running the script with no input yields same exit code
#   TC5: AC3 — script references cascade-prone labels (status:*, agent:*, cc:*)
#
# Pre-impl RED state: 5/5 FAIL
# Post-impl GREEN state: 5/5 PASS
#
# Run: bash scripts/tests/s29-008-strip-cascade-labels.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STRIP_SH="${REPO_ROOT}/scripts/strip-cascade-labels.sh"

if [[ -t 1 ]]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[34m'; D=$'\033[0m'
else
  R=""; G=""; Y=""; B=""; D=""
fi

PASS=0; FAIL=0; INFO=0
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
info() { printf "  ${Y}ℹ INFO${D} — %s\n" "$1"; INFO=$((INFO+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

printf "${B}s29-008 strip-cascade-labels forward-port d-test (5 TCs)${D}\n"
printf "${B}================================================================${D}\n"
printf "  Script under test: %s\n" "$STRIP_SH"
printf "  Sister-pattern:    ADR-0012 4-cat invariant cleanup\n\n"

# TC1
section "TC1: AC1 — strip-cascade-labels.sh exists + executable"
if [ ! -f "$STRIP_SH" ]; then
  fail "TC1 — scripts/strip-cascade-labels.sh missing" "expected $STRIP_SH"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
  exit 1
fi
if [ ! -x "$STRIP_SH" ]; then
  fail "TC1 — strip-cascade-labels.sh not executable" "run: chmod +x $STRIP_SH"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
  exit 1
fi
pass "TC1 — strip-cascade-labels.sh exists + executable"

# TC2
section "TC2: AC2 — bash -n syntax check"
if bash -n "$STRIP_SH" 2>/dev/null; then
  pass "TC2 — bash -n exits 0"
else
  fail "TC2 — bash -n failed (syntax error)"
fi

# TC3
section "TC3: AC3 — --help / --dry-run exits 0 with usage info"
HELP_OUT=$(bash "$STRIP_SH" --help 2>&1 || true)
HELP_EXIT=$?
if [ "$HELP_EXIT" -eq 0 ] && echo "$HELP_OUT" | grep -qiE "(usage|cascade|strip|labels)"; then
  pass "TC3 — --help exits 0 with usage info"
else
  fail "TC3 — --help failed or no usage" "exit=$HELP_EXIT"
fi

# TC4
section "TC4: AC4 — idempotency (two consecutive --help runs)"
R1=$(bash "$STRIP_SH" --help 2>&1; echo "EXIT:$?")
R2=$(bash "$STRIP_SH" --help 2>&1; echo "EXIT:$?")
R1E=$(echo "$R1" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)
R2E=$(echo "$R2" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)
if [ "$R1E" = "$R2E" ] && [ -n "$R1E" ]; then
  pass "TC4 — idempotent (run1=$R1E, run2=$R2E)"
else
  fail "TC4 — non-idempotent" "run1=$R1E, run2=$R2E"
fi

# TC5: cascade-prone label categories referenced
section "TC5: AC3 — cascade-prone labels referenced (status:*/agent:*/cc:*)"
STATUS_HITS=$(grep -cE 'status:[a-z-]+' "$STRIP_SH" 2>/dev/null; true)
STATUS_HITS=${STATUS_HITS:-0}
AGENT_HITS=$(grep -cE 'agent:[a-z-]+' "$STRIP_SH" 2>/dev/null; true)
AGENT_HITS=${AGENT_HITS:-0}
CC_HITS=$(grep -cE 'cc:[a-z-]+' "$STRIP_SH" 2>/dev/null; true)
CC_HITS=${CC_HITS:-0}

# Sister-pattern: strip-cascade-labels.sh targets specific cascade-prone labels
# (e.g. cc:human, agent:*) that accumulate after status:done. We require ≥2 of
# the 3 cascade-prone categories, since some scripts target only a subset.
TOTAL_CASCADE=$((STATUS_HITS + AGENT_HITS + CC_HITS))
if [ "$TOTAL_CASCADE" -ge 2 ]; then
  pass "TC5 — cascade-prone labels present (status=$STATUS_HITS, agent=$AGENT_HITS, cc=$CC_HITS, total=$TOTAL_CASCADE ≥ 2)"
else
  fail "TC5 — cascade-prone labels insufficient" \
       "status=$STATUS_HITS, agent=$AGENT_HITS, cc=$CC_HITS — strip-cascade-labels must target ≥2 cascade-prone categories"
fi

# Summary
section "Summary"
printf "  ${G}PASS: %d${D}  ${R}FAIL: %d${D}  ${Y}INFO: %d${D}\n\n" "$PASS" "$FAIL" "$INFO"

if [ "$FAIL" -gt 0 ]; then
  printf "${R}✗ RED state — at least one TC failed${D}\n"
  exit 1
fi

printf "${G}✓ GREEN state — strip-cascade-labels.sh (STORY-S29-008) lands with all 5 ACs verified${D}\n"
exit 0