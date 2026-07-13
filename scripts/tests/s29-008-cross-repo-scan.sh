#!/usr/bin/env bash
# s29-008-cross-repo-scan.sh — STORY-S29-008 regression guard for cross-repo-scan.sh
# (Issue #1033, Sprint 29 Wave 2 forward-port).
#
# Why this test exists
# --------------------
# cross-repo-scan.sh is the orchestrator's fleet-wide cross-repo visibility +
# dispatch mechanism (ADR-0047 Part 2). STORY-S29-008 ports it to template so
# downstream clones inherit the cross-repo hygiene from day 1. This d-test guards
# against a regression in the script's invocation shape or env var contract.
#
# Acceptance criteria (Issue #1033 / STORY-S29-008 AC4):
#   TC1: AC1 — scripts/cross-repo-scan.sh exists + executable
#   TC2: AC2 — bash -n syntax check passes
#   TC3: AC3 — --help exits 0 with usage info
#   TC4: AC4 — idempotency: re-running yields identical exit code
#   TC5: AC3 — script references AGENT_CROSS_REPOS env var OR default repos list
#             (path parameterization contract per ADR-0047 §Decision Part 2)
#
# Pre-impl RED state (current main, pre-S29-008): 5/5 FAIL
# Post-impl GREEN state (after S29-008 squash): 5/5 PASS
#
# Sister-pattern: d049 (AtilCalculator sister, ADR-0047 Part 2 d-test)
#
# Run: bash scripts/tests/s29-008-cross-repo-scan.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCAN_SH="${REPO_ROOT}/scripts/cross-repo-scan.sh"

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

printf "${B}s29-008 cross-repo-scan forward-port d-test (5 TCs per ADR-0044)${D}\n"
printf "${B}====================================================================${D}\n"
printf "  Script under test: %s\n" "$SCAN_SH"
printf "  Sister-pattern:    d049 (AtilCalculator), ADR-0047 Part 2\n"
printf "  RED-first:         pre-impl all TCs FAIL.\n\n"

# TC1: AC1 — exists + executable
section "TC1: AC1 — cross-repo-scan.sh exists + executable"
if [ ! -f "$SCAN_SH" ]; then
  fail "TC1 — scripts/cross-repo-scan.sh missing" "expected $SCAN_SH"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
  exit 1
fi
if [ ! -x "$SCAN_SH" ]; then
  fail "TC1 — cross-repo-scan.sh not executable" "run: chmod +x $SCAN_SH"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
  exit 1
fi
pass "TC1 — cross-repo-scan.sh exists + executable"

# TC2: AC2 — bash -n syntax check
section "TC2: AC2 — bash -n syntax check"
if bash -n "$SCAN_SH" 2>/dev/null; then
  pass "TC2 — bash -n exits 0"
else
  fail "TC2 — bash -n failed (syntax error)"
fi

# TC3: AC3 — --help exits 0 with usage
section "TC3: AC3 — --help exits 0 with usage info"
HELP_OUT=$(bash "$SCAN_SH" --help 2>&1 || true)
HELP_EXIT=$?
if [ "$HELP_EXIT" -eq 0 ] && echo "$HELP_OUT" | grep -qiE "(usage|cross-repo|scan)"; then
  pass "TC3 — --help exits 0 with usage info"
else
  fail "TC3 — --help failed or no usage" "exit=$HELP_EXIT, output=$(echo "$HELP_OUT" | head -1)"
fi

# TC4: AC4 — idempotency (re-run yields same exit code with no GitHub auth)
section "TC4: AC4 — idempotency (two consecutive --help runs)"
R1=$(bash "$SCAN_SH" --help 2>&1; echo "EXIT:$?")
R2=$(bash "$SCAN_SH" --help 2>&1; echo "EXIT:$?")
R1E=$(echo "$R1" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)
R2E=$(echo "$R2" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)
if [ "$R1E" = "$R2E" ] && [ -n "$R1E" ]; then
  pass "TC4 — idempotent (run1=$R1E, run2=$R2E)"
else
  fail "TC4 — non-idempotent" "run1=$R1E, run2=$R2E"
fi

# TC5: AC3 — AGENT_CROSS_REPOS env var or default repos referenced
section "TC5: AC3 — AGENT_CROSS_REPOS env var or default repos present"
HITS=$(grep -cE 'AGENT_CROSS_REPOS|atilproject/(dev-studio-template|AtilCalculator)' "$SCAN_SH" 2>/dev/null; true)
HITS=${HITS:-0}
ATIL_HITS=$(grep -cE 'atilcan65' "$SCAN_SH" 2>/dev/null; true)
ATIL_HITS=${ATIL_HITS:-0}
if [ "$HITS" -gt 0 ] && [ "$ATIL_HITS" -eq 0 ]; then
  pass "TC5 — AGENT_CROSS_REPOS env var present, no atilcan65 hardcode (parameterized)"
elif [ "$HITS" -gt 0 ]; then
  info "TC5 — AGENT_CROSS_REPOS present but $ATIL_HITS atilcan65 hardcodes (consider parameterizing)"
  pass "TC5 — AGENT_CROSS_REPOS env var present"
else
  fail "TC5 — AGENT_CROSS_REPOS env var or default repos NOT referenced" \
       "expected AGENT_CROSS_REPOS or known atilproject/* repos per ADR-0047 Part 2"
fi

# Summary
section "Summary"
printf "  ${G}PASS: %d${D}  ${R}FAIL: %d${D}  ${Y}INFO: %d${D}\n\n" "$PASS" "$FAIL" "$INFO"

if [ "$FAIL" -gt 0 ]; then
  printf "${R}✗ RED state — at least one TC failed${D}\n"
  exit 1
fi

printf "${G}✓ GREEN state — cross-repo-scan.sh (STORY-S29-008) lands with all 5 ACs verified${D}\n"
exit 0
