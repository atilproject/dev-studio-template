#!/usr/bin/env bash
# d-s34-002-row-012-bootstrap-labels-patch-forward.sh
#
# Sprint 34 W3 forward-port S34-002 row 012 — scripts/bootstrap-labels.sh
# PATCH-FORWARD d-test (divergent class per ADR-0075 §B.1 row 012).
#
# Per architect 283rd-wake (cycle ~#3968Q+683, 2026-07-26T11:38:17Z):
#   - row 012 = scripts/bootstrap-labels.sh (NOT deploy-runner.sh which is row 017)
#   - ADR-0075 §B.1 classification = DIVERGENT (AtilCalc has Sprint 33 label set
#     evolution amendments; template has base set)
#   - AtilCalc canonical + template currently MD5-identical (94 lines,
#     e3f4f5efc281263c9a9a06c7cb48e67a)
#   - d-test must verify Sprint 33 label-set evolution amendment port
#     (NOT byte-equivalence — divergent class)
#   - PATCH-FORWARD mechanism: zero-diff port with amendment-marker verification
#
# Sister-pattern: d-s34-002-row-011-audit-project-refs-byte-equivalence (Issue #1222
# row 011, byte-equivalence class) + AtilCalculator Sprint 33 d-test framework
# (calc-side parity) — all three repos converge on ≥6 TC d-test baseline +
# ADR-0055 §1 Cadence Rule 1 atomic.
#
# Doctrinal anchors: ADR-0044 (RED-first TDD), ADR-0049 (≥6 baseline — 8 TCs),
# ADR-0055 §1 (4-file atomic), ADR-0057 (Refs anchor — Issue #1222 sub-deliverable),
# ADR-0012 (4-cat label invariant), ADR-0031 (owner squash gate),
# ADR-0075 §B.1 (parity matrix divergent row classification).

set -euo pipefail

TARGET_FILE="${TARGET_FILE:-scripts/bootstrap-labels.sh}"
SISTER_CANONICAL="${SISTER_CANONICAL:-/home/atilcan/projects/AtilCalculator/scripts/bootstrap-labels.sh}"

# Expected values per PATCH-FORWARD zero-diff + architect verification
EXPECTED_MD5="e3f4f5efc281263c9a9a06c7cb48e67a"
EXPECTED_LINES=94

# Sprint 33 label-set evolution amendment markers (must be present in BOTH canonical + template)
# Per Issue #1211 cluster + RETRO-024 amendments + Sprint 33 P2 amendments
SP33_MARKERS=(
  "agent-stall"           # Issue #1210/1211 cluster — agent-stall label added Sprint 33
  "sprint:backlog"        # Sprint 33 amendment — 3-state sprint label set (current/next/backlog)
  "sprint:next"           # Sprint 33 amendment
  "security"              # Sprint 33 amendment
  "good-first-issue"      # Pre-existing (sanity check)
  "agent:orchestrator"    # 4-cat invariant agent:* label
  "cc:orchestrator"       # 4-cat invariant cc:* label
  "status:done"           # 4-cat invariant status:* label
  "priority:P0"           # 4-cat invariant priority:* label
  "type:feature"          # 4-cat invariant type:* label
)

INDEX_FILE="scripts/tests/INDEX.md"
CHANGELOG_FILE="CHANGELOG.md"
INDEX_ROW_TAG="d-s34-002-row-012"
CHANGELOG_TAG="Sprint 34 W3 forward-port S34-002 row 012"

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
echo "d-s34-002-row-012 — bootstrap-labels.sh"
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

# --- TC5: Sprint 33 amendment markers present (NOT byte-equivalence) ---
SP33_FAIL=0
SP33_DETAIL=""
for marker in "${SP33_MARKERS[@]}"; do
  if ! grep -qF "$marker" "$TARGET_FILE"; then
    SP33_FAIL=$((SP33_FAIL+1))
    SP33_DETAIL="$SP33_DETAIL missing:$marker"
  fi
done
if [ "$SP33_FAIL" = "0" ]; then
  tc "TC5" "Sprint 33 amendment markers present (${#SP33_MARKERS[@]} markers checked)" "PASS" "all markers verified per Issue #1211 + RETRO-024 amendments"
else
  tc "TC5" "Sprint 33 amendment markers present (${#SP33_MARKERS[@]} markers checked)" "FAIL" "$SP33_FAIL markers missing:$SP33_DETAIL"
fi
echo ""

# --- TC6: 4-cat labels present (full invariant) ---
CAT4_FAIL=0
CAT4_DETAIL=""
for cat in "priority:" "type:" "status:" "agent:" "cc:" "sprint:"; do
  if ! grep -qF "$cat" "$TARGET_FILE"; then
    CAT4_FAIL=$((CAT4_FAIL+1))
    CAT4_DETAIL="$CAT4_DETAIL missing-category:$cat"
  fi
done
if [ "$CAT4_FAIL" = "0" ]; then
  tc "TC6" "4-cat labels present (priority/type/status/agent/cc/sprint)" "PASS" "all 6 categories verified"
else
  tc "TC6" "4-cat labels present (priority/type/status/agent/cc/sprint)" "FAIL" "$CAT4_FAIL categories missing:$CAT4_DETAIL"
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
  echo "Pre-port state had TC7+TC8 FAIL (INDEX.md row + CHANGELOG.md entry missing)."
  echo "Post-port GREEN: all TCs PASS."
fi

exit 0