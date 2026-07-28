#!/usr/bin/env bash
# d-s35-004-disposable-bootstrap-test-seed-step.sh —
#   Sprint 35 S35-004 RED-first d-test verifying Issue #1252 fix:
#   disposable-bootstrap-test.yml MUST have a 'seed new repo with dev-studio-template
#   content' step inserted between step 2 (Create disposable public repo) and step 3
#   (Bootstrap init + render + labels).
#
# Why this test exists
# --------------------
# Run #2 (30369652086) RED @ 2026-07-28T14:42:15Z at step 4 — workflow cloned the empty
# newly-created repo and tried to run bootstrap scripts that ONLY exist in
# dev-studio-template. The fix inserts a seed step that pushes dev-studio-template
# content to the new repo between create + clone.
#
# cycle ~#3968Q+1109 NEW DOCTRINE inverse outcome — secrets-fix from Issue #1251
# unblocked step 3 but unmasked this downstream workflow design defect (PRD-style
# RCA cascade). Without a RED-first d-test, this regression could resurface.
#
# Sister-pattern lineage:
#   - d-s34-004-disposable-bootstrap-test.sh — direct sister d-test for the workflow
#     itself (≥6 TCs, AC1-AC4 verification of init/render/labels/teardown lifecycle)
#   - d-s34-005-runner-label-atilcan.sh — workflow-file d-test sister (15 TCs)
#   - d-s35-003-c1-label-check-sprint33-doctrine-forward-port.sh — workflow-file
#     d-test sister (10 TCs)
#   - d096-soul-files-template.sh — d-test framework ≥5 TCs baseline (ADR-0049)
#   - cycle ~#3968Q+414 PR self-blocking CI — sister pattern (dev-prepared +
#     owner-squash workflow)
#
# 6 TCs (≥6 baseline per ADR-0049 + ADR-0044):
#   TC1: workflow file exists at .github/workflows/disposable-bootstrap-test.yml
#   TC2: YAML syntactic check (Python yaml.safe_load parses cleanly)
#   TC3: NEW 'Seed new repo with dev-studio-template content' step present
#   TC4: Seed step is INSERTED BETWEEN step 2 (Create) and step 3 (Bootstrap) — order
#   TC5: Seed step uses secrets.ATILPROJECT_DISPOSABLE_TOKEN (NOT hardcoded GH_TOKEN)
#   TC6: Seed step uses x-access-token URL pattern (auth-via-token, not password)
#
# Pre-impl RED state (verified 2026-07-28T15:14Z against pre-fix workflow):
#   - TC1: PASS (file exists)
#   - TC2: PASS (YAML parses)
#   - TC3: FAIL (no 'Seed' step in pre-fix workflow)
#   - TC4: FAIL (no seed step to verify order)
#   - TC5: FAIL (no seed step to verify secrets)
#   - TC6: FAIL (no seed step to verify URL pattern)
# Post-impl GREEN state (verified 2026-07-28T15:15Z against fixed workflow):
#   - TC1: PASS
#   - TC2: PASS
#   - TC3: PASS (seed step now present)
#   - TC4: PASS (positioned between Create and Bootstrap)
#   - TC5: PASS (uses secrets.ATILPROJECT_DISPOSABLE_TOKEN)
#   - TC6: PASS (uses x-access-token URL pattern)
# Expected exit code: 0 (GREEN) per ADR-0044 RED-first VERIFIED.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOWS_DIR="$SCRIPT_DIR/../../.github/workflows"
TARGET_FILE="$WORKFLOWS_DIR/disposable-bootstrap-test.yml"
INDEX_FILE="$SCRIPT_DIR/INDEX.md"
CHANGELOG_FILE="$SCRIPT_DIR/../../CHANGELOG.md"
EXPECTED_NAME="d-s35-004-disposable-bootstrap-test-seed-step"
EXPECTED_CHANGELOG_PREFIX="Sprint 35 disposable-bootstrap-test seed step Issue #1252 fix"

failed=0
tc_num=0

run_tc() {
  local desc="$1"
  local expected_rc="$2"
  if [[ "$expected_rc" -eq 0 ]]; then
    echo "  ✓ PASS — $desc"
  else
    echo "  ✗ FAIL — $desc"
    failed=$((failed + 1))
  fi
}

echo "==== d-s35-004-disposable-bootstrap-test-seed-step ===="
echo "Target: $TARGET_FILE"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# TC1: workflow file exists
tc_num=$((tc_num + 1))
if [ -f "$TARGET_FILE" ]; then
  run_tc "TC${tc_num}: workflow file exists at .github/workflows/disposable-bootstrap-test.yml" 0
else
  run_tc "TC${tc_num}: workflow file MISSING at .github/workflows/disposable-bootstrap-test.yml" 1
  echo ""
  echo "❌ TC1 FAIL is BLOCKING — cannot proceed without target file."
  echo "Result: 0 PASS, 1 FAIL"
  exit 1
fi

# TC2: YAML syntactic check (Python yaml.safe_load)
tc_num=$((tc_num + 1))
if python3 -c "import yaml, sys; yaml.safe_load(open('$TARGET_FILE').read())" 2>/dev/null; then
  run_tc "TC${tc_num}: YAML syntactic check (python yaml.safe_load parses cleanly)" 0
else
  rc=$?
  run_tc "TC${tc_num}: YAML syntactic check FAILED (python yaml.safe_load parse error rc=$rc)" 1
fi

# TC3: NEW 'Seed new repo with dev-studio-template content' step present
tc_num=$((tc_num + 1))
seed_step=$(grep -E "Seed new repo with dev-studio-template content" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$seed_step" -ge 1 ]]; then
  run_tc "TC${tc_num}: NEW 'Seed new repo with dev-studio-template content' step present (Issue #1252 fix)" 0
else
  run_tc "TC${tc_num}: NEW 'Seed new repo with dev-studio-template content' step MISSING (Issue #1252 fix not applied)" 1
fi

# TC4: Seed step is INSERTED BETWEEN step 2 (Create) and step 3 (Bootstrap)
tc_num=$((tc_num + 1))
# Strategy: extract line numbers of 'Create disposable public repo' and
# 'Bootstrap init + render + labels' and 'Seed new repo with dev-studio-template content',
# verify Seed line number is between Create and Bootstrap.
create_line=$(grep -n "Create disposable public repo" "$TARGET_FILE" 2>/dev/null | head -1 | cut -d: -f1 | tr -d ' ')
seed_line=$(grep -n "Seed new repo with dev-studio-template content" "$TARGET_FILE" 2>/dev/null | head -1 | cut -d: -f1 | tr -d ' ')
bootstrap_line=$(grep -n "Bootstrap init + render + labels" "$TARGET_FILE" 2>/dev/null | head -1 | cut -d: -f1 | tr -d ' ')
if [[ -z "$create_line" || -z "$seed_line" || -z "$bootstrap_line" ]]; then
  run_tc "TC${tc_num}: step ordering check FAILED (create='$create_line' seed='$seed_line' bootstrap='$bootstrap_line' — missing)" 1
elif [[ "$seed_line" -gt "$create_line" && "$seed_line" -lt "$bootstrap_line" ]]; then
  run_tc "TC${tc_num}: Seed step INSERTED BETWEEN Create (line $create_line) and Bootstrap (line $bootstrap_line) — seed at line $seed_line" 0
else
  run_tc "TC${tc_num}: Seed step NOT between Create and Bootstrap (create=$create_line, seed=$seed_line, bootstrap=$bootstrap_line)" 1
fi

# TC5: Seed step uses secrets.ATILPROJECT_DISPOSABLE_TOKEN (NOT hardcoded)
tc_num=$((tc_num + 1))
# Extract the seed step block: from '- name: Seed new repo' to the next '- name:' at same indent
seed_block=$(awk '
  /- name: Seed new repo with dev-studio-template content/ { in_seed=1; print; next }
  in_seed && /^      - name:/ { in_seed=0; print; next }
  in_seed { print }
' "$TARGET_FILE" 2>/dev/null)
secrets_used=$(echo "$seed_block" | grep -cE "secrets\.ATILPROJECT_DISPOSABLE_TOKEN" | tr -d ' ')
hardcoded=$(echo "$seed_block" | grep -cE "GH_TOKEN:[[:space:]]*['\"]" | tr -d ' ')
if [[ "$secrets_used" -ge 1 && "$hardcoded" -eq 0 ]]; then
  run_tc "TC${tc_num}: Seed step uses secrets.ATILPROJECT_DISPOSABLE_TOKEN (no hardcoded GH_TOKEN) — secrets_used=$secrets_used" 0
else
  run_tc "TC${tc_num}: Seed step secrets check FAILED (secrets_used=$secrets_used, hardcoded=$hardcoded)" 1
fi

# TC6: Seed step uses x-access-token URL pattern (auth-via-token, not password)
tc_num=$((tc_num + 1))
x_access_token=$(echo "$seed_block" | grep -cE "x-access-token:" | tr -d ' ')
if [[ "$x_access_token" -ge 1 ]]; then
  run_tc "TC${tc_num}: Seed step uses x-access-token URL pattern (auth-via-token, not password)" 0
else
  run_tc "TC${tc_num}: Seed step URL pattern FAILED (no x-access-token: found in seed step)" 1
fi

echo ""
total_tcs=$tc_num
if [ "$failed" -eq 0 ]; then
  echo "✅ All $total_tcs TCs GREEN — Sprint 35 S35-004 disposable-bootstrap-test seed step Issue #1252 fix verified"
  echo "   Impl PR ready for dev-prepared + owner-squash per ADR-0031 + cycle ~#414 sister pattern"
  exit 0
else
  echo "❌ $failed TC(s) failed of $total_tcs — RED-first contract per ADR-0044"
  echo ""
  echo "Fix scope (Issue #1252):"
  echo "  - INSERT new step between step 2 (Create disposable public repo) and step 3 (Bootstrap init + render + labels)"
  echo "  - Step must push dev-studio-template HEAD content to new repo's main branch"
  echo "  - Step must use secrets.ATILPROJECT_DISPOSABLE_TOKEN (owner-configured per Issue #1251 RCA)"
  echo "  - Step must use x-access-token URL pattern for auth-via-token (NOT password)"
  echo ""
  echo "Sister-pattern: cycle ~#3968Q+414 dev-prepared + owner-squash workflow"
  exit 1
fi