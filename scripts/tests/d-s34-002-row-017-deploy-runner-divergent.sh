#!/usr/bin/env bash
# d-s34-002-row-017-deploy-runner-divergent.sh — Sprint 34 W4 forward-port
# Test for row 017 of ADR-0075 §B.1 (amended by ADR-0077):
#   scripts/deploy-runner.sh (divergent class — env-driven pattern preserved).
#
# Pre-port template state (f9c399f): MD5 53d56953c241c9723226e3f1e894c49b, 294 lines.
# Post-port target state:           MD5 53d56953c241c9723226e3f1e894c49b, 294 lines.
#                                   impl UNCHANGED (env-driven pattern preserved).
# Classification: divergent (PATCH-FORWARD per ADR-0077 row 017 amendment).
# Forward-port preserves divergent aspect of canonical: AtilCalculator keeps v9.1
# hardcoded; template keeps env-driven pattern (ADR-0047-deploy-automation-pattern).
# Test author: dev lane, 2026-07-26.
# Run: bash scripts/tests/d-s34-002-row-017-deploy-runner-divergent.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="$ROOT/scripts/deploy-runner.sh"
EXPECTED_MD5="53d56953c241c9723226e3f1e894c49b"
EXPECTED_LINES=294

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
# TC3: line count = 294 (env-driven pattern preserved, NOT AtilCalc v9.1 hardcoded)
# ============================================================================
section "TC3: line count = 294 (env-driven pattern preserved, NOT 690 AtilCalc hardcoded)"
actual_lines="$(wc -l < "$TARGET" 2>/dev/null || echo 0)"
if [ "$actual_lines" -eq "$EXPECTED_LINES" ]; then
  ok "line count = $actual_lines (env-driven pattern preserved per ADR-0077 row 017 amendment)"
else
  nok "line count mismatch" "expected $EXPECTED_LINES (env-driven pattern), got $actual_lines (AtilCalc v9.1 hardcoded would be 690)"
fi

# ============================================================================
# TC4: MD5 = 53d56953c241c9723226e3f1e894c49b (impl UNCHANGED, divergent preserved)
# ============================================================================
section "TC4: MD5 = 53d56953c241c9723226e3f1e894c49b (impl UNCHANGED, divergent preserved)"
actual_md5="$(md5sum "$TARGET" 2>/dev/null | awk '{print $1}')"
if [ "$actual_md5" = "$EXPECTED_MD5" ]; then
  ok "MD5 = $actual_md5 (impl UNCHANGED — env-driven pattern preserved per ADR-0077)"
else
  nok "MD5 mismatch" "expected $EXPECTED_MD5 (env-driven stub), got $actual_md5"
fi

# ============================================================================
# TC5: env-var pattern preserved (4 required: SERVICE_NAME, MODULE_PATH, DEPLOY_PORT, HEALTHZ_PATH)
# ============================================================================
section "TC5: env-var pattern preserved (4 required: SERVICE_NAME + MODULE_PATH + DEPLOY_PORT + HEALTHZ_PATH)"
SP33_MARKERS=()
for marker in 'SERVICE_NAME' 'MODULE_PATH' 'DEPLOY_PORT' 'HEALTHZ_PATH'; do
  if grep -q -F "$marker" "$TARGET" 2>/dev/null; then
    SP33_MARKERS+=("$marker")
  fi
done
if [ "${#SP33_MARKERS[@]}" -ge 4 ]; then
  ok "all 4 required env vars present: ${SP33_MARKERS[*]}"
else
  missing=()
  for marker in 'SERVICE_NAME' 'MODULE_PATH' 'DEPLOY_PORT' 'HEALTHZ_PATH'; do
    if ! grep -q -F "$marker" "$TARGET" 2>/dev/null; then
      missing+=("$marker")
    fi
  done
  nok "missing required env vars" "missing: ${missing[*]}"
fi

# ============================================================================
# TC6: PROD_HOSTNAME optional env var (warn-only validation per ADR-0047 §Decision.5)
# ============================================================================
section "TC6: PROD_HOSTNAME optional env var (warn-only validation, lens g)"
if grep -q -F 'PROD_HOSTNAME' "$TARGET" 2>/dev/null; then
  ok "PROD_HOSTNAME optional env var present (warn-only validation per ADR-0047 §Decision.5)"
else
  nok "PROD_HOSTNAME missing" "expected PROD_HOSTNAME optional env var in $TARGET (warn-only validation per ADR-0047)"
fi

# ============================================================================
# TC7: ADR-0047 §Decision.2 nohup+setsid marker preserved (NOT systemctl --user)
# ============================================================================
section "TC7: ADR-0047 §Decision.2 nohup+setsid marker preserved (NOT systemctl --user)"
if grep -q -F 'nohup+setsid' "$TARGET" 2>/dev/null && grep -q -F 'ADR-0047' "$TARGET" 2>/dev/null; then
  ok "ADR-0047 §Decision.2 marker present: nohup+setsid pattern preserved (NOT systemctl --user per template pattern)"
else
  nok "ADR-0047 §Decision.2 marker missing" "expected 'nohup+setsid' + 'ADR-0047' in $TARGET"
fi

# ============================================================================
# TC8: INDEX.md row present (Cadence Rule 1 atomic attestation)
# ============================================================================
section "TC8: INDEX.md row present (Cadence Rule 1 atomic attestation)"
INDEX="$ROOT/scripts/tests/INDEX.md"
if grep -q "d-s34-002-row-017-deploy-runner-divergent" "$INDEX" 2>/dev/null; then
  ok "INDEX.md row present for d-s34-002-row-017"
else
  nok "INDEX.md row missing" "expected 'd-s34-002-row-017-deploy-runner-divergent' in $INDEX"
fi

# ============================================================================
# TC9: CHANGELOG.md entry present (Sprint 34 W4 forward-port row 017)
# ============================================================================
section "TC9: CHANGELOG.md entry present (Sprint 34 W4 forward-port row 017)"
CHANGELOG="$ROOT/CHANGELOG.md"
# Match the SPECIFIC row 017 forward-port entry (NOT the row 012 reference that mentions row 017).
# Unique pattern: 'Sprint 34 W4 forward-port S34-002 row 017' — only the actual row 017 entry has this prefix.
if grep -q "Sprint 34 W4 forward-port S34-002 row 017" "$CHANGELOG" 2>/dev/null; then
  ok "CHANGELOG.md entry present for row 017 (unique 'S34-002 row 017' forward-port prefix)"
else
  nok "CHANGELOG.md entry missing" "expected 'Sprint 34 W4 forward-port S34-002 row 017' in $CHANGELOG (row 012 reference does not count)"
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
  echo "d-s34-002-row-017 REGRESSION PASS — scripts/deploy-runner.sh (ADR-0077 row 017 divergent class) env-driven pattern preserved. 9/9 TCs green."
  exit 0
else
  echo
  echo "d-s34-002-row-017 REGRESSION FAILED — see FAIL lines above."
  exit 1
fi