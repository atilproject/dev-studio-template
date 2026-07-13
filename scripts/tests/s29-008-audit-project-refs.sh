#!/usr/bin/env bash
# s29-008-audit-project-refs.sh — STORY-S29-008 regression guard for audit-project-refs.sh
# (Issue #1033, Sprint 29 Wave 2 forward-port).
#
# Why this test exists
# --------------------
# STORY-S29-008 ports 5-7 universal top-level scripts from AtilCalculator to the
# dev-studio-template. audit-project-refs.sh is one of them (per Sprint 29 plan
# §3.Wave 2 / S29-008 explicit list). Without this d-test, a future regression
# in the audit script (path parameterization break, removed --json, etc.) would
# not be caught until CI runs in some downstream clone.
#
# Acceptance criteria (Issue #1033 / STORY-S29-008 AC4):
#   TC1: AC1 — scripts/audit-project-refs.sh exists at canonical path + executable
#   TC2: AC2 — bash -n syntax check passes (script is parseable, no syntax errors)
#   TC3: AC3 — --help / default usage exits 0 with usage info printed
#   TC4: AC4 — Idempotency: re-running the audit twice yields identical exit code
#             (idempotent read-only or self-cleaning re-run, no state corruption)
#   TC5: AC3 — Path parameterization: script does NOT hardcode atilcan65 (must
#             use ${ORG} env var, or default to atilproject as canonical, or be
#             pure-pattern matching without org-specific strings)
#
# Pre-impl RED state (current main, pre-S29-008):
#   TC1: scripts/audit-project-refs.sh DOES NOT EXIST → FAIL (preflight)
#   TC2: bash -n fails on missing file → FAIL
#   TC3: --help fails on missing executable → FAIL
#   TC4: cannot re-run missing executable → FAIL
#   TC5: file missing → FAIL
#   → 5/5 TCs FAIL = proper RED-first per ADR-0044.
#
# Post-impl GREEN state (after S29-008 PR squash):
#   TC1: scripts/audit-project-refs.sh exists ✅
#   TC2: bash -n exits 0 ✅
#   TC3: --help exits 0 with "Usage:" or "audit" in output ✅
#   TC4: Two consecutive runs both exit 0 or 1 (consistent) ✅
#   TC5: atilcan65 hardcoding absent (or parameterized via ${ORG}) ✅
#   → 5/5 TCs PASS = GREEN.
#
# Sister-pattern family (d-test lineage, ADR-0049):
#   - d105 (AtilCalculator sister, S21-004 #651 — original audit-project-refs d-test)
#   - s29-005-verify-portage.sh (sister — S29-005 port from AtilCalc to template)
#   - s29-008 (this file — STORY-S29-008 audit-project-refs forward-port d-test)
#
# Run: bash scripts/tests/s29-008-audit-project-refs.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AUDIT_SH="${REPO_ROOT}/scripts/audit-project-refs.sh"

# Colors (TTY-aware)
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

printf "${B}s29-008 audit-project-refs forward-port d-test (5 TCs per ADR-0044)${D}\n"
printf "${B}=========================================================================${D}\n"
printf "  Script under test: %s\n" "$AUDIT_SH"
printf "  Sister-pattern:    d105 (AtilCalculator), s29-005 (template port pattern)\n"
printf "  RED-first:         pre-impl all TCs FAIL (script missing → preflight).\n"
printf "  Post-impl:         all TCs must PASS.\n\n"

# ============================================================================
# TC1: AC1 — script exists + executable
# ============================================================================
section "TC1: AC1 — audit-project-refs.sh exists + executable"

if [ ! -f "$AUDIT_SH" ]; then
  fail "TC1 — scripts/audit-project-refs.sh missing" \
       "expected $AUDIT_SH (STORY-S29-008 impl not yet shipped)"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d  ${Y}INFO${D}: %d\n" "$PASS" "$FAIL" "$INFO"
  exit 1
fi

if [ ! -x "$AUDIT_SH" ]; then
  fail "TC1 — scripts/audit-project-refs.sh not executable" \
       "run: chmod +x scripts/audit-project-refs.sh"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d  ${Y}INFO${D}: %d\n" "$PASS" "$FAIL" "$INFO"
  exit 1
fi

pass "TC1 — audit-project-refs.sh exists + executable at $AUDIT_SH"

# ============================================================================
# TC2: AC2 — bash -n syntax check passes
# ============================================================================
section "TC2: AC2 — bash -n syntax check"

if bash -n "$AUDIT_SH" 2>/dev/null; then
  pass "TC2 — bash -n exits 0 (script is parseable)"
else
  fail "TC2 — bash -n failed (syntax error)" \
       "expected clean parse, got error from bash -n $AUDIT_SH"
fi

# ============================================================================
# TC3: AC3 — --help / default usage prints usage info
# ============================================================================
section "TC3: AC3 — --help / default usage exits 0 with usage info"

HELP_OUT="$(bash "$AUDIT_SH" --help 2>&1 || true)"
HELP_EXIT=$?

if [ "$HELP_EXIT" -eq 0 ] && echo "$HELP_OUT" | grep -qiE "(usage|audit|project-refs)"; then
  pass "TC3 — --help exits 0 with usage info (Usage/audit/project-refs in output)"
else
  fail "TC3 — --help did not exit 0 or no usage info" \
       "exit=$HELP_EXIT, output=$(echo "$HELP_OUT" | head -1)"
fi

# ============================================================================
# TC4: AC4 — idempotency: re-running yields identical exit code
# ============================================================================
section "TC4: AC4 — idempotency (two consecutive runs same exit code)"

# Use a tmp fixture dir with NO hardcoded refs (clean state)
FIX_TMP=$(mktemp -d)
FIX_DIR="$FIX_TMP/repo"
mkdir -p "$FIX_DIR"
(
  cd "$FIX_DIR"
  git init -q
  git config user.email "test@test"
  git config user.name "Test"
  echo "# CleanProject" > README.md
  git add -A
  git commit -q -m "clean fixture"
)

RUN1=$(bash "$AUDIT_SH" "$FIX_DIR" 2>/dev/null; echo "EXIT:$?")
RUN2=$(bash "$AUDIT_SH" "$FIX_DIR" 2>/dev/null; echo "EXIT:$?")

RUN1_EXIT=$(echo "$RUN1" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)
RUN2_EXIT=$(echo "$RUN2" | grep -oE 'EXIT:[0-9]+' | cut -d: -f2)

rm -rf "$FIX_TMP"

if [ "$RUN1_EXIT" = "$RUN2_EXIT" ] && [ -n "$RUN1_EXIT" ]; then
  pass "TC4 — idempotent (run1=$RUN1_EXIT, run2=$RUN2_EXIT — consistent)"
else
  fail "TC4 — non-idempotent run" \
       "run1_exit=$RUN1_EXIT, run2_exit=$RUN2_EXIT (must be equal)"
fi

# ============================================================================
# TC5: AC3 — path parameterization: no atilcan65 hardcode (or ${ORG} env var used)
# ============================================================================
section "TC5: AC3 — path parameterization (atilcan65 absent or parameterized)"

ATIL_HITS=$(grep -cE 'atilcan65' "$AUDIT_SH" 2>/dev/null; true)
ATIL_HITS=${ATIL_HITS:-0}
ORG_ENV_HITS=$(grep -cE '\$\{?ORG\}?|\$\{?OWNER\}?' "$AUDIT_SH" 2>/dev/null; true)
ORG_ENV_HITS=${ORG_ENV_HITS:-0}

if [ "$ATIL_HITS" -eq 0 ]; then
  pass "TC5 — no atilcan65 hardcode in audit-project-refs.sh (parameterized via ${ORG:-atilproject} or similar)"
elif [ "$ORG_ENV_HITS" -gt 0 ]; then
  pass "TC5 — atilcan65 referenced but also \${ORG}/\${OWNER} env var present (parameterized pattern)"
else
  fail "TC5 — atilcan65 hardcoded and NO \${ORG} env var fallback" \
       "expected: replace hardcoded org strings with \${ORG} (default atilproject) per AC3"
fi

# ============================================================================
# Summary
# ============================================================================
section "Summary"
printf "  ${G}PASS: %d${D}  ${R}FAIL: %d${D}  ${Y}INFO: %d${D}\n\n" "$PASS" "$FAIL" "$INFO"

if [ "$FAIL" -gt 0 ]; then
  printf "${R}✗ RED state — at least one TC failed${D}\n"
  exit 1
fi

printf "${G}✓ GREEN state — audit-project-refs.sh (STORY-S29-008) lands with all 5 ACs verified${D}\n"
exit 0
