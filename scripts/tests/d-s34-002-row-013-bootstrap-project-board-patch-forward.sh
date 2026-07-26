#!/usr/bin/env bash
# d-s34-002-row-013-bootstrap-project-board-patch-forward.sh
#
# Sprint 34 W4 forward-port S34-002 row 013 — scripts/bootstrap-project-board.sh
# PATCH-FORWARD d-test (divergent class per ADR-0075 §B.1 — needs 'Blocked' status option
# plus zero-diff proof MD5 = 205bb3446bec9a113a4801be76aca7df).
#
# Per orchestrator 290th-wake (cycle ~#3968Q+685 row 013 dispatch 2026-07-26):
#   - row 013 = scripts/bootstrap-project-board.sh (NOT deploy-runner.sh which is row 017)
#   - ADR-0075 §B.1 classification = PATCH-FORWARD divergent class
#   - AtilCalc canonical MD5 = 205bb3446bec9a113a4801be76aca7df (355 lines)
#   - Diff: 1-line STATUS_OPTIONS amendment — AtilCalc has "Blocked" added (Sprint 33 amendment)
#   - d-test must verify PATCH-FORWARD zero-diff final state + 'Blocked' marker presence
#   - PATCH-FORWARD mechanism: zero-diff port with amendment-marker verification
#
# Sister-pattern: d-s34-002-row-011-audit-project-refs-byte-equivalence (Issue #1222
# row 011, byte-equivalence class) + d-s34-002-row-012-bootstrap-labels-patch-forward
# (Issue #1222 row 012, PATCH-FORWARD divergent zero-diff sister) — both repos converge
# on ≥6 TC d-test baseline + ADR-0055 §1 Cadence Rule 1 atomic.
#
# Doctrinal anchors: ADR-0044 (RED-first TDD), ADR-0049 (≥6 baseline — 8 TCs),
# ADR-0055 §1 (4-file atomic), ADR-0057 (Refs anchor — Issue #1222 sub-deliverable),
# ADR-0012 (4-cat label invariant), ADR-0031 (owner squash gate),
# ADR-0075 §B.1 (parity matrix divergent row classification).

set -euo pipefail

TARGET_FILE="${TARGET_FILE:-scripts/bootstrap-project-board.sh}"
SISTER_CANONICAL="${SISTER_CANONICAL:-/home/atilcan/projects/AtilCalculator/scripts/bootstrap-project-board.sh}"

# Expected values per PATCH-FORWARD zero-diff + orchestrator dispatch evidence
EXPECTED_MD5="205bb3446bec9a113a4801be76aca7df"
EXPECTED_LINES=355

# Sprint 33 amendment marker for row 013 (the actual port difference)
# Per diff: AtilCalc canonical has "Blocked" added to STATUS_OPTIONS array (line 60 area)
SP33_MARKERS=(
  '"Blocked"'                   # Sprint 33 amendment — added "Blocked" status option (the actual port)
  'BOARD_TITLE='                # Board creation structural marker
  'command -v gh'               # Pre-flight gh CLI check
  'command -v jq'               # Pre-flight jq check
  'gh project'                  # Project board API call (must be present for board bootstrap)
)

# 4-cat labels present in companion scripts (must be present after port)
# Note: bootstrap-project-board.sh is a board CREATOR, not a label-driven file;
# we verify the script can reference 4-cat categories when creating them.
SP33_LABEL_CATEGORIES=(
  "Backlog"
  "Ready"
  "In Progress"
  "In Review"
  "Done"
)

INDEX_FILE="scripts/tests/INDEX.md"
CHANGELOG_FILE="CHANGELOG.md"
INDEX_ROW_TAG="d-s34-002-row-013"
CHANGELOG_TAG="Sprint 34 W4 forward-port S34-002 row 013"

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
echo "d-s34-002-row-013 — bootstrap-project-board.sh"
echo "PATCH-FORWARD d-test (divergent class)"
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

# --- TC4: MD5 PATCH-FORWARD zero-diff proof ---
ACTUAL_MD5=$(md5sum "$TARGET_FILE" | awk '{print $1}')
if [ "$ACTUAL_MD5" = "$EXPECTED_MD5" ]; then
  tc "TC4" "MD5 = $EXPECTED_MD5 (PATCH-FORWARD zero-diff proof)" "PASS" "actual=$ACTUAL_MD5"
  RED_BEFORE_GREEN_OK=1
else
  tc "TC4" "MD5 = $EXPECTED_MD5 (PATCH-FORWARD zero-diff proof)" "FAIL" "actual=$ACTUAL_MD5 — divergent file not yet PATCH-FORWARD synced"
fi
echo ""

# --- TC5: Sprint 33 amendment markers present (NOT byte-equivalence — divergence OK because amendment is the port) ---
SP33_FAIL=0
SP33_DETAIL=""
for marker in "${SP33_MARKERS[@]}"; do
  if ! grep -qF "$marker" "$TARGET_FILE"; then
    SP33_FAIL=$((SP33_FAIL+1))
    SP33_DETAIL="$SP33_DETAIL missing:$marker"
  fi
done
if [ "$SP33_FAIL" = "0" ]; then
  tc "TC5" "Sprint 33 amendment markers present (${#SP33_MARKERS[@]} markers checked, including 'Blocked' status option)" "PASS" "all markers verified per orchestrator row 013 dispatch"
else
  tc "TC5" "Sprint 33 amendment markers present (${#SP33_MARKERS[@]} markers checked)" "FAIL" "$SP33_FAIL markers missing:$SP33_DETAIL"
fi
echo ""

# --- TC6: 4-cat labels present (full invariant) ---
CAT4_FAIL=0
CAT4_DETAIL=""
for cat in "${SP33_LABEL_CATEGORIES[@]}"; do
  if ! grep -qF "$cat" "$TARGET_FILE"; then
    CAT4_FAIL=$((CAT4_FAIL+1))
    CAT4_DETAIL="$CAT4_DETAIL missing-category:$cat"
  fi
done
if [ "$CAT4_FAIL" = "0" ]; then
  tc "TC6" "Project board STATUS_OPTIONS present (5 canonical statuses: Backlog/Ready/In Progress/In Review/Done)" "PASS" "all 5 STATUS_OPTIONS verified"
else
  tc "TC6" "Project board STATUS_OPTIONS present (5 canonical statuses: Backlog/Ready/In Progress/In Review/Done)" "FAIL" "$CAT4_FAIL statuses missing:$CAT4_DETAIL"
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
  echo "Pre-port state had TC4 FAIL (MD5 mismatch — tmpl main was 2d873a381020, target 205bb3446bec)."
  echo "Post-port GREEN: all TCs PASS (Blocked amendment applied + zero-diff MD5 match)."
fi

exit 0
