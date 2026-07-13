#!/usr/bin/env bash
# s29-004-status-label-to-board-disabled.sh — regression test for STORY-S29-004.
#
# Issue #1016 (atilcan65/AtilCalculator): template's status-label-to-board.yml
# has been FAILing in CI history (2026-07-11 13:48:40-41Z, audit §3.1). Root
# cause: workflow tries to push status:* label updates to a non-existent
# Projects v2 board on the template repo.
#
# Fix (STORY-S29-004, design PR atilcan65/AtilCalculator#1026, path a):
#   Add `if: false` to the `sync-status` job in
#   `.github/workflows/status-label-to-board.yml`. Gentler than `git rm`,
#   reversible, preserves file as documentation.
#
# Bug-class defended against:
#   1. `if: false` line missing → workflow re-enabled → FAIL resumes
#   2. `if: false` on wrong key (e.g. workflow-level vs job-level) → silently
#      does not disable → FAIL resumes
#   3. Runs-on / secrets / permissions accidentally stripped during edit
#   4. YAML malformed → workflow file rejected by Actions parser
#   5. STORY-S29-004 attribution comment missing → no regression pin → future
#      agent might "clean up" the comment without realizing it's a load-bearing
#      disable marker
#
# Test cases:
#   T1:  file exists at canonical path (AC2: file present, not deleted)
#   T2:  sync-status job has `if: false` literal on the job-level line (AC2)
#   T3:  YAML is parseable by Python yaml.safe_load (no syntax drift, AC2)
#   T4:  runs-on: ubuntu-latest preserved (S29-001 sister-pattern: not stripped
#        in this PR; S29-001 migrates in a follow-up — disabled state is
#        orthogonal)
#   T5:  STORY-S29-004 attribution comment present (regression pin)
#   T6:  workflow name + on: triggers unchanged (no accidental rename / event
#        removal)
#   T7:  permissions block preserved (regression check vs audit drift)
#
# Exit code: 0 = all pass, 1 = at least one fail.
#
# Run standalone: bash scripts/tests/s29-004-status-label-to-board-disabled.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WF_FILE="$SCRIPT_DIR/../../.github/workflows/status-label-to-board.yml"

# Colors (TTY-aware)
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; B=""; D=""; fi

PASS=0; FAIL=0
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required (for YAML parse)" >&2; exit 127
fi
if [ ! -r "$WF_FILE" ]; then
  echo "ERROR: workflow file not found at $WF_FILE" >&2; exit 127
fi

# ============================================================================
# T1: file exists at canonical path
# ============================================================================
section "T1: workflow file present (AC2: not deleted)"
if [ -f "$WF_FILE" ]; then
  pass "file exists at $WF_FILE"
else
  fail "file missing" "expected $WF_FILE (path a preserves file as documentation)"
  printf "\n${R}Cannot continue — file missing${D}\n" >&2
  exit 1
fi

# ============================================================================
# T2: `if: false` on the sync-status job (job-level, not workflow-level)
# ============================================================================
section "T2: sync-status job has if: false (AC2)"
# Strategy: find the line number of `sync-status:` job header, then check the
# next ~10 lines for a literal `if: false` (with optional trailing comment).
# This is grep-based to avoid awk/bash keyword-collision (`if:`) edge cases.
JOB_LINE=$(grep -nE '^[[:space:]]*sync-status:' "$WF_FILE" | head -1 | cut -d: -f1)
if [ -z "$JOB_LINE" ]; then
  fail "sync-status job header not found" "expected '^sync-status:' (any indent) in $WF_FILE"
else
  # Window: 10 lines starting from the sync-status: header line. The 'if:'
  # literal must appear at the start of a 4-space-indented (job-level) line.
  # YAML structure: jobs: (col 0), sync-status: (col 2), if:/runs-on:/steps: (col 4).
  IF_FALSE_LINE=$(tail -n +"$JOB_LINE" "$WF_FILE" | head -15 | grep -nE '^    if:[[:space:]]*false([[:space:]]*#.*)?$' | head -1)
  if [ -n "$IF_FALSE_LINE" ]; then
    pass "sync-status job has job-level 'if: false' (line $((JOB_LINE + $(echo "$IF_FALSE_LINE" | cut -d: -f1) - 1)))"
  else
    fail "if: false not found at job level on sync-status" \
         "expected literal 'if: false' on a 4-space-indented (job-level) line within the first 15 lines of the sync-status job block (header at line $JOB_LINE)"
  fi
fi

# ============================================================================
# T3: YAML is parseable
# ============================================================================
section "T3: YAML syntactically valid (no parser drift)"
if python3 -c "
import sys, yaml
with open('$WF_FILE') as f:
    doc = yaml.safe_load(f)
if not isinstance(doc, dict):
    sys.exit('not a mapping at root')
if 'jobs' not in doc:
    sys.exit('jobs key missing')
if 'sync-status' not in doc['jobs']:
    sys.exit('sync-status job missing')
if doc['jobs']['sync-status'].get('if') is not False:
    sys.exit('sync-status.if != false')
sys.exit(0)
" 2>/dev/null; then
  pass "YAML parses + sync-status.if is Python False (semantic check)"
else
  fail "YAML parse failed or sync-status.if is not false" \
       "run: python3 -c \"import yaml; yaml.safe_load(open('$WF_FILE'))\" for diagnostic"
fi

# ============================================================================
# T4: runs-on: ubuntu-latest preserved
# ============================================================================
section "T4: runs-on: ubuntu-latest preserved (S29-001 sister-pattern: not stripped here)"
if grep -Eq '^\s+runs-on:\s+ubuntu-latest\s*$' "$WF_FILE"; then
  pass "runs-on: ubuntu-latest still present on sync-status job"
else
  fail "runs-on: ubuntu-latest missing or drifted" \
       "S29-001 migrates to 4-tuple in a follow-up PR; this PR must NOT change runs-on"
fi

# ============================================================================
# T5: STORY-S29-004 attribution comment present (regression pin)
# ============================================================================
section "T5: STORY-S29-004 attribution comment (regression pin)"
if grep -q 'STORY-S29-004' "$WF_FILE"; then
  pass "STORY-S29-004 marker comment present"
else
  fail "STORY-S29-004 marker missing" \
       "expected '# STORY-S29-004:' comment near the if: false line (regression pin)"
fi

# ============================================================================
# T6: workflow name + on: triggers unchanged
# ============================================================================
section "T6: workflow name + on: triggers preserved"
NAME_OK=$(awk '/^name:/{print; exit}' "$WF_FILE" | grep -F "Status Label → Board Sync (ADR-0013)" | wc -l)
ON_OK=$(grep -cE '^on:$' "$WF_FILE")
if [ "$NAME_OK" = "1" ] && [ "$ON_OK" = "1" ]; then
  pass "workflow name + on: trigger block both preserved"
else
  fail "workflow metadata drifted" \
       "name='$NAME_OK' (expect 1), on:='$ON_OK' (expect 1)"
fi

# ============================================================================
# T7: permissions block preserved (audit drift regression check)
# ============================================================================
section "T7: permissions block preserved (audit drift regression check)"
PERMS_OK=0
for perm in "issues: read" "pull-requests: read" "repository-projects: write"; do
  if grep -qF "$perm" "$WF_FILE"; then
    PERMS_OK=$((PERMS_OK + 1))
  fi
done
if [ "$PERMS_OK" = "3" ]; then
  pass "permissions block (3 lines) preserved"
else
  fail "permissions block drifted" "found $PERMS_OK/3 expected lines (issues / pull-requests / repository-projects)"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
if [ "$FAIL" = "0" ]; then
  printf "${G}ALL ${PASS} TESTS PASSED${D}\n"
  exit 0
else
  printf "${R}${FAIL} TEST(S) FAILED${D} (${PASS} passed)\n"
  exit 1
fi