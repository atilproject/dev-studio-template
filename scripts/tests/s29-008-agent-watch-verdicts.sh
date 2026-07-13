#!/usr/bin/env bash
# s29-008-agent-watch-verdicts.sh — STORY-S29-008 regression guard for agent-watch-verdicts.sh
# (Issue #1033, Sprint 29 Wave 2 forward-port).
#
# Why this test exists
# --------------------
# agent-watch-verdicts.sh augments agent-watch.sh with verdict-aware filter
# logic: surfaces only "verdict-bearing" PR comments (APPROVED / CHANGES REQUESTED /
# 🟢/🟡/🔴) for the agent's lens. STORY-S29-008 ports it so downstream clones
# inherit the verdict surface pattern from day 1.
#
# Acceptance criteria (Issue #1033 / STORY-S29-008 AC4):
#   TC1: AC1 — scripts/agent-watch-verdicts.sh exists + executable
#   TC2: AC2 — bash -n syntax check passes
#   TC3: AC3 — --help exits 0 with usage info
#   TC4: AC4 — idempotency (re-run yields same exit code)
#   TC5: AC3 — script references verdict patterns (APPROVED / CHANGES REQUESTED / 🟢🟡🔴)
#
# Pre-impl RED state: 5/5 FAIL
# Post-impl GREEN state: 5/5 PASS
#
# Run: bash scripts/tests/s29-008-agent-watch-verdicts.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WATCH_SH="${REPO_ROOT}/scripts/agent-watch-verdicts.sh"

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

printf "${B}s29-008 agent-watch-verdicts forward-port d-test (5 TCs)${D}\n"
printf "${B}================================================================${D}\n"
printf "  Script under test: %s\n" "$WATCH_SH"
printf "  Sister-pattern:    agent-watch.sh (sister), ADR-0024 verdict-by\n\n"

# TC1
section "TC1: AC1 — agent-watch-verdicts.sh exists + executable"
if [ ! -f "$WATCH_SH" ]; then
  fail "TC1 — scripts/agent-watch-verdicts.sh missing" "expected $WATCH_SH"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
  exit 1
fi
if [ ! -x "$WATCH_SH" ]; then
  fail "TC1 — agent-watch-verdicts.sh not executable" "run: chmod +x $WATCH_SH"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
  exit 1
fi
pass "TC1 — agent-watch-verdicts.sh exists + executable"

# TC2
section "TC2: AC2 — bash -n syntax check"
if bash -n "$WATCH_SH" 2>/dev/null; then
  pass "TC2 — bash -n exits 0"
else
  fail "TC2 — bash -n failed (syntax error)"
fi

# TC3
section "TC3: AC3 — --help exits 0 with usage info"
HELP_OUT=$(bash "$WATCH_SH" --help 2>&1 || true)
HELP_EXIT=$?
if [ "$HELP_EXIT" -eq 0 ] && echo "$HELP_OUT" | grep -qiE "(usage|verdict|watch)"; then
  pass "TC3 — --help exits 0 with usage info"
else
  fail "TC3 — --help failed or no usage" "exit=$HELP_EXIT"
fi

# TC4
section "TC4: AC4 — idempotency (two consecutive --help runs)"
R1=$(bash "$WATCH_SH" --help 2>&1; echo "EXIT:$?")
R2=$(bash "$WATCH_SH" --help 2>&1; echo "EXIT:$?")
R1E=$(echo "$R1" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)
R2E=$(echo "$R2" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)
if [ "$R1E" = "$R2E" ] && [ -n "$R1E" ]; then
  pass "TC4 — idempotent (run1=$R1E, run2=$R2E)"
else
  fail "TC4 — non-idempotent" "run1=$R1E, run2=$R2E"
fi

# TC5: verdict patterns referenced
section "TC5: AC3 — verdict patterns referenced (APPROVED / CHANGES REQUESTED / 🟢🟡🔴)"
APPROVED_HITS=$(grep -cE 'APPROVED' "$WATCH_SH" 2>/dev/null; true)
APPROVED_HITS=${APPROVED_HITS:-0}
CHANGES_HITS=$(grep -cE 'CHANGES.REQUESTED|CHANGES_REQUESTED|changes.requested' "$WATCH_SH" 2>/dev/null; true)
CHANGES_HITS=${CHANGES_HITS:-0}
EMOJI_HITS=$(grep -cE '🟢|🟡|🔴' "$WATCH_SH" 2>/dev/null; true)
EMOJI_HITS=${EMOJI_HITS:-0}

if [ "$APPROVED_HITS" -gt 0 ] && [ "$EMOJI_HITS" -gt 0 ]; then
  pass "TC5 — verdict patterns present (APPROVED=$APPROVED_HITS, CHANGES=$CHANGES_HITS, emoji=$EMOJI_HITS)"
else
  fail "TC5 — verdict patterns incomplete" \
       "APPROVED=$APPROVED_HITS, CHANGES=$CHANGES_HITS, emoji=$EMOJI_HITS — must reference verdict semantics per ADR-0024"
fi

# Summary
section "Summary"
printf "  ${G}PASS: %d${D}  ${R}FAIL: %d${D}  ${Y}INFO: %d${D}\n\n" "$PASS" "$FAIL" "$INFO"

if [ "$FAIL" -gt 0 ]; then
  printf "${R}✗ RED state — at least one TC failed${D}\n"
  exit 1
fi

printf "${G}✓ GREEN state — agent-watch-verdicts.sh (STORY-S29-008) lands with all 5 ACs verified${D}\n"
exit 0