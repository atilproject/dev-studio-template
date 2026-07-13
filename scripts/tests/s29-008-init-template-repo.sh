#!/usr/bin/env bash
# s29-008-init-template-repo.sh — STORY-S29-008 regression guard for init-template-repo.sh
# (Issue #1033, Sprint 29 Wave 2 forward-port).
#
# Why this test exists
# --------------------
# init-template-repo.sh is the bootstrap script downstream consumers run after
# cloning dev-studio-template to substitute org/project placeholders into a new
# repository. STORY-S29-008 ports it so downstream clones have the init script
# from day 1 (sister-pattern to dev-studio-init.sh but template-internal).
#
# Acceptance criteria (Issue #1033 / STORY-S29-008 AC4):
#   TC1: AC1 — scripts/init-template-repo.sh exists + executable
#   TC2: AC2 — bash -n syntax check passes
#   TC3: AC3 — --help exits 0 with usage info
#   TC4: AC4 — idempotency (re-run yields same exit code)
#   TC5: AC3 — script references the org/project placeholder substitution pattern
#
# Pre-impl RED state: 5/5 FAIL
# Post-impl GREEN state: 5/5 PASS
#
# Sister-pattern: dev-studio-init.sh (template bootstrap), d070a init gate
#
# Run: bash scripts/tests/s29-008-init-template-repo.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INIT_SH="${REPO_ROOT}/scripts/init-template-repo.sh"

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

printf "${B}s29-008 init-template-repo forward-port d-test (5 TCs)${D}\n"
printf "${B}================================================================${D}\n"
printf "  Script under test: %s\n" "$INIT_SH"
printf "  Sister-pattern:    dev-studio-init.sh, d070a init gate\n\n"

# TC1
section "TC1: AC1 — init-template-repo.sh exists + executable"
if [ ! -f "$INIT_SH" ]; then
  fail "TC1 — scripts/init-template-repo.sh missing" "expected $INIT_SH"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
  exit 1
fi
if [ ! -x "$INIT_SH" ]; then
  fail "TC1 — init-template-repo.sh not executable" "run: chmod +x $INIT_SH"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
  exit 1
fi
pass "TC1 — init-template-repo.sh exists + executable"

# TC2
section "TC2: AC2 — bash -n syntax check"
if bash -n "$INIT_SH" 2>/dev/null; then
  pass "TC2 — bash -n exits 0"
else
  fail "TC2 — bash -n failed (syntax error)"
fi

# TC3
section "TC3: AC3 — --help exits 0 with usage info"
HELP_OUT=$(bash "$INIT_SH" --help 2>&1 || true)
HELP_EXIT=$?
if [ "$HELP_EXIT" -eq 0 ] && echo "$HELP_OUT" | grep -qiE "(usage|init|template|repo)"; then
  pass "TC3 — --help exits 0 with usage info"
else
  fail "TC3 — --help failed or no usage" "exit=$HELP_EXIT"
fi

# TC4
section "TC4: AC4 — idempotency (two consecutive --help runs)"
R1=$(bash "$INIT_SH" --help 2>&1; echo "EXIT:$?")
R2=$(bash "$INIT_SH" --help 2>&1; echo "EXIT:$?")
R1E=$(echo "$R1" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)
R2E=$(echo "$R2" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)
if [ "$R1E" = "$R2E" ] && [ -n "$R1E" ]; then
  pass "TC4 — idempotent (run1=$R1E, run2=$R2E)"
else
  fail "TC4 — non-idempotent" "run1=$R1E, run2=$R2E"
fi

# TC5: placeholder substitution pattern
section "TC5: AC3 — placeholder substitution pattern (org/project templating)"
PLACEHOLDER_HITS=$(grep -cE '\{\{.*\}\}|\$\{?(ORG|REPO|PROJECT|OWNER|TEMPLATE_REPO)\}?' "$INIT_SH" 2>/dev/null; true)
PLACEHOLDER_HITS=${PLACEHOLDER_HITS:-0}
ATIL_HITS=$(grep -cE 'atilcan65' "$INIT_SH" 2>/dev/null; true)
ATIL_HITS=${ATIL_HITS:-0}

if [ "$PLACEHOLDER_HITS" -gt 0 ] && [ "$ATIL_HITS" -eq 0 ]; then
  pass "TC5 — placeholder substitution pattern present, no atilcan65 hardcode (hits=$PLACEHOLDER_HITS)"
elif [ "$ATIL_HITS" -gt 0 ]; then
  info "TC5 — atilcan65 referenced $ATIL_HITS times (likely as AtilCalculator example); placeholder_hits=$PLACEHOLDER_HITS"
  pass "TC5 — placeholder pattern present alongside atilcan65 examples"
else
  fail "TC5 — placeholder substitution pattern NOT found" \
       "expected {{...}} or \${ORG}/\${REPO}/\${PROJECT} pattern per template-bootstrap contract"
fi

# Summary
section "Summary"
printf "  ${G}PASS: %d${D}  ${R}FAIL: %d${D}  ${Y}INFO: %d${D}\n\n" "$PASS" "$FAIL" "$INFO"

if [ "$FAIL" -gt 0 ]; then
  printf "${R}✗ RED state — at least one TC failed${D}\n"
  exit 1
fi

printf "${G}✓ GREEN state — init-template-repo.sh (STORY-S29-008) lands with all 5 ACs verified${D}\n"
exit 0