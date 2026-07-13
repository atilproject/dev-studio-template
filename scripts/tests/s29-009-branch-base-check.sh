#!/usr/bin/env bash
# s29-009-branch-base-check.sh — STORY-S29-009 regression guard for scripts/pre-push/branch-base-check.sh
# (Issue #1034, Sprint 29 Wave 2 forward-port).
#
# Why this test exists
# --------------------
# branch-base-check.sh detects chain dep pollution (RETRO-009 §1) before push.
# It blocks pushes where origin/main is not an ancestor of HEAD or commits
# reference squash-merge. STORY-S29-009 ports it so downstream clones inherit
# the pre-push chain-dep guard.
#
# Acceptance criteria (Issue #1034 / STORY-S29-009 AC1):
#   TC1: AC1 — scripts/pre-push/branch-base-check.sh exists + executable
#   TC2: AC2 — bash -n syntax check passes
#   TC3: AC3 — script references RETRO-009 §1 doctrine + chain dep pollution detection
#             + rebase fix guidance per ADR-0049 doc contract
#   TC4: AC4 — idempotency: running with no input exits 0 (clean, no refs to check)
#             per ADR-0048 lens d silent-skip pattern
#   TC5: AC3 — git pre-push contract invoked via stdin (no args, stdin-based)
#             + checks origin/main ancestor + scan squash-merge commit messages
#
# Pre-impl RED state: 5/5 FAIL (script missing)
# Post-impl GREEN state: 5/5 PASS
#
# Sister-pattern: d060-branch-base-check.sh (AtilCalculator sister, 9 TCs)
#
# Run: bash scripts/tests/s29-009-branch-base-check.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHECK_SH="${REPO_ROOT}/scripts/pre-push/branch-base-check.sh"

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

printf "${B}s29-009 branch-base-check forward-port d-test (5 TCs)${D}\n"
printf "${B}==================================================================${D}\n"
printf "  Script under test: %s\n" "$CHECK_SH"
printf "  Sister-pattern:    d060 (AtilCalculator), RETRO-009 §1\n\n"

# TC1
section "TC1: AC1 — branch-base-check.sh exists + executable"
if [ ! -f "$CHECK_SH" ]; then
  fail "TC1 — scripts/pre-push/branch-base-check.sh missing" "expected $CHECK_SH"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
  exit 1
fi
if [ ! -x "$CHECK_SH" ]; then
  fail "TC1 — branch-base-check.sh not executable" "run: chmod +x $CHECK_SH"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
  exit 1
fi
pass "TC1 — branch-base-check.sh exists + executable"

# TC2
section "TC2: AC2 — bash -n syntax check"
if bash -n "$CHECK_SH" 2>/dev/null; then
  pass "TC2 — bash -n exits 0"
else
  fail "TC2 — bash -n failed (syntax error)"
fi

# TC3: RETRO-009 §1 + chain dep pollution detection
section "TC3: AC3 — RETRO-009 §1 + chain dep detection doctrine"
RETRO_HITS=$(grep -cE 'RETRO-009' "$CHECK_SH" 2>/dev/null; true)
RETRO_HITS=${RETRO_HITS:-0}
CHAIN_HITS=$(grep -cE 'chain.dep.pollution|chain dep' "$CHECK_SH" 2>/dev/null; true)
CHAIN_HITS=${CHAIN_HITS:-0}
FIX_HITS=$(grep -cE 'git rebase origin/main' "$CHECK_SH" 2>/dev/null; true)
FIX_HITS=${FIX_HITS:-0}

if [ "$RETRO_HITS" -gt 0 ] && [ "$CHAIN_HITS" -gt 0 ] && [ "$FIX_HITS" -gt 0 ]; then
  pass "TC3 — RETRO-009 + chain dep + rebase fix all present (retro=$RETRO_HITS, chain=$CHAIN_HITS, fix=$FIX_HITS)"
else
  fail "TC3 — doctrine or contracts incomplete" \
       "retro=$RETRO_HITS, chain=$CHAIN_HITS, fix=$FIX_HITS — must reference all 3 per ADR-0049"
fi

# TC4: idempotency — empty stdin → exit 0 (silent_skip per ADR-0048 lens d)
section "TC4: AC4 — idempotency (empty stdin → exit 0 silent_skip)"
R1=$(echo -n "" | bash "$CHECK_SH" 2>&1; echo "EXIT:$?")
R1E=$(echo "$R1" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)

R2=$(echo -n "" | bash "$CHECK_SH" 2>&1; echo "EXIT:$?")
R2E=$(echo "$R2" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)

if [ "$R1E" = "0" ] && [ "$R2E" = "0" ] && [ "$R1E" = "$R2E" ]; then
  pass "TC4 — idempotent empty stdin (r1=$R1E, r2=$R2E — both exit 0 silent_skip)"
else
  fail "TC4 — non-idempotent or non-zero empty stdin" "r1=$R1E, r2=$R2E — both should be 0"
fi

# TC5: git pre-push contract: stdin-based + ancestor check + commit scan
section "TC5: AC3 — git pre-push contract (stdin + ancestor + commit scan)"
STDIN_HITS=$(grep -cE 'stdin|pre-push contract' "$CHECK_SH" 2>/dev/null; true)
STDIN_HITS=${STDIN_HITS:-0}
ANCESTOR_HITS=$(grep -cE 'merge-base.*is-ancestor' "$CHECK_SH" 2>/dev/null; true)
ANCESTOR_HITS=${ANCESTOR_HITS:-0}
COMMIT_SCAN=$(grep -cE 'git log.*--format|squash-merge|squashed' "$CHECK_SH" 2>/dev/null; true)
COMMIT_SCAN=${COMMIT_SCAN:-0}

if [ "$STDIN_HITS" -gt 0 ] && [ "$ANCESTOR_HITS" -gt 0 ] && [ "$COMMIT_SCAN" -gt 0 ]; then
  pass "TC5 — pre-push contract: stdin + ancestor + commit scan all present (stdin=$STDIN_HITS, ancestor=$ANCESTOR_HITS, scan=$COMMIT_SCAN)"
else
  fail "TC5 — pre-push contract incomplete" \
       "stdin=$STDIN_HITS, ancestor=$ANCESTOR_HITS, scan=$COMMIT_SCAN — all 3 must be present"
fi

# Summary
section "Summary"
printf "  ${G}PASS: %d${D}  ${R}FAIL: %d${D}  ${Y}INFO: %d${D}\n\n" "$PASS" "$FAIL" "$INFO"

if [ "$FAIL" -gt 0 ]; then
  printf "${R}✗ RED state — at least one TC failed${D}\n"
  exit 1
fi

printf "${G}✓ GREEN state — branch-base-check.sh (STORY-S29-009) lands with all 5 ACs verified${D}\n"
exit 0
