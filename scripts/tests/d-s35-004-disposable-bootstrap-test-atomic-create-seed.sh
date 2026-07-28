#!/usr/bin/env bash
# d-s35-004-disposable-bootstrap-test-atomic-create-seed.sh —
#   Sprint 35 S35-004 RED-first d-test verifying Issue #1254 fix:
#   disposable-bootstrap-test.yml MUST use `gh repo create --push --source .` for
#   ATOMIC create + seed, eliminating the separate seed step that hit github-actions[bot]
#   no cross-repo push permission on Run #3 (30376196420).
#
# Why this test exists
# --------------------
# Run #3 (30376196420) RED @ 2026-07-28T16:01:09Z at step 2.5 — workflow used a
# separate seed step (`git remote add + git push + git remote remove`) that
# authenticated as github-actions[bot] (auto GITHUB_TOKEN identity) instead of
# ATILPROJECT_DISPOSABLE_TOKEN. Server returned HTTP 403 "Permission to
# atilproject/<repo>.git denied to github-actions[bot]".
#
# The fix collapses step 2 (Create) + step 2.5 (Seed) into a single
# `gh repo create --push --source .` invocation. gh CLI handles auth internally
# for both API create AND git push, so GH_TOKEN env is honored consistently.
#
# cycle ~#3968Q+1109 NEW DOCTRINE inverse outcome RECURSIVE — secrets-fix from
# Issue #1251 unblocked step 3 (Run #2 GREEN); workflow-design-fix from Issue
# #1252 (PR #228) unblocked step 4 (Run #3 RED at 2.5); this 3rd-order amend
# fixes the token-scope defect at the same step.
#
# Sister-pattern lineage:
#   - d-s35-004-disposable-bootstrap-test-seed-step.sh — Issue #1252 d-test
#     (PR #228 superseded by this 3rd-order amend; the workflow no longer has a
#     separate seed step, so the old d-test would now FAIL post-port — needs
#     to be amended or replaced)
#   - d-s34-004-disposable-bootstrap-test.sh — direct sister d-test (≥6 TCs)
#   - d-s34-005-runner-label-atilcan.sh — workflow-file d-test sister (15 TCs)
#   - d-s35-003-c1-label-check-sprint33-doctrine-forward-port.sh — sister
#   - d096-soul-files-template.sh — d-test framework ≥5 TCs baseline (ADR-0049)
#   - cycle ~#3968Q+847 inline d-test amender pattern — TC5+TC6 amend + TC7+TC8
#     NEW in same commit before sign-off request (per ADR-0044 + cycle ~#3893Q v2)
#
# 10 TCs (≥6 baseline per ADR-0049 + ADR-0044):
#   TC1: workflow file exists at .github/workflows/disposable-bootstrap-test.yml
#   TC2: YAML syntactic check (Python yaml.safe_load parses cleanly)
#   TC3: NEW atomic 'Create + seed disposable public repo' step present (Issue #1254 fix)
#   TC4: Create+seed step INSERTED at step 2 (right after Checkout, before Bootstrap)
#   TC5 (AMENDED): Create+seed step uses secrets.ATILPROJECT_DISPOSABLE_TOKEN (was: Seed step)
#   TC6 (AMENDED): Create+seed step uses `--push --source .` atomic pattern (was: x-access-token URL)
#   TC7 (NEW): `--push` flag present in create step (atomic create+seed signal)
#   TC8 (NEW): old 'Seed new repo with dev-studio-template content' step is REMOVED (regression guard)
#   TC9 (NEW — Issue #231 5th-order fix): `--remote upstream` flag present in gh repo create
#   TC10 (NEW — Issue #231 defense-in-depth): `git remote remove origin` defense before gh repo create
#
# Pre-port RED state (verified 2026-07-28T16:05Z against PR #228 merged workflow):
#   - TC1: PASS (file exists)
#   - TC2: PASS (YAML parses)
#   - TC3: PASS (Create+seed step present after refactor — but with old name)
#   - TC4: PASS (still at step 2 position)
#   - TC5 (amended): PASS (env var still secrets.ATILPROJECT_DISPOSABLE_TOKEN — preserved)
#   - TC6 (amended): FAIL (workflow has no --push --source flags — still uses separate seed)
#   - TC7 (NEW): FAIL (no --push flag in create step — original PR #228 used gh repo create only)
#   - TC8 (NEW): FAIL (seed step still present at step 2.5 — not yet removed)
# Post-port GREEN state (verified 2026-07-28T16:06Z against fixed workflow):
#   - TC1: PASS
#   - TC2: PASS
#   - TC3: PASS
#   - TC4: PASS
#   - TC5: PASS
#   - TC6: PASS (--push --source . pattern present)
#   - TC7: PASS (--push flag present)
#   - TC8: PASS (seed step REMOVED — regression guard holds)
# Expected exit code: 0 (GREEN) per ADR-0044 RED-first VERIFIED.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOWS_DIR="$SCRIPT_DIR/../../.github/workflows"
TARGET_FILE="$WORKFLOWS_DIR/disposable-bootstrap-test.yml"
INDEX_FILE="$SCRIPT_DIR/INDEX.md"
CHANGELOG_FILE="$SCRIPT_DIR/../../CHANGELOG.md"
EXPECTED_NAME="d-s35-004-disposable-bootstrap-test-atomic-create-seed"
EXPECTED_CHANGELOG_PREFIX="Sprint 35 disposable-bootstrap-test atomic create+seed Issue #1254 fix"

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

echo "==== d-s35-004-disposable-bootstrap-test-atomic-create-seed ===="
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

# TC3: NEW atomic 'Create + seed disposable public repo' step present
tc_num=$((tc_num + 1))
create_seed_step=$(grep -E "Create \+ seed disposable public repo" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$create_seed_step" -ge 1 ]]; then
  run_tc "TC${tc_num}: NEW atomic 'Create + seed disposable public repo' step present (Issue #1254 fix)" 0
else
  run_tc "TC${tc_num}: NEW atomic 'Create + seed' step MISSING (Issue #1254 fix not applied)" 1
fi

# TC4: Create+seed step INSERTED at step 2 (right after Checkout, before Bootstrap)
tc_num=$((tc_num + 1))
# Strategy: extract line numbers and verify Create+seed is between Checkout and Bootstrap.
checkout_line=$(grep -n "Checkout dev-studio-template" "$TARGET_FILE" 2>/dev/null | head -1 | cut -d: -f1 | tr -d ' ')
create_seed_line=$(grep -n "Create + seed disposable public repo" "$TARGET_FILE" 2>/dev/null | head -1 | cut -d: -f1 | tr -d ' ')
bootstrap_line=$(grep -n "Bootstrap init + render + labels" "$TARGET_FILE" 2>/dev/null | head -1 | cut -d: -f1 | tr -d ' ')
if [[ -z "$checkout_line" || -z "$create_seed_line" || -z "$bootstrap_line" ]]; then
  run_tc "TC${tc_num}: step ordering check FAILED (checkout='$checkout_line' create_seed='$create_seed_line' bootstrap='$bootstrap_line' — missing)" 1
elif [[ "$create_seed_line" -gt "$checkout_line" && "$create_seed_line" -lt "$bootstrap_line" ]]; then
  run_tc "TC${tc_num}: Create+seed step INSERTED BETWEEN Checkout (line $checkout_line) and Bootstrap (line $bootstrap_line) — at line $create_seed_line" 0
else
  run_tc "TC${tc_num}: Create+seed step NOT between Checkout and Bootstrap (checkout=$checkout_line, create_seed=$create_seed_line, bootstrap=$bootstrap_line)" 1
fi

# TC5 (AMENDED): Create+seed step uses secrets.ATILPROJECT_DISPOSABLE_TOKEN (was: Seed step)
tc_num=$((tc_num + 1))
# Extract the create+seed step block: from '- name: Create + seed' to the next '- name:' at same indent
create_seed_block=$(awk '
  /- name: Create \+ seed disposable public repo/ { in_cs=1; print; next }
  in_cs && /^      - name:/ { in_cs=0; print; next }
  in_cs { print }
' "$TARGET_FILE" 2>/dev/null)
secrets_used=$(echo "$create_seed_block" | grep -cE "secrets\.ATILPROJECT_DISPOSABLE_TOKEN" | tr -d ' ')
hardcoded=$(echo "$create_seed_block" | grep -cE "GH_TOKEN:[[:space:]]*['\"]" | tr -d ' ')
if [[ "$secrets_used" -ge 1 && "$hardcoded" -eq 0 ]]; then
  run_tc "TC${tc_num}: Create+seed step uses secrets.ATILPROJECT_DISPOSABLE_TOKEN (no hardcoded GH_TOKEN) — secrets_used=$secrets_used" 0
else
  run_tc "TC${tc_num}: Create+seed step secrets check FAILED (secrets_used=$secrets_used, hardcoded=$hardcoded)" 1
fi

# TC6 (AMENDED): Create+seed step uses `--push --source .` atomic pattern (was: x-access-token URL)
tc_num=$((tc_num + 1))
push_flag=$(echo "$create_seed_block" | grep -cE -- "--push" | tr -d ' ')
source_flag=$(echo "$create_seed_block" | grep -cE -- "--source" | tr -d ' ')
x_access_token=$(echo "$create_seed_block" | grep -cE "x-access-token:" | tr -d ' ')
if [[ "$push_flag" -ge 1 && "$source_flag" -ge 1 && "$x_access_token" -eq 0 ]]; then
  run_tc "TC${tc_num}: Create+seed step uses --push + --source atomic pattern (no x-access-token URL) — push=$push_flag, source=$source_flag" 0
else
  run_tc "TC${tc_num}: Create+seed step --push --source atomic check FAILED (push=$push_flag, source=$source_flag, x_access_token=$x_access_token)" 1
fi

# TC7 (NEW): `--push` flag present in create step
tc_num=$((tc_num + 1))
push_in_create=$(grep -A 10 "Create + seed disposable public repo" "$TARGET_FILE" 2>/dev/null | grep -cE -- "--push" | tr -d ' ')
if [[ "$push_in_create" -ge 1 ]]; then
  run_tc "TC${tc_num}: --push flag present in create step (atomic create+seed signal, Issue #1254 fix)" 0
else
  run_tc "TC${tc_num}: --push flag NOT found in create step — atomic signal missing" 1
fi

# TC8 (NEW): old 'Seed new repo with dev-studio-template content' step is REMOVED (regression guard)
tc_num=$((tc_num + 1))
seed_step_present=$(grep -E "Seed new repo with dev-studio-template content" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$seed_step_present" -eq 0 ]]; then
  run_tc "TC${tc_num}: old 'Seed new repo with dev-studio-template content' step REMOVED (regression guard holds, Issue #1254 fix applied)" 0
else
  run_tc "TC${tc_num}: old 'Seed new repo with dev-studio-template content' step STILL PRESENT (count=$seed_step_present) — should be removed by Option B refactor" 1
fi

# TC9 (NEW — Issue #231 5th-order fix, Run #4 30384997111 RED at step 3 origin remote conflict):
#   --remote upstream flag is present in `gh repo create` invocation (avoids the
#   name collision with the 'origin' remote that step 2 (actions/checkout) created).
tc_num=$((tc_num + 1))
remote_upstream_flag=$(grep -A 10 "Create + seed disposable public repo" "$TARGET_FILE" 2>/dev/null | grep -cE -- "--remote[[:space:]]+(upstream|[\"']upstream[\"'])" | tr -d ' ')
if [[ "$remote_upstream_flag" -ge 1 ]]; then
  run_tc "TC${tc_num}: --remote upstream flag present in 'Create + seed' step (avoids origin name collision — Issue #231 5th-order fix)" 0
else
  run_tc "TC${tc_num}: --remote upstream flag NOT found in 'Create + seed' step — Issue #231 fix missing (Run #4 30384997111 would still RED)" 1
fi

# TC10 (NEW — Issue #231 5th-order defense-in-depth):
#   `git remote remove origin` defense step is present BEFORE the `gh repo create`
#   invocation (belt + suspenders for the --remote upstream fix).
tc_num=$((tc_num + 1))
git_remote_remove_origin=$(grep -A 12 "Create + seed disposable public repo" "$TARGET_FILE" 2>/dev/null | grep -cE "git remote remove origin" | tr -d ' ')
if [[ "$git_remote_remove_origin" -ge 1 ]]; then
  run_tc "TC${tc_num}: 'git remote remove origin' defense present before gh repo create (Issue #231 defense-in-depth)" 0
else
  run_tc "TC${tc_num}: 'git remote remove origin' defense MISSING — Issue #231 belt+suspenders missing" 1
fi

echo ""
total_tcs=$tc_num
if [ "$failed" -eq 0 ]; then
  echo "✅ All $total_tcs TCs GREEN — Sprint 35 S35-004 atomic create+seed Issue #1254 + Issue #231 5th-order fix verified"
  echo "   Impl PR ready for dev-prepared + owner-squash per ADR-0031 + cycle ~#414 sister pattern"
  echo "   cycle ~#3968Q+1109 inverse outcome RECURSIVE: 5 layers deep on S35-004 (Run #1 → #2 → #3 → #4 → #5)"
  exit 0
else
  echo "❌ $failed TC(s) failed of $total_tcs — RED-first contract per ADR-0044"
  echo ""
  echo "Fix scope (Issue #1254 + Issue #231 Option C):"
  echo "  - Replace step 2 'Create disposable public repo' with atomic 'Create + seed disposable public repo'"
  echo "  - Use gh repo create --push --source . for atomic create+seed"
  echo "  - REMOVE old step 2.5 'Seed new repo with dev-studio-template content'"
  echo "  - env GH_TOKEN: \${{ secrets.ATILPROJECT_DISPOSABLE_TOKEN }} preserved"
  echo "  - ADD 'git remote remove origin || true' defense before gh repo create (Run #4 origin conflict)"
  echo "  - ADD '--remote upstream' flag to gh repo create (avoid origin name collision)"
  echo ""
  echo "Sister-pattern: cycle ~#3968Q+414 dev-prepared + owner-squash workflow"
  echo "Sister-pattern: cycle ~#3968Q+847 inline d-test amender (TC5+TC6 amend, TC7+TC8+TC9+TC10 NEW)"
  echo "Sister-pattern: cycle ~#3968Q+1109 inverse outcome RECURSIVE 5 layers — Run #4 RED at step 3 (origin conflict) → Option C fix"
  echo "Sister-pattern: RETRO-035 LIVE VALIDATION: 'When RED → fix → re-trigger RED at **different step**, investigate next downstream step's data flow'"
  exit 1
fi