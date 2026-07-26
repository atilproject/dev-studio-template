#!/usr/bin/env bash
# d-s34-002-row-015-cross-repo-close-byte-equivalence.sh — Sprint 34 W4 forward-port
# Test for row 015 of ADR-0075 §B.1: scripts/cross-repo-close.sh (divergent class).
#
# Pre-port template state (b6a61681): MD5 9cd683e70e5b0dbccf2ff5f5c744ee5f, 161 lines.
# Post-port target state:           MD5 a0823334897d4cab863f9e114847563f, 154 lines.
#                                   byte-identical to atilcan65/AtilCalculator canonical.
# Classification: divergent (PATCH-FORWARD per ADR-0075 §B.1 row 015).
# Test author: dev lane, 2026-07-26.
# Run: bash scripts/tests/d-s34-002-row-015-cross-repo-close-byte-equivalence.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="$ROOT/scripts/cross-repo-close.sh"
EXPECTED_MD5="a0823334897d4cab863f9e114847563f"
EXPECTED_LINES=154

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
# TC3: line count = 154 (matches AtilCalc canonical)
# ============================================================================
section "TC3: line count = 154 (matches AtilCalc canonical)"
actual_lines="$(wc -l < "$TARGET" 2>/dev/null || echo 0)"
if [ "$actual_lines" -eq "$EXPECTED_LINES" ]; then
  ok "line count = $actual_lines (matches AtilCalc canonical)"
else
  nok "line count mismatch" "expected $EXPECTED_LINES, got $actual_lines"
fi

# ============================================================================
# TC4: MD5 = a0823334897d4cab863f9e114847563f (byte-equivalence proof)
# ============================================================================
section "TC4: MD5 = a0823334897d4cab863f9e114847563f (byte-equivalence proof)"
actual_md5="$(md5sum "$TARGET" 2>/dev/null | awk '{print $1}')"
if [ "$actual_md5" = "$EXPECTED_MD5" ]; then
  ok "MD5 = $actual_md5 (byte-identical to AtilCalc canonical)"
else
  nok "MD5 mismatch" "expected $EXPECTED_MD5, got $actual_md5"
fi

# ============================================================================
# TC5: Sprint 33 amendment markers present (5 markers)
# ============================================================================
section "TC5: Sprint 33 amendment markers present (CROSS_REPO_CLOSE_TOKEN + ADR-0040 + Issue #293 + Idempotent + Dry-run)"
SP33_MARKERS=()
for marker in 'CROSS_REPO_CLOSE_TOKEN' 'ADR-0040' 'Issue #293' 'Idempotent' 'Dry-run'; do
  if grep -q -F "$marker" "$TARGET" 2>/dev/null; then
    SP33_MARKERS+=("$marker")
  fi
done
if [ "${#SP33_MARKERS[@]}" -ge 5 ]; then
  ok "all 5 Sprint 33 markers present: ${SP33_MARKERS[*]}"
else
  missing=()
  for marker in 'CROSS_REPO_CLOSE_TOKEN' 'ADR-0040' 'Issue #293' 'Idempotent' 'Dry-run'; do
    if ! grep -q -F "$marker" "$TARGET" 2>/dev/null; then
      missing+=("$marker")
    fi
  done
  nok "missing Sprint 33 markers" "missing: ${missing[*]}"
fi

# ============================================================================
# TC6: state machine integrity markers present (5 markers)
# ============================================================================
section "TC6: state machine integrity markers (gh api + gh issue + STATE + Authorization + --dry-run)"
STATE_MACHINE_MARKERS=()
for marker in 'gh api' 'gh issue' 'STATE=' 'Authorization' 'dry-run'; do
  if grep -q -F -e "$marker" "$TARGET" 2>/dev/null; then
    STATE_MACHINE_MARKERS+=("$marker")
  fi
done
if [ "${#STATE_MACHINE_MARKERS[@]}" -ge 5 ]; then
  ok "all 5 state machine markers present: ${STATE_MACHINE_MARKERS[*]}"
else
  missing=()
  for marker in 'gh api' 'gh issue' 'STATE=' 'Authorization' 'dry-run'; do
    if ! grep -q -F -e "$marker" "$TARGET" 2>/dev/null; then
      missing+=("$marker")
    fi
  done
  nok "missing state machine markers" "missing: ${missing[*]}"
fi

# ============================================================================
# TC7: INDEX.md row present (Cadence Rule 1 atomic attestation)
# ============================================================================
section "TC7: INDEX.md row present (Cadence Rule 1 atomic attestation)"
INDEX="$ROOT/scripts/tests/INDEX.md"
if grep -q "d-s34-002-row-015-cross-repo-close-byte-equivalence" "$INDEX" 2>/dev/null; then
  ok "INDEX.md row present for d-s34-002-row-015"
else
  nok "INDEX.md row missing" "expected 'd-s34-002-row-015-cross-repo-close-byte-equivalence' in $INDEX"
fi

# ============================================================================
# TC8: CHANGELOG.md entry present (Sprint 34 W4 forward-port row 015)
# ============================================================================
section "TC8: CHANGELOG.md entry present (Sprint 34 W4 forward-port row 015)"
CHANGELOG="$ROOT/CHANGELOG.md"
if grep -q "row 015" "$CHANGELOG" 2>/dev/null && grep -q "cross-repo-close.sh" "$CHANGELOG" 2>/dev/null; then
  ok "CHANGELOG.md entry present for row 015 + cross-repo-close.sh"
else
  nok "CHANGELOG.md entry missing" "expected 'row 015' + 'cross-repo-close.sh' in $CHANGELOG"
fi

# ============================================================================
# TC9: PATCH-FORWARD marker (template header removed + AtilCalc-specific paths replaced)
# ============================================================================
section "TC9: PATCH-FORWARD applied (template header absent + no AtilCalc-specific paths)"
if ! grep -q "TEMPLATE PORT (Issue #372" "$TARGET" 2>/dev/null && \
   ! grep -q "atilcan65/AtilCalculator" "$TARGET" 2>/dev/null && \
   ! grep -q "atilcan65/dev-studio-template" "$TARGET" 2>/dev/null; then
  ok "PATCH-FORWARD applied: no TEMPLATE PORT header + no AtilCalc-specific paths"
else
  leftover=()
  if grep -q "TEMPLATE PORT (Issue #372" "$TARGET" 2>/dev/null; then leftover+=("TEMPLATE PORT header"); fi
  if grep -q "atilcan65/AtilCalculator" "$TARGET" 2>/dev/null; then leftover+=("atilcan65/AtilCalculator path"); fi
  if grep -q "atilcan65/dev-studio-template" "$TARGET" 2>/dev/null; then leftover+=("atilcan65/dev-studio-template path"); fi
  nok "PATCH-FORWARD incomplete" "leftover: ${leftover[*]}"
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
  echo "d-s34-002-row-015 REGRESSION PASS — scripts/cross-repo-close.sh (ADR-0075 §B.1 row 015 divergent class) PATCH-FORWARD byte-equivalent to AtilCalc canonical. 9/9 TCs green."
  exit 0
else
  echo
  echo "d-s34-002-row-015 REGRESSION FAILED — see FAIL lines above."
  exit 1
fi
