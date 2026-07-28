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
# 14 TCs (≥6 baseline per ADR-0049 + ADR-0044):
#   TC1: workflow file exists at .github/workflows/disposable-bootstrap-test.yml
#   TC2: YAML syntactic check (Python yaml.safe_load parses cleanly)
#   TC3: 'Create + seed disposable public repo' step present (Issue #1254 fix — combined create+seed)
#   TC4: Create+seed step INSERTED at step 2 (right after Checkout, before Bootstrap)
#   TC5 (AMENDED 2x): Create+seed step uses secrets.ATILPROJECT_DISPOSABLE_TOKEN env (preserved across all amends)
#   TC6 (AMENDED 3x): Create+seed step uses explicit x-access-token URL push (was: --push --source atomic; before that: separate seed step)
#   TC7 (AMENDED 2x): old 'Seed new repo with dev-studio-template content' step is REMOVED (regression guard for Issue #1254 fix; was: --push flag present)
#   TC8 (AMENDED): `git remote remove origin` defense before gh repo create (was: --remote upstream flag; Option D drops --remote upstream since Option D does its own remote add)
#   TC9 (NEW — 6th-order fix, Option D belt+suspenders): `gh auth setup-git` present (defense-in-depth for git credential helper)
#   TC10 (NEW — 6th-order fix, Option D explicit credential): `git remote add upstream https://x-access-token:` pattern present (x-access-token URL uses GH_TOKEN credential regardless of git credential helper)
#   TC11 (NEW — 6th-order fix, Option D explicit push): explicit `git push upstream HEAD:main` present (not just --push flag)
#   TC12 (NEW — 6th-order fix, Run #5 regression guard): `--push` flag REMOVED from `gh repo create` invocation (regression guard against Run #5 github-actions[bot] 403 root cause)
#   TC13 (NEW — 7th-order fix, Issue #235 Run #6 RED): `gh repo create ... --public --confirm` uses --confirm flag (deprecated but supported in older gh CLI versions on self-hosted runner; --yes is supported only in newer gh versions)
#   TC14 (NEW — 7th-order fix, Run #6 regression guard): `--yes` flag NOT used in `gh repo create` invocation (Run #6 RCA: runner gh CLI version doesn't recognize --yes; --confirm is the safe cross-version flag)
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
  in_cs && /^      - name:/ { in_cs=0; next }
  in_cs { print }
' "$TARGET_FILE" 2>/dev/null)
secrets_used=$(echo "$create_seed_block" | grep -cE "secrets\.ATILPROJECT_DISPOSABLE_TOKEN" | tr -d ' ')
hardcoded=$(echo "$create_seed_block" | grep -cE "GH_TOKEN:[[:space:]]*['\"]" | tr -d ' ')
if [[ "$secrets_used" -ge 1 && "$hardcoded" -eq 0 ]]; then
  run_tc "TC${tc_num}: Create+seed step uses secrets.ATILPROJECT_DISPOSABLE_TOKEN (no hardcoded GH_TOKEN) — secrets_used=$secrets_used" 0
else
  run_tc "TC${tc_num}: Create+seed step secrets check FAILED (secrets_used=$secrets_used, hardcoded=$hardcoded)" 1
fi

# TC6 (AMENDED 3x): Create+seed step uses explicit x-access-token URL push (was: --push --source atomic; before that: separate seed step).
# Run #5 (30386751399) RED root cause: --push --source . flag uses github-actions[bot] default credential (NOT GH_TOKEN).
# Fix: drop --push --source, use explicit `git remote add upstream x-access-token URL` + `git push upstream HEAD:main`.
tc_num=$((tc_num + 1))
x_access_token_url=$(echo "$create_seed_block" | grep -cE "x-access-token:.*github\.com" | tr -d ' ')
git_push_explicit=$(echo "$create_seed_block" | grep -cE "git push upstream HEAD:main" | tr -d ' ')
if [[ "$x_access_token_url" -ge 1 && "$git_push_explicit" -ge 1 ]]; then
  run_tc "TC${tc_num}: Create+seed step uses explicit x-access-token URL + git push upstream HEAD:main (replaces --push --source, 6th-order Option D)" 0
else
  run_tc "TC${tc_num}: Create+seed step explicit push pattern FAILED (x_access_token_url=$x_access_token_url, git_push_explicit=$git_push_explicit)" 1
fi

# TC7 (AMENDED 2x): old 'Seed new repo with dev-studio-template content' step is REMOVED (regression guard for Issue #1254 fix; was: --push flag present).
tc_num=$((tc_num + 1))
seed_step_present=$(grep -E "Seed new repo with dev-studio-template content" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$seed_step_present" -eq 0 ]]; then
  run_tc "TC${tc_num}: old 'Seed new repo with dev-studio-template content' step REMOVED (regression guard holds, Issue #1254 fix applied)" 0
else
  run_tc "TC${tc_num}: old 'Seed new repo with dev-studio-template content' step STILL PRESENT (count=$seed_step_present) — should be removed by Issue #1254 fix" 1
fi

# TC8 (AMENDED): `git remote remove origin` defense before gh repo create (was: --remote upstream flag).
# Issue #231 5th-order fix defense-in-depth. Option D retains this (still applicable).
tc_num=$((tc_num + 1))
git_remote_remove_origin=$(echo "$create_seed_block" | grep -cE "git remote remove origin" | tr -d ' ')
if [[ "$git_remote_remove_origin" -ge 1 ]]; then
  run_tc "TC${tc_num}: 'git remote remove origin' defense present before gh repo create (Issue #231 defense-in-depth, retained by 6th-order Option D)" 0
else
  run_tc "TC${tc_num}: 'git remote remove origin' defense MISSING — Issue #231 belt+suspenders missing" 1
fi

# TC9 (NEW — 6th-order fix, Option D belt+suspenders, Run #5 30386751399 RED at step 3 github-actions[bot] 403):
#   `gh auth setup-git` defense-in-depth step is present BEFORE the `gh repo create` invocation.
#   This configures git's credential helper to use gh CLI's GH_TOKEN auth for any subsequent
#   git operations (defense-in-depth — works even if the x-access-token URL pattern fails).
tc_num=$((tc_num + 1))
gh_auth_setup_git=$(echo "$create_seed_block" | grep -cE "gh auth setup-git" | tr -d ' ')
if [[ "$gh_auth_setup_git" -ge 1 ]]; then
  run_tc "TC${tc_num}: 'gh auth setup-git' defense-in-depth present (configures git credential helper to use GH_TOKEN — Run #5 root cause)" 0
else
  run_tc "TC${tc_num}: 'gh auth setup-git' defense-in-depth MISSING — 6th-order Option D belt+suspenders missing" 1
fi

# TC10 (NEW — 6th-order fix, Option D explicit credential):
#   `git remote add upstream https://x-access-token:${GH_TOKEN}@github.com/...` pattern present.
#   The x-access-token URL embeds GH_TOKEN, so git push uses GH_TOKEN credential regardless of
#   git credential helper config (works without `gh auth setup-git` too — belt + suspenders).
#   (Note: this is the same x-access-token check as TC6, but verifies the REMOTE ADD step specifically)
tc_num=$((tc_num + 1))
git_remote_add_upstream_xat=$(echo "$create_seed_block" | grep -cE "git remote add upstream.*x-access-token:" | tr -d ' ')
if [[ "$git_remote_add_upstream_xat" -ge 1 ]]; then
  run_tc "TC${tc_num}: 'git remote add upstream https://x-access-token:...' pattern present (explicit credential — 6th-order Option D)" 0
else
  run_tc "TC${tc_num}: 'git remote add upstream x-access-token:' pattern MISSING — 6th-order Option D explicit credential missing" 1
fi

# TC11 (NEW — 6th-order fix, Option D explicit push):
#   Explicit `git push upstream HEAD:main` is present (replaces the --push flag).
#   This is the actual push step that uses GH_TOKEN credential via the x-access-token URL.
tc_num=$((tc_num + 1))
git_push_upstream_main=$(echo "$create_seed_block" | grep -cE "git push upstream HEAD:main" | tr -d ' ')
if [[ "$git_push_upstream_main" -ge 1 ]]; then
  run_tc "TC${tc_num}: explicit 'git push upstream HEAD:main' present (replaces --push flag, uses GH_TOKEN credential)" 0
else
  run_tc "TC${tc_num}: explicit 'git push upstream HEAD:main' MISSING — 6th-order Option D push step missing" 1
fi

# TC12 (NEW — 6th-order fix, Run #5 regression guard):
#   `--push` flag is REMOVED from `gh repo create` invocation (regression guard against
#   the Run #5 (30386751399) RED root cause — --push uses github-actions[bot] default credential).
tc_num=$((tc_num + 1))
gh_repo_create_line=$(echo "$create_seed_block" | grep -E "^[[:space:]]*gh repo create" | tr -d ' ')
push_flag_in_create=$(echo "$gh_repo_create_line" | grep -cE -- "--push" | tr -d ' ')
if [[ "$push_flag_in_create" -eq 0 ]]; then
  run_tc "TC${tc_num}: --push flag REMOVED from 'gh repo create' (Run #5 root cause guard — github-actions[bot] 403 prevention)" 0
else
  run_tc "TC${tc_num}: --push flag STILL PRESENT in 'gh repo create' (count=$push_flag_in_create) — Run #5 root cause would still RED" 1
fi

# TC13 (NEW — 7th-order fix, Issue #235 Run #6 RED): `gh repo create ... --public --confirm` uses --confirm flag.
#   Run #6 (30390499383) RED at 2026-07-28T19:06:43Z with "unknown flag: --yes". Root cause: the
#   self-hosted runner's gh CLI version is older and doesn't support --yes (only --confirm is supported).
#   The --confirm flag is deprecated in newer gh versions but still works in older ones — safe cross-version.
tc_num=$((tc_num + 1))
gh_repo_create_confirm=$(echo "$create_seed_block" | grep -E "^[[:space:]]*gh repo create" | grep -cE -- "--confirm" | tr -d ' ')
if [[ "$gh_repo_create_confirm" -ge 1 ]]; then
  run_tc "TC${tc_num}: 'gh repo create' uses --confirm flag (deprecated but supported in runner gh CLI version — Issue #235 7th-order fix)" 0
else
  run_tc "TC${tc_num}: 'gh repo create' does NOT use --confirm flag — runner would still RED with 'unknown flag'" 1
fi

# TC14 (NEW — 7th-order fix, Run #6 regression guard): `--yes` flag NOT used anywhere in workflow.
#   Run #6 RCA showed --yes is unknown flag in runner's gh CLI version. Any future code that switches
#   back to --yes would re-trigger Run #6 RED. This TC is a regression guard.
tc_num=$((tc_num + 1))
yes_flag_in_create=$(echo "$create_seed_block" | grep -cE -- "--yes" | tr -d ' ')
if [[ "$yes_flag_in_create" -eq 0 ]]; then
  run_tc "TC${tc_num}: --yes flag NOT used in 'gh repo create' (Run #6 regression guard — 'unknown flag: --yes' prevention)" 0
else
  run_tc "TC${tc_num}: --yes flag STILL PRESENT in 'gh repo create' (count=$yes_flag_in_create) — Run #6 root cause would still RED" 1
fi

echo ""
total_tcs=$tc_num
if [ "$failed" -eq 0 ]; then
  echo "✅ All $total_tcs TCs GREEN — Sprint 35 S35-004 atomic create+seed Issue #1254 + Issue #231 5th-order + 6th-order fixes verified"
  echo "   Impl PR ready for dev-prepared + owner-squash per ADR-0031 + cycle ~#414 sister pattern"
  echo "   cycle ~#3968Q+1109 inverse outcome RECURSIVE: 5 layers deep on S35-004 (Run #1 → #2 → #3 → #4 → #5)"
  echo "   6th-order layer (cycle ~#3968Q+1109 NEW LAYER): Run #5 RED at step 3 with github-actions[bot] 403"
  exit 0
else
  echo "❌ $failed TC(s) failed of $total_tcs — RED-first contract per ADR-0044"
  echo ""
  echo "Fix scope (Issue #1254 + Issue #231 Option C + 6th-order Option D):"
  echo "  - Replace step 2 'Create disposable public repo' with atomic 'Create + seed disposable public repo'"
  echo "  - Use gh repo create --push --source . for atomic create+seed"
  echo "  - REMOVE old step 2.5 'Seed new repo with dev-studio-template content'"
  echo "  - env GH_TOKEN: \${{ secrets.ATILPROJECT_DISPOSABLE_TOKEN }} preserved"
  echo "  - ADD 'git remote remove origin || true' defense before gh repo create (Run #4 origin conflict)"
  echo "  - ADD '--remote upstream' flag to gh repo create (avoid origin name collision)"
  echo "  - ADD 'gh auth setup-git' defense-in-depth for git credential helper (Run #5)"
  echo "  - DROP '--push --source .' from gh repo create (Run #5 uses github-actions[bot])"
  echo "  - ADD 'git remote add upstream https://x-access-token:${GH_TOKEN}@...' (uses GH_TOKEN credential)"
  echo "  - ADD explicit 'git push upstream HEAD:main' (replaces --push flag)"
  echo ""
  echo "Sister-pattern: cycle ~#3968Q+414 dev-prepared + owner-squash workflow"
  echo "Sister-pattern: cycle ~#3968Q+847 inline d-test amender (TC5+TC6 amend, TC7+TC8+TC9+TC10 NEW, TC11+TC12+TC13+TC14 NEW)"
  echo "Sister-pattern: cycle ~#3968Q+1109 inverse outcome RECURSIVE 5 layers — Run #4 RED at step 3 (origin conflict) → Option C fix"
  echo "Sister-pattern: cycle ~#3968Q+1109 NEW LAYER 6th-order — Run #5 RED at step 3 (github-actions[bot] 403) → Option D fix"
  echo "Sister-pattern: RETRO-035 LIVE VALIDATION: 'When RED → fix → re-trigger RED at **different step**, investigate next downstream step's data flow'"
  exit 1
fi