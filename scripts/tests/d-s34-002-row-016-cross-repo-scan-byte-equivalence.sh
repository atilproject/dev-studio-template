#!/usr/bin/env bash
# d-s34-002-row-016-cross-repo-scan-byte-equivalence.sh — Sprint 34 W4 forward-port
# Test for row 016 of ADR-0075 §B.1: scripts/cross-repo-scan.sh (equivalent class).
#
# Pre-port template state (ebbfe03): MD5 165f4e830540023bdf6bc241e8f007ba, 252 lines.
# Post-port target state:           MD5 165f4e830540023bdf6bc241e8f007ba, 252 lines.
#                                   byte-identical to atilcan65/AtilCalculator canonical.
# Classification: equivalent (byte-equivalence per ADR-0075 §B.1 row 016).
# Test author: dev lane, 2026-07-26.
# Run: bash scripts/tests/d-s34-002-row-016-cross-repo-scan-byte-equivalence.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="$ROOT/scripts/cross-repo-scan.sh"
EXPECTED_MD5="165f4e830540023bdf6bc241e8f007ba"
EXPECTED_LINES=252

pass=0
fail=0

section() { echo; echo "==== $1 ===="; }
ok()      { echo "  ✓ PASS — $1"; pass=$((pass+1)); }
nok()     { echo "  ✗ FAIL — $1"; echo "    $2"; fail=$((fail+1)); }

# ============================================================================
# TC1: target file exists
# ============================================================================
section "TC1: target file exists"
if [ -f "$TARGET" ]; then
  ok "file exists: $TARGET"
else
  nok "file missing" "expected $TARGET"
fi

# ============================================================================
# TC2: bash -n syntactic self-check
# ============================================================================
section "TC2: bash -n syntactic self-check"
if bash -n "$TARGET" 2>/dev/null; then
  ok "bash -n passes (no syntax errors)"
else
  nok "bash -n failed" "syntactic errors in $TARGET"
fi

# ============================================================================
# TC3: line count = 252 (matches AtilCalc canonical)
# ============================================================================
section "TC3: line count = 252 (matches AtilCalc canonical)"
actual_lines="$(wc -l < "$TARGET" 2>/dev/null || echo 0)"
if [ "$actual_lines" -eq "$EXPECTED_LINES" ]; then
  ok "line count = $actual_lines (matches AtilCalc canonical)"
else
  nok "line count mismatch" "expected $EXPECTED_LINES, got $actual_lines"
fi

# ============================================================================
# TC4: MD5 = 165f4e830540023bdf6bc241e8f007ba (byte-equivalence proof)
# ============================================================================
section "TC4: MD5 = 165f4e830540023bdf6bc241e8f007ba (byte-equivalence proof)"
actual_md5="$(md5sum "$TARGET" 2>/dev/null | awk '{print $1}')"
if [ "$actual_md5" = "$EXPECTED_MD5" ]; then
  ok "MD5 = $actual_md5 (byte-identical to AtilCalc canonical)"
else
  nok "MD5 mismatch" "expected $EXPECTED_MD5, got $actual_md5"
fi

# ============================================================================
# TC5: ADR-0047 Part 2 markers present (4 markers)
# ============================================================================
section "TC5: ADR-0047 Part 2 markers present (ADR-0047 + ADR-0042 + CROSS_REPO_SCAN_INTERVAL_SEC + cross_repo_dispatch)"
SP33_MARKERS=()
for marker in 'ADR-0047' 'ADR-0042' 'CROSS_REPO_SCAN_INTERVAL_SEC' 'cross_repo_dispatch'; do
  if grep -q -F "$marker" "$TARGET" 2>/dev/null; then
    SP33_MARKERS+=("$marker")
  fi
done
if [ "${#SP33_MARKERS[@]}" -ge 4 ]; then
  ok "all 4 ADR-0047 Part 2 markers present: ${SP33_MARKERS[*]}"
else
  missing=()
  for marker in 'ADR-0047' 'ADR-0042' 'CROSS_REPO_SCAN_INTERVAL_SEC' 'cross_repo_dispatch'; do
    if ! grep -q -F "$marker" "$TARGET" 2>/dev/null; then
      missing+=("$marker")
    fi
  done
  nok "missing ADR-0047 Part 2 markers" "missing: ${missing[*]}"
fi

# ============================================================================
# TC6: INDEX.md row present (Cadence Rule 1 atomic attestation)
# ============================================================================
section "TC6: INDEX.md row present (Cadence Rule 1 atomic attestation)"
INDEX="$ROOT/scripts/tests/INDEX.md"
if grep -q "d-s34-002-row-016-cross-repo-scan-byte-equivalence" "$INDEX" 2>/dev/null; then
  ok "INDEX.md row present for d-s34-002-row-016"
else
  nok "INDEX.md row missing" "expected 'd-s34-002-row-016-cross-repo-scan-byte-equivalence' in $INDEX"
fi

# ============================================================================
# TC7: CHANGELOG.md entry present (Sprint 34 W4 forward-port row 016)
# ============================================================================
section "TC7: CHANGELOG.md entry present (Sprint 34 W4 forward-port row 016)"
CHANGELOG="$ROOT/CHANGELOG.md"
if grep -q "row 016" "$CHANGELOG" 2>/dev/null && grep -q "cross-repo-scan.sh" "$CHANGELOG" 2>/dev/null; then
  ok "CHANGELOG.md entry present for row 016 + cross-repo-scan.sh"
else
  nok "CHANGELOG.md entry missing" "expected 'row 016' + 'cross-repo-scan.sh' in $CHANGELOG"
fi

# ============================================================================
# SUMMARY
# ============================================================================
echo
echo "==== SUMMARY ===="
echo "  PASS: $pass"
echo "  FAIL: $fail"

if [ "$fail" -eq 0 ]; then
  echo
  echo "d-s34-002-row-016 REGRESSION PASS — scripts/cross-repo-scan.sh (ADR-0075 §B.1 row 016 equivalent class) byte-identical to AtilCalc canonical. 7/7 TCs green."
  exit 0
else
  echo
  echo "d-s34-002-row-016 REGRESSION FAILED — see FAIL lines above."
  exit 1
fi