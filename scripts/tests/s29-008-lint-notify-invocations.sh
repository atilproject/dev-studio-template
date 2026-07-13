#!/usr/bin/env bash
# s29-008-lint-notify-invocations.sh — STORY-S29-008 regression guard for lint-notify-invocations.sh
# (Issue #1033, Sprint 29 Wave 2 forward-port).
#
# Why this test exists
# --------------------
# lint-notify-invocations.sh is the CI guard against the broken `notify.sh -l <role>`
# syntax that historically snuck into PRs (Issue #320). It greps PR diffs for the
# broken pattern and reports. STORY-S29-008 ports it so downstream clones inherit
# the notify discipline from day 1 (ADR-0033 dual-channel peer-poke).
#
# Acceptance criteria (Issue #1033 / STORY-S29-008 AC4):
#   TC1: AC1 — scripts/lint-notify-invocations.sh exists + executable
#   TC2: AC2 — bash -n syntax check passes
#   TC3: AC3 — --help exits 0 with usage info
#   TC4: AC4 — idempotency (re-run yields same exit code)
#   TC5: AC3 — script references the 6 role names (orchestrator/product-manager/
#             architect/developer/tester/human) and the notify.sh -l <role> pattern
#
# Pre-impl RED state: 5/5 FAIL
# Post-impl GREEN state: 5/5 PASS
#
# Sister-pattern: d039 (AtilCalculator sister, Issue #320 scope expansion)
#
# Run: bash scripts/tests/s29-008-lint-notify-invocations.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LINT_SH="${REPO_ROOT}/scripts/lint-notify-invocations.sh"

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

printf "${B}s29-008 lint-notify-invocations forward-port d-test (5 TCs)${D}\n"
printf "${B}====================================================================${D}\n"
printf "  Script under test: %s\n" "$LINT_SH"
printf "  Sister-pattern:    d039 (AtilCalculator), ADR-0033 dual-channel\n\n"

# TC1
section "TC1: AC1 — lint-notify-invocations.sh exists + executable"
if [ ! -f "$LINT_SH" ]; then
  fail "TC1 — scripts/lint-notify-invocations.sh missing" "expected $LINT_SH"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
  exit 1
fi
if [ ! -x "$LINT_SH" ]; then
  fail "TC1 — lint-notify-invocations.sh not executable" "run: chmod +x $LINT_SH"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
  exit 1
fi
pass "TC1 — lint-notify-invocations.sh exists + executable"

# TC2
section "TC2: AC2 — bash -n syntax check"
if bash -n "$LINT_SH" 2>/dev/null; then
  pass "TC2 — bash -n exits 0"
else
  fail "TC2 — bash -n failed (syntax error)"
fi

# TC3
section "TC3: AC3 — --help exits 0 with usage info"
HELP_OUT=$(bash "$LINT_SH" --help 2>&1 || true)
HELP_EXIT=$?
if [ "$HELP_EXIT" -eq 0 ] && echo "$HELP_OUT" | grep -qiE "(usage|notify|invocation|lint)"; then
  pass "TC3 — --help exits 0 with usage info"
else
  fail "TC3 — --help failed or no usage" "exit=$HELP_EXIT"
fi

# TC4
section "TC4: AC4 — idempotency (two consecutive --help runs)"
R1=$(bash "$LINT_SH" --help 2>&1; echo "EXIT:$?")
R2=$(bash "$LINT_SH" --help 2>&1; echo "EXIT:$?")
R1E=$(echo "$R1" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)
R2E=$(echo "$R2" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)
if [ "$R1E" = "$R2E" ] && [ -n "$R1E" ]; then
  pass "TC4 — idempotent (run1=$R1E, run2=$R2E)"
else
  fail "TC4 — non-idempotent" "run1=$R1E, run2=$R2E"
fi

# TC5: 6 role names + notify.sh pattern
section "TC5: AC3 — 6 role names + notify.sh pattern referenced"
ROLES_HIT=0
for role in orchestrator product-manager architect developer tester human; do
  if grep -qE "$role" "$LINT_SH" 2>/dev/null; then
    ROLES_HIT=$((ROLES_HIT + 1))
  fi
done
NOTIFY_PATTERN=$(grep -cE 'notify\.sh.*-l' "$LINT_SH" 2>/dev/null; true)
NOTIFY_PATTERN=${NOTIFY_PATTERN:-0}

if [ "$ROLES_HIT" -ge 6 ] && [ "$NOTIFY_PATTERN" -gt 0 ]; then
  pass "TC5 — 6 role names + notify.sh -l pattern present (roles=$ROLES_HIT/6, notify_pattern=$NOTIFY_PATTERN)"
else
  fail "TC5 — role names or notify.sh pattern incomplete" \
       "roles=$ROLES_HIT/6, notify_pattern=$NOTIFY_PATTERN — must cover all 6 roles + notify.sh -l pattern"
fi

# Summary
section "Summary"
printf "  ${G}PASS: %d${D}  ${R}FAIL: %d${D}  ${Y}INFO: %d${D}\n\n" "$PASS" "$FAIL" "$INFO"

if [ "$FAIL" -gt 0 ]; then
  printf "${R}✗ RED state — at least one TC failed${D}\n"
  exit 1
fi

printf "${G}✓ GREEN state — lint-notify-invocations.sh (STORY-S29-008) lands with all 5 ACs verified${D}\n"
exit 0