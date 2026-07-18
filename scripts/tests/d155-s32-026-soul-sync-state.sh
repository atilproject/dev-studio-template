#!/usr/bin/env bash
# d155-s32-026-soul-sync-state.sh — S32-026 tmpl-leads soul-sync state regression test
# (5 TCs, ADR-0049 sister-pattern + Cadence Rule 1 atomic per ADR-0055 §1).
#
# Why this test exists
# --------------------
# S32-026 (Issue #155) was reopened by ORCH (cycle ~#3443) via RETRO-027
# §Retroactive-Close Precondition because architect's reflexive RETRO-024 close
# of Issue #155 lacked an anchor-PR. Cadence Rule 2 §Operational chain step 2/7
# dispatched architect to open an ADR docs PR.
#
# Per Issue #972 Path-Verify Doctrine, architect re-queried ground truth BEFORE
# acting on the dispatch (cycle ~#3475). Result: tmpl is AHEAD of calc by +362B
# orchestrator + +1784B architect (PR #140 brought KAPI HOTFIX + RETRO-027
# blocks). Issue #155's "+5500B / +1440B" premise is OBSOLETE.
#
# This d-test verifies the actual tmpl-leads state so that future retroactive
# closes of similar soul-sync issues can be validated against ground truth.
#
# 5 TCs (per ADR-0049 ≥5 TCs invariant + Cadence Rule 1 atomic per ADR-0055 §1):
#   TC1: tmpl orchestrator.md.tmpl byte count >= calc orchestrator.md (tmpl-leads)
#   TC2: tmpl orchestrator.md.tmpl contains KAPI HOTFIX SOUL AMEND markers
#   TC3: tmpl orchestrator.md.tmpl contains Cadence Rule 2 Retroactive-Close
#        Precondition SOUL AMEND markers
#   TC4: tmpl architect.md.tmpl contains Issue #972 Path-Verify Doctrine
#        SOUL AMEND markers (source of +1784B architect lead)
#   TC5: tmpl orchestrator.md.tmpl contains Issue #414 Dispatch Discipline
#        SOUL AMEND markers + 3-rule pre-flight text
#
# Sister-pattern to:
#   - d-cadence-rule-2-orphan-impl-dispatch.sh (Cadence Rule 2 d-test)
#   - d156-s32-027-adr-port-batch.sh (Wave 3 ADR port batch d-test)
#   - d1138-template-agent-wake-fix-4b.sh (tmpl wake fix d-test sister)
#
# Run: bash scripts/tests/d155-s32-026-soul-sync-state.sh
#
# Exit code: 0 = all pass, 1 = at least one fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TMPL_ORCH="$REPO_ROOT/.claude/agents/orchestrator.md.tmpl"
TMPL_ARCH="$REPO_ROOT/.claude/agents/architect.md.tmpl"
CALC_ORCH="${CALC_ORCH:-/home/atilcan/projects/AtilCalculator/.claude/agents/orchestrator.md}"
CALC_ARCH="${CALC_ARCH:-/home/atilcan/projects/AtilCalculator/.claude/agents/architect.md}"

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
if [ ! -r "$TMPL_ORCH" ]; then
  echo "ERROR: tmpl orchestrator.md.tmpl not found at $TMPL_ORCH" >&2
  exit 127
fi
if [ ! -r "$TMPL_ARCH" ]; then
  echo "ERROR: tmpl architect.md.tmpl not found at $TMPL_ARCH" >&2
  exit 127
fi
if [ ! -r "$CALC_ORCH" ]; then
  echo "ERROR: calc orchestrator.md not found at $CALC_ORCH" >&2
  exit 127
fi
if [ ! -r "$CALC_ARCH" ]; then
  echo "ERROR: calc architect.md not found at $CALC_ARCH" >&2
  exit 127
fi

# ============================================================================
section "TC1: tmpl orchestrator.md.tmpl byte count >= calc orchestrator.md (tmpl-leads)"
TMPL_ORCH_BYTES=$(wc -c < "$TMPL_ORCH")
CALC_ORCH_BYTES=$(wc -c < "$CALC_ORCH")
if [ "$TMPL_ORCH_BYTES" -ge "$CALC_ORCH_BYTES" ]; then
  pass "tmpl orchestrator.md.tmpl ($TMPL_ORCH_BYTES B) >= calc orchestrator.md ($CALC_ORCH_BYTES B) — tmpl-leads invariant holds (delta=+$((TMPL_ORCH_BYTES - CALC_ORCH_BYTES))B)"
else
  fail "tmpl orchestrator.md.tmpl ($TMPL_ORCH_BYTES B) < calc orchestrator.md ($CALC_ORCH_BYTES B) — tmpl-leads invariant VIOLATED (delta=$((TMPL_ORCH_BYTES - CALC_ORCH_BYTES))B)" \
       "Likely cause: a calc-only amendment added since cycle ~#3475 baseline. Re-run diff before any retroactive close."
fi

# ============================================================================
section "TC2: tmpl orchestrator.md.tmpl contains KAPI HOTFIX SOUL AMEND markers"
KAPI_BEGIN_OK=0
KAPI_END_OK=0
if grep -q "^# >>> KAPI HOTFIX SOUL AMEND BEGIN" "$TMPL_ORCH"; then
  KAPI_BEGIN_OK=1
fi
if grep -q "^# <<< KAPI HOTFIX SOUL AMEND END" "$TMPL_ORCH"; then
  KAPI_END_OK=1
fi
if [ "$KAPI_BEGIN_OK" -eq 1 ] && [ "$KAPI_END_OK" -eq 1 ]; then
  pass "KAPI HOTFIX SOUL AMEND block present (begin + end markers found) — Cadence Rule 2 forward-port dispatch doctrine synced"
else
  fail "KAPI HOTFIX SOUL AMEND markers missing (begin=$KAPI_BEGIN_OK, end=$KAPI_END_OK) — likely PR #140 reverted or amend block not landed" \
       "Fix: re-apply KAPI HOTFIX block from calc .claude/agents/orchestrator.md lines 108-147 to tmpl .claude/agents/orchestrator.md.tmpl"
fi

# ============================================================================
section "TC3: tmpl orchestrator.md.tmpl contains Cadence Rule 2 Retroactive-Close Precondition markers"
RETRO_BEGIN_OK=0
RETRO_END_OK=0
if grep -q "^# >>> Cadence Rule 2 Retroactive-Close Precondition SOUL AMEND BEGIN" "$TMPL_ORCH"; then
  RETRO_BEGIN_OK=1
fi
if grep -q "^# <<< Cadence Rule 2 Retroactive-Close Precondition SOUL AMEND END" "$TMPL_ORCH"; then
  RETRO_END_OK=1
fi
if [ "$RETRO_BEGIN_OK" -eq 1 ] && [ "$RETRO_END_OK" -eq 1 ]; then
  pass "Cadence Rule 2 Retroactive-Close Precondition SOUL AMEND block present (begin + end markers found) — RETRO-027 closure-precondition doctrine synced"
else
  fail "RETRO-027 Retroactive-Close Precondition markers missing (begin=$RETRO_BEGIN_OK, end=$RETRO_END_OK)" \
       "Fix: re-apply RETRO-027 block from calc .claude/agents/orchestrator.md lines 149-196 to tmpl"
fi

# ============================================================================
section "TC4: tmpl architect.md.tmpl contains Issue #972 Path-Verify Doctrine SOUL AMEND markers"
ISSUE972_BEGIN_OK=0
ISSUE972_END_OK=0
PATH_VERIFY_TEXT_OK=0
if grep -q "^# >>> Issue #972 SOUL AMEND BEGIN" "$TMPL_ARCH"; then
  ISSUE972_BEGIN_OK=1
fi
if grep -q "^# <<< Issue #972 SOUL AMEND END" "$TMPL_ARCH"; then
  ISSUE972_END_OK=1
fi
if grep -q "Path-Verify Doctrine" "$TMPL_ARCH"; then
  PATH_VERIFY_TEXT_OK=1
fi
if [ "$ISSUE972_BEGIN_OK" -eq 1 ] && [ "$ISSUE972_END_OK" -eq 1 ] && [ "$PATH_VERIFY_TEXT_OK" -eq 1 ]; then
  pass "Issue #972 Path-Verify Doctrine SOUL AMEND block present (begin + end + body markers found) — source of +1784B architect lead"
else
  fail "Issue #972 SOUL AMEND markers missing (begin=$ISSUE972_BEGIN_OK, end=$ISSUE972_END_OK, body=$PATH_VERIFY_TEXT_OK)" \
       "Fix: re-apply Issue #972 SOUL AMEND block to tmpl architect.md.tmpl (sister-pattern to calc-side back-port in S33+)"
fi

# ============================================================================
section "TC5: tmpl orchestrator.md.tmpl + architect.md.tmpl contain Issue #414 SOUL AMEND markers (3-rule pre-flight lives in architect)"
ISSUE414_ORCH_BEGIN_OK=0
ISSUE414_ORCH_END_OK=0
ISSUE414_ARCH_BEGIN_OK=0
ISSUE414_ARCH_END_OK=0
PRE_FLIGHT_OK=0
if grep -q "^# >>> Issue #414 SOUL AMEND BEGIN" "$TMPL_ORCH"; then
  ISSUE414_ORCH_BEGIN_OK=1
fi
if grep -q "^# <<< Issue #414 SOUL AMEND END" "$TMPL_ORCH"; then
  ISSUE414_ORCH_END_OK=1
fi
if grep -q "^# >>> Issue #414 SOUL AMEND BEGIN" "$TMPL_ARCH"; then
  ISSUE414_ARCH_BEGIN_OK=1
fi
if grep -q "^# <<< Issue #414 SOUL AMEND END" "$TMPL_ARCH"; then
  ISSUE414_ARCH_END_OK=1
fi
if grep -q "Pre-verdict re-query" "$TMPL_ARCH" && \
   grep -q "Mid-verdict re-query" "$TMPL_ARCH" && \
   grep -q "Post-verdict verification" "$TMPL_ARCH"; then
  PRE_FLIGHT_OK=1
fi
if [ "$ISSUE414_ORCH_BEGIN_OK" -eq 1 ] && [ "$ISSUE414_ORCH_END_OK" -eq 1 ] && \
   [ "$ISSUE414_ARCH_BEGIN_OK" -eq 1 ] && [ "$ISSUE414_ARCH_END_OK" -eq 1 ] && \
   [ "$PRE_FLIGHT_OK" -eq 1 ]; then
  pass "Issue #414 SOUL AMEND present in BOTH orchestrator (8-step dispatch) + architect (3-rule pre-flight); 3-rule text found in architect.md.tmpl"
else
  fail "Issue #414 SOUL AMEND markers incomplete (orch-begin=$ISSUE414_ORCH_BEGIN_OK, orch-end=$ISSUE414_ORCH_END_OK, arch-begin=$ISSUE414_ARCH_BEGIN_OK, arch-end=$ISSUE414_ARCH_END_OK, pre-flight=$PRE_FLIGHT_OK)" \
       "Fix: re-apply Issue #414 SOUL AMEND blocks to both tmpl orchestrator.md.tmpl + architect.md.tmpl"
fi

# ============================================================================
printf "\n${B}==== SUMMARY ====${D}\n"
printf "  ${G}PASS${D}: %d\n" "$PASS"
printf "  ${R}FAIL${D}: %d\n" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo
  echo "d155 REGRESSION FAILED — tmpl soul-sync state has regressed."
  echo "Action: investigate which soul-sync PR was reverted or skipped, then re-apply."
  echo "Sister-pattern: cycle ~#3475 baseline (tmpl ahead of calc by +362B orchestrator + +1784B architect)."
  exit 1
fi
echo
echo "d155 REGRESSION PASS — tmpl soul-sync state honored (tmpl ahead of calc on both orchestrator + architect)."
exit 0
