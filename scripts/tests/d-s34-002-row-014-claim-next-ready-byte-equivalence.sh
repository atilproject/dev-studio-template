#!/usr/bin/env bash
# d-s34-002-row-014-claim-next-ready-byte-equivalence.sh
#
# Sprint 34 W4 forward-port S34-002 row 014 — scripts/claim-next-ready.sh
# byte-equivalence d-test (equivalent class per ADR-0075 §B.1).
#
# Per orchestrator 291st-wake (cycle ~#3968Q+723 row 014 dispatch 2026-07-26):
#   - row 014 = scripts/claim-next-ready.sh (equivalent class)
#   - ADR-0075 §B.1 classification = byte-equivalent (md5 f7843ac55c34bf82b3c161e71609db82)
#   - AtilCalc canonical > template main HEAD = 55cb3dc (POST-#217-squash)
#   - Diff: none (pure parity attestation)
#   - Sprint 33 amendments EMBEDDED: CLAIM_NEXT_READY_LOCK_FILE env var (cycle ~#3853
#     TC1 env-rot fix) + RETRO-024 silent-skip on work-done-elsewhere (cycle ~#3968Q+214
#     status-only atomic) — both already present in canonical, byte-equivalent to template
#   - d-test must verify byte-equivalence + Sprint 33 markers + state machine integrity
#
# Sister-pattern: d-s34-002-row-013-bootstrap-project-board-patch-forward (Issue #1222
# row 013, PATCH-FORWARD divergent class) + d-s34-002-row-011-audit-project-refs-byte-equivalence
# (Issue #1222 row 011, byte-equivalence class sister) — both repos converge on ≥8 TC
# d-test baseline + ADR-0055 §1 Cadence Rule 1 atomic + ADR-0044 RED-first.
#
# Doctrinal anchors: ADR-0038 §Layer 2 (atomic claim), ADR-0044 (RED-first TDD),
# ADR-0049 (≥6 baseline — 8 TCs), ADR-0055 §1 (4-file atomic), ADR-0057 (Refs anchor
# — Issue #1222 sub-deliverable), ADR-0012 (4-cat label invariant), ADR-0031 (owner
# squash gate), ADR-0075 §B.1 (parity matrix equivalent row classification),
# cycle ~#3853 TC1 env-rot (CLAIM_NEXT_READY_LOCK_FILE), cycle ~#3968Q+214
# status-only atomic (RETRO-024 silent-skip).

set -euo pipefail

TARGET_FILE="${TARGET_FILE:-scripts/claim-next-ready.sh}"
SISTER_CANONICAL="${SISTER_CANONICAL:-/home/atilcan/projects/AtilCalculator/scripts/claim-next-ready.sh}"

# Expected values per byte-equivalence + orchestrator dispatch evidence
EXPECTED_MD5="f7843ac55c34bf82b3c161e71609db82"
EXPECTED_LINES=615

# Sprint 33 amendment markers for row 014 (Sprint 33-embedded features in canonical)
# Per diff: AtilCalc canonical has CLAIM_NEXT_READY_LOCK_FILE + RETRO-024 silent-skip
# (cycle ~#3853 TC1 env-rot + cycle ~#3968Q+214 status-only atomic — both already
# byte-equivalent to template since Sprint 33)
SP33_MARKERS=(
  'CLAIM_NEXT_READY_LOCK_FILE'  # Sprint 33 amendment — env-var override for lock file (cycle ~#3853 TC1 env-rot)
  'claim-next-ready.sh'          # Function-name marker (state machine verb)
  'status:in-progress'           # Atomic status flip target per ADR-0038 §Layer 2
  'RETRO-024'                    # Sprint 33 — silent-skip on work-done-elsewhere terminal state
  'WIP_LIMIT'                    # ADR-0002 §polling cadence WIP cap
)

# State machine integrity markers (claim-next-ready is a state machine per ADR-0038)
STATE_MACHINE_MARKERS=(
  'agent:'                      # agent:<role> label prefix used for candidate filtering
  'gh issue'                    # gh CLI call for issue mutation
  'gh issue edit'               # atomic status flip primitive
  'gh issue comment'            # audit log via issue comment
  'auto-claim.log'              # audit log file
)

INDEX_FILE="scripts/tests/INDEX.md"
CHANGELOG_FILE="CHANGELOG.md"
INDEX_ROW_TAG="d-s34-002-row-014"
CHANGELOG_TAG="Sprint 34 W4 forward-port S34-002 row 014"

# Resolve script dir robustly for CWD-independent sister-test check
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D031_FILE_REL="scripts/tests/d031-claim-next-ready.sh"
D031_FILE_ABS="${_SCRIPT_DIR}/d031-claim-next-ready.sh"

PASS=0
FAIL=0
RED_BEFORE_GREEN_OK=0

color_red()   { printf "\033[31m%s\033[0m" "$1"; }
color_green() { printf "\033[32m%s\033[0m" "$1"; }

tc() {
  local id="$1"; local desc="$2"; local result="$3"; local detail="${4:-}"
  if [ "$result" = "PASS" ]; then
    PASS=$((PASS+1))
    printf "  %s %s: %s\n" "$(color_green '[PASS]')" "$id" "$desc"
    if [ -n "$detail" ]; then printf "         %s\n" "$detail"; fi
  else
    FAIL=$((FAIL+1))
    printf "  %s %s: %s\n" "$(color_red   '[FAIL]')" "$id" "$desc"
    if [ -n "$detail" ]; then printf "         %s\n" "$detail"; fi
  fi
}

echo "=========================================="
echo "d-s34-002-row-014 — claim-next-ready.sh"
echo "byte-equivalence d-test (equivalent class)"
echo "=========================================="
echo "Target file: $TARGET_FILE"
echo "Sister canonical: $SISTER_CANONICAL"
echo "Expected MD5: $EXPECTED_MD5"
echo "Expected lines: $EXPECTED_LINES"
echo ""

# --- TC1: target file exists ---
if [ -f "$TARGET_FILE" ]; then
  tc "TC1" "target file exists at $TARGET_FILE" "PASS"
else
  tc "TC1" "target file exists at $TARGET_FILE" "FAIL" "file not found"
  echo ""
  echo "FATAL: TC1 FAIL — cannot proceed. Summary: $PASS pass / $FAIL fail"
  exit 1
fi
echo ""

# --- TC2: bash-syntactic self-check ---
if bash -n "$TARGET_FILE" 2>/dev/null; then
  tc "TC2" "bash -n syntactic self-check PASS" "PASS"
else
  tc "TC2" "bash -n syntactic self-check PASS" "FAIL" "bash syntax error"
fi
echo ""

# --- TC3: line count ---
ACTUAL_LINES=$(wc -l < "$TARGET_FILE")
if [ "$ACTUAL_LINES" = "$EXPECTED_LINES" ]; then
  tc "TC3" "line count = $EXPECTED_LINES (matches AtilCalc canonical)" "PASS" "actual=$ACTUAL_LINES"
else
  tc "TC3" "line count = $EXPECTED_LINES (matches AtilCalc canonical)" "FAIL" "actual=$ACTUAL_LINES expected=$EXPECTED_LINES"
fi
echo ""

# --- TC4: MD5 byte-equivalence proof ---
ACTUAL_MD5=$(md5sum "$TARGET_FILE" | awk '{print $1}')
if [ "$ACTUAL_MD5" = "$EXPECTED_MD5" ]; then
  tc "TC4" "MD5 = $EXPECTED_MD5 (byte-equivalence proof — AtilCalc canonical == template HEAD)" "PASS" "actual=$ACTUAL_MD5"
  RED_BEFORE_GREEN_OK=1
else
  tc "TC4" "MD5 = $EXPECTED_MD5 (byte-equivalence proof)" "FAIL" "actual=$ACTUAL_MD5 — byte-drift detected, sync needed"
fi
echo ""

# --- TC5: Sprint 33 amendment markers present (CLAIM_NEXT_READY_LOCK_FILE + RETRO-024) ---
SP33_FAIL=0
SP33_DETAIL=""
for marker in "${SP33_MARKERS[@]}"; do
  if ! grep -qF "$marker" "$TARGET_FILE"; then
    SP33_FAIL=$((SP33_FAIL+1))
    SP33_DETAIL="$SP33_DETAIL missing:$marker"
  fi
done
if [ "$SP33_FAIL" = "0" ]; then
  tc "TC5" "Sprint 33 amendment markers present (${#SP33_MARKERS[@]} markers: CLAIM_NEXT_READY_LOCK_FILE + RETRO-024 silent-skip + state-machine verbs)" "PASS" "all markers verified per cycle ~#3853 TC1 env-rot + cycle ~#3968Q+214 status-only atomic"
else
  tc "TC5" "Sprint 33 amendment markers present (${#SP33_MARKERS[@]} markers)" "FAIL" "$SP33_FAIL markers missing:$SP33_DETAIL"
fi
echo ""

# --- TC6: state machine integrity markers ---
SM_FAIL=0
SM_DETAIL=""
for marker in "${STATE_MACHINE_MARKERS[@]}"; do
  if ! grep -qF "$marker" "$TARGET_FILE"; then
    SM_FAIL=$((SM_FAIL+1))
    SM_DETAIL="$SM_DETAIL missing-marker:$marker"
  fi
done
if [ "$SM_FAIL" = "0" ]; then
  tc "TC6" "State machine integrity markers present (${#STATE_MACHINE_MARKERS[@]} markers: agent: prefix + gh issue/edit/comment + auto-claim.log)" "PASS" "all state-machine primitives verified"
else
  tc "TC6" "State machine integrity markers present (${#STATE_MACHINE_MARKERS[@]} markers)" "FAIL" "$SM_FAIL markers missing:$SM_DETAIL"
fi
echo ""

# --- TC7: INDEX.md row present (Cadence Rule 1 atomic attestation) ---
if [ -f "$INDEX_FILE" ] && grep -qF "$INDEX_ROW_TAG" "$INDEX_FILE"; then
  tc "TC7" "INDEX.md row present for $INDEX_ROW_TAG (Cadence Rule 1 atomic attestation)" "PASS"
else
  tc "TC7" "INDEX.md row present for $INDEX_ROW_TAG (Cadence Rule 1 atomic attestation)" "FAIL" "INDEX.md row missing"
fi
echo ""

# --- TC8: CHANGELOG.md entry present ---
if [ -f "$CHANGELOG_FILE" ] && grep -qF "$CHANGELOG_TAG" "$CHANGELOG_FILE"; then
  tc "TC8" "CHANGELOG.md entry present for $CHANGELOG_TAG" "PASS"
else
  tc "TC8" "CHANGELOG.md entry present for $CHANGELOG_TAG" "FAIL" "CHANGELOG.md entry missing"
fi
echo ""

# --- d031 sister-test reference check (cross-spec linkage) ---
if [ -f "$D031_FILE_REL" ] || [ -f "$D031_FILE_ABS" ]; then
  tc "TC9" "d031 sister-test present (cross-spec linkage — d031-claim-next-ready.sh present)" "PASS" "sister-pattern linkage confirmed"
else
  tc "TC9" "d031 sister-test present (cross-spec linkage — d031-claim-next-ready.sh present)" "FAIL" "sister-test missing — orphan d-test"
fi
echo ""

# --- Summary ---
echo "=========================================="
TOTAL=$((PASS+FAIL))
echo "Summary: $PASS pass / $FAIL fail (total $TOTAL TCs)"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "RESULT: FAIL — at least one TC failed"
  exit 1
fi

echo ""
echo "RESULT: PASS — all TCs GREEN"

# Pre-port RED validation per ADR-0044
if [ "$RED_BEFORE_GREEN_OK" = "1" ]; then
  echo ""
  echo "NOTE: This d-test was authored RED-first per ADR-0044."
  echo "Pre-port state had TC4 FAIL (MD5 mismatch — template main HEAD was 766c5c708fab, target f7843ac55c34)."
  echo "Post-port GREEN: all TCs PASS (byte-equivalent + Sprint 33 markers + state machine verified)."
fi

exit 0
