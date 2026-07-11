#!/usr/bin/env bash
# d983-s28-003-forward-port-parity.sh — STORY-S28-003 forward-port parity
# regression test (5 TCs, ADR-0049 sister-pattern).
#
# Why this test exists
# --------------------
# AtilCalculator has scripts/claim-next-ready.sh + scripts/agent-watch.sh with
# the full feature set (Issue #552 --wip-count-only mode + Event Model v4-v7
# additions). The canonical tmpl dev-studio-template ships a thinner version
# of both. STORY-S28-003 (#983, P1) forward-ports calc → tmpl so fresh
# projects cloned from tmpl inherit the full feature set out-of-the-box.
#
# 5 TCs (per docs/backlog/STORY-S28-003.md + ADR-0049 ≥5 TCs invariant):
#   TC1: tmpl claim-next-ready.sh contains '--wip-count-only' mode flag
#        (Issue #552 dual mechanism — calc-specific, NOT in tmpl pre-port)
#   TC2: tmpl claim-next-ready.sh contains 'WIP_COUNT_ONLY' env-flag handling
#        (sister to TC1, structural check on the flag mechanism)
#   TC3: tmpl claim-next-ready.sh LOC ≥ calc's claim-next-ready.sh LOC
#        (forward-port adds features, never strips them — AC of sister-stories)
#   TC4: tmpl agent-watch.sh has Event Model v4 marker 'issue_comment_mention'
#        (ADR-0017 sister-invariant — calc + tmpl must both have it)
#   TC5: tmpl agent-watch.sh has Event Model v6.2 marker 'issue_assigned_any_status'
#        (Issue #113 silent-drop closure — calc + tmpl must both have it)
#
# Sister-pattern to:
#   - d031-claim-next-ready.sh (claim-next-ready behavior regression)
#   - d052-agent-watch-hardening.sh (agent-watch hardening regression)
#   - d051-5-soul-dispatch-discipline.sh (Issue #414 sister-pattern format)
#
# Run: bash scripts/tests/d983-s28-003-forward-port-parity.sh
#
# Exit code: 0 = all pass, 1 = at least one fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAIM_SH="$REPO_ROOT/scripts/claim-next-ready.sh"
WATCH_SH="$REPO_ROOT/scripts/agent-watch.sh"

# --- test framework ---
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

PASS=0; FAIL=0
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; B=""; D=""
fi
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

# --- pre-flight: required artifacts ---
if [ ! -r "$CLAIM_SH" ]; then
  echo "ERROR: claim-next-ready.sh not found at $CLAIM_SH" >&2
  exit 127
fi
if [ ! -r "$WATCH_SH" ]; then
  echo "ERROR: agent-watch.sh not found at $WATCH_SH" >&2
  exit 127
fi

# --- canonical parity baseline ---
# Calc's scripts (source of truth for forward-port) — read by raw path,
# NOT a git dependency. The parity check is structural, not remote-bound.
CALC_CLAIM_SH="${CALC_CLAIM_SH:-/home/atilcan/projects/AtilCalculator/scripts/claim-next-ready.sh}"
CALC_WATCH_SH="${CALC_WATCH_SH:-/home/atilcan/projects/AtilCalculator/scripts/agent-watch.sh}"

# ============================================================================
section "TC1: tmpl claim-next-ready.sh supports --wip-count-only mode (Issue #552)"
if grep -q -- "--wip-count-only" "$CLAIM_SH"; then
  pass "tmpl claim-next-ready.sh declares --wip-count-only mode flag"
else
  fail "tmpl claim-next-ready.sh missing --wip-count-only mode (calc has it, forward-port incomplete)" \
       "expected: 'WIP_COUNT_ONLY=true' branch handling; see calc ${CALC_CLAIM_SH}"
fi

# ============================================================================
section "TC2: tmpl claim-next-ready.sh has WIP_COUNT_ONLY flag-variable handling"
if grep -qE "WIP_COUNT_ONLY" "$CLAIM_SH"; then
  pass "tmpl claim-next-ready.sh has WIP_COUNT_ONLY structural handling"
else
  fail "tmpl claim-next-ready.sh missing WIP_COUNT_ONLY structural handling" \
       "expected: 'if \[ \"\${1:-}\" = \"--wip-count-only\" \"; then WIP_COUNT_ONLY=true' (sister-pattern to calc)"
fi

# ============================================================================
section "TC3: tmpl claim-next-ready.sh LOC ≥ calc's (forward-port never strips)"
TMPL_LOC=$(wc -l < "$CLAIM_SH")
CALC_LOC=0
if [ -r "$CALC_CLAIM_SH" ]; then
  CALC_LOC=$(wc -l < "$CALC_CLAIM_SH")
fi
if [ "$CALC_LOC" -gt 0 ] && [ "$TMPL_LOC" -lt "$CALC_LOC" ]; then
  fail "tmpl claim-next-ready.sh LOC regression" \
       "tmpl=${TMPL_LOC} < calc=${CALC_LOC} — forward-port stripped features (forbidden)"
else
  pass "tmpl claim-next-ready.sh LOC parity (tmpl=${TMPL_LOC}, calc=${CALC_LOC})"
fi

# ============================================================================
section "TC4: tmpl agent-watch.sh has Event Model v4 marker (issue_comment_mention)"
if grep -q "issue_comment_mention" "$WATCH_SH"; then
  pass "tmpl agent-watch.sh declares Event Model v4 issue_comment_mention"
else
  fail "tmpl agent-watch.sh missing Event Model v4 marker" \
       "expected: 'issue_comment_mention' in v4 comment block; ADR-0017 invariant"
fi

# ============================================================================
section "TC5: tmpl agent-watch.sh has Event Model v6.2 marker (issue_assigned_any_status, Issue #113)"
if grep -q "issue_assigned_any_status" "$WATCH_SH"; then
  pass "tmpl agent-watch.sh declares Event Model v6.2 issue_assigned_any_status (silent-drop closure)"
else
  fail "tmpl agent-watch.sh missing Event Model v6.2 marker" \
       "expected: 'issue_assigned_any_status' in v6.2 comment block; Issue #113 silent-drop closure invariant"
fi

# ============================================================================
printf "\n${B}==== SUMMARY ====${D}\n"
printf "  ${G}PASS${D}: %d\n" "$PASS"
printf "  ${R}FAIL${D}: %d\n" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo
  echo "d983 REGRESSION FAILED — STORY-S28-003 forward-port parity violated."
  echo "Fix: copy scripts/claim-next-ready.sh + scripts/agent-watch.sh from AtilCalculator,"
  echo "      apply path-resolution review (Issue #983 open question), update d-tests/INDEX.md."
  exit 1
fi
echo
echo "d983 REGRESSION PASS — STORY-S28-003 forward-port parity honored."
exit 0