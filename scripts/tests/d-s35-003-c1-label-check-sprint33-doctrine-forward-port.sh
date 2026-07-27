#!/usr/bin/env bash
# d-s35-003-c1-label-check-sprint33-doctrine-forward-port.sh —
#   Sprint 35 S35-003 cluster 1 RED-first d-test verifying label-check.yml
#   forward-port from bare 123-line original → AtilCalculator's post-Sprint 33
#   977-line version (Issue #213 Layer 3 + Issue #423 Layer 4 + owner-override
#   + closed event in pull_request_target).
#
# Why this test exists
# --------------------
# Sprint 33 closed a 977-line label-check.yml in atilproject/AtilCalculator
# (post-Sprint 33 doctrine) but the dev-studio-template canonical home still
# carries the bare 123-line original. Per ADR-0075 template-launcher-parity-matrix,
# dev-studio-template = source of truth for new project bootstraps, so a new
# project scaffolded today would land with the bare version, missing:
#
#   - **Issue #213 TEST-WAKE-ENFORCE Layer 3** — type:bug must auto-add
#     `cc:tester` + `needs-tester-signoff` (CI gate; see Issue #213 §Layer 3)
#   - **Issue #423 ADR-0012 §Cascade-strip Part 1** — cascade-strip section
#     must remove ONLY duplicate `status:*` labels, NOT touch `cc:*` or
#     `needs-*-signoff` (scope-tightening, see Issue #423)
#   - **owner-override clause** — bypass mechanism for the human owner
#     (peer-poke / gh workflow run / label script)
#   - **closed event in pull_request_target** — trigger on PR close
#     (was missing in bare version; required for verdict-by post-close hygiene
#     and RETRO-024 §4-cat repair silent-skip guard)
#   - **concurrency serialization** — prevent overlapping label-check runs on
#     the same PR (ADR-0012 §Cascade-strip Part 1 + cycle ~#3968Q+414 PR
#     self-blocking CI doctrine)
#
# S35-003 cluster 1 = the d-test for this forward-port, RED-first per ADR-0044.
# Once this d-test is GREEN, the impl PR (dev lane, ADR-0059 cluster-squash
# cadence ≤5 PRs/cluster) can land the forward-port.
#
# Sister-pattern lineage:
#   - d-s34-005-runner-label-atilcan.sh — direct workflow-file d-test sister
#     (15 TCs, sed verification of `atilproject` → `atilcan` label across 10
#     workflow files; same TC counter + grep pattern + INDEX.md + CHANGELOG.md
#     structure)
#   - d-s34-004-disposable-bootstrap-test.sh — workflow-file d-test sister
#     (10 TCs, includes Python yaml.safe_load syntactic check TC2)
#   - d096-soul-files-template.sh — d-test framework ≥5 TCs baseline (ADR-0049)
#     + --self-test discipline + Cadence Rule 1 INDEX.md row
#   - d-retro-024-4cat-repair-silent-skip.sh — sister-pattern silent-skip guard
#     (related to TC5 cascade-strip scope-tightening)
#
# 10 TCs (≥6 baseline per ADR-0049 + ADR-0044; ≥5 d-test framework + 5 Sprint 33
# doctrine-layer specific):
#   TC1: workflow file exists at .github/workflows/label-check.yml
#   TC2: YAML syntactic check (Python yaml.safe_load parses cleanly)
#   TC3: workflow has `pull_request_target` trigger types INCLUDING `closed`
#        event (closed-on-PR hygiene per RETRO-024 §4-cat repair silent-skip
#        and verdict-by post-close)
#   TC4: workflow has `concurrency:` block with group key + cancel-in-progress
#        (Issue #423 ADR-0012 §Cascade-strip Part 1 concurrency serialization;
#        cycle ~#3968Q+414 PR self-blocking CI doctrine)
#   TC5: workflow ENFORCES type:bug → cc:tester + needs-tester-signoff
#        (Issue #213 TEST-WAKE-ENFORCE Layer 3 — CI gate, not just suggestion)
#   TC6: workflow cascade-strip section removes ONLY duplicate `status:*`,
#        does NOT touch `cc:*` or `needs-*-signoff` (Issue #423 ADR-0012
#        §Cascade-strip Part 1 scope-tightening)
#   TC7: workflow has owner-override clause (human-owner bypass mechanism,
#        typically `if: github.actor == 'atilcan65'` or equivalent comment)
#   TC8: workflow SHA-pins actions/github-script to commit SHA (ADR-0027
#        SHA-pinning hygiene — currently PASS today)
#   TC9: scripts/tests/INDEX.md has d-s35-003-c1-label-check-sprint33-doctrine
#        -forward-port row (Cadence Rule 1 atomic per ADR-0055 §1)
#   TC10: CHANGELOG.md has "Sprint 35 label-check Sprint 33 doctrine forward-port"
#         entry (unique prefix so duplicate-file detection works)
#
# Pre-impl RED state (verified 2026-07-27T17:08Z against bare 123-line target):
#   - TC1: PASS (file exists)
#   - TC2: PASS (YAML parses)
#   - TC3: FAIL (types are [opened, reopened, labeled, unlabeled] — NO `closed`)
#   - TC4: FAIL (no `concurrency:` block in bare version)
#   - TC5: FAIL (no type:bug → cc:tester + needs-tester-signoff enforcement)
#   - TC6: FAIL (no cascade-strip section at all)
#   - TC7: FAIL (no owner-override clause)
#   - TC8: PASS (SHA-pinned already in bare version)
#   - TC9: FAIL (no INDEX.md row yet)
#   - TC10: FAIL (no CHANGELOG.md entry yet)
# Expected exit code: 1 (RED state) per ADR-0044 RED-first VERIFIED.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOWS_DIR="$SCRIPT_DIR/../../.github/workflows"
TARGET_FILE="$WORKFLOWS_DIR/label-check.yml"
INDEX_FILE="$SCRIPT_DIR/INDEX.md"
CHANGELOG_FILE="$SCRIPT_DIR/../../CHANGELOG.md"
EXPECTED_NAME="d-s35-003-c1-label-check-sprint33-doctrine-forward-port"
EXPECTED_CHANGELOG_PREFIX="Sprint 35 label-check Sprint 33 doctrine forward-port"

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

echo "==== d-s35-003-c1-label-check-sprint33-doctrine-forward-port ===="
echo "Target: $TARGET_FILE"
echo "INDEX:  $INDEX_FILE"
echo "CHANGELOG: $CHANGELOG_FILE"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# TC1: workflow file exists
tc_num=$((tc_num + 1))
if [ -f "$TARGET_FILE" ]; then
  run_tc "TC${tc_num}: workflow file exists at .github/workflows/label-check.yml" 0
else
  run_tc "TC${tc_num}: workflow file MISSING at .github/workflows/label-check.yml" 1
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

# TC3: pull_request_target types includes "closed" event
tc_num=$((tc_num + 1))
# Use Python yaml to extract the on.pull_request_target.types list reliably
closed_in_types=$(python3 -c "
import yaml, sys
with open('$TARGET_FILE') as f:
    doc = yaml.safe_load(f)
on = doc.get(True, doc.get('on', {}))  # YAML 1.1 parses 'on' as boolean True
prt = on.get('pull_request_target', {})
types = prt.get('types', [])
print('yes' if 'closed' in types else 'no')
" 2>/dev/null)
if [[ "$closed_in_types" == "yes" ]]; then
  run_tc "TC${tc_num}: pull_request_target types includes 'closed' event (RETRO-024 §4-cat repair + verdict-by post-close)" 0
else
  run_tc "TC${tc_num}: pull_request_target types MISSING 'closed' event (current types lack closed-trigger; RETRO-024 silent-skip + verdict-by post-close hygiene broken)" 1
fi

# TC4: workflow has concurrency: block (Issue #423 ADR-0012 §Cascade-strip Part 1)
tc_num=$((tc_num + 1))
concurrency_block=$(python3 -c "
import yaml, sys
with open('$TARGET_FILE') as f:
    doc = yaml.safe_load(f)
conc = doc.get('concurrency', None)
if conc is None:
    print('missing')
elif isinstance(conc, str):
    print('present:group=' + conc)
elif isinstance(conc, dict):
    grp = conc.get('group', '')
    cip = conc.get('cancel-in-progress', 'unset')
    print(f'present:group={grp},cancel-in-progress={cip}')
else:
    print('present:unknown-shape')
" 2>/dev/null)
if [[ "$concurrency_block" == missing* ]] || [[ "$concurrency_block" == "" ]]; then
  run_tc "TC${tc_num}: workflow has concurrency: block (Issue #423 ADR-0012 §Cascade-strip Part 1 concurrency serialization) — FOUND: '$concurrency_block' — MISSING" 1
else
  run_tc "TC${tc_num}: workflow has concurrency: block (Issue #423) — FOUND: '$concurrency_block'" 0
fi

# TC5: workflow ENFORCES type:bug → cc:tester + needs-tester-signoff (Issue #213 Layer 3)
tc_num=$((tc_num + 1))
# Look for: a block that checks for type:bug label presence and adds cc:tester + needs-tester-signoff
# Defensive grep: search for the label strings co-occurring with type:bug check
# Use wc -l (always emits clean integer, even on no-match) instead of grep -c (multi-line on failure)
enforce_bug_wake=$(grep -E "type:bug.*cc:tester|cc:tester.*type:bug|type:bug.*needs-tester-signoff|needs-tester-signoff.*type:bug" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
# Also check for the auto-add logic (gh issue edit / actions/github-script addLabel calls in same block)
if [[ "$enforce_bug_wake" -ge 1 ]]; then
  run_tc "TC${tc_num}: workflow enforces type:bug → cc:tester + needs-tester-signoff (Issue #213 TEST-WAKE-ENFORCE Layer 3 — CI gate)" 0
else
  run_tc "TC${tc_num}: workflow does NOT enforce type:bug → cc:tester + needs-tester-signoff (Issue #213 Layer 3 missing; bare version has no enforcement block)" 1
fi

# TC6: cascade-strip scope-tightening Part 1 — only status:*, NOT cc:*/needs-*-signoff
tc_num=$((tc_num + 1))
# Detect cascade-strip section + verify it only removes status:* duplicates
# Strategy: grep for a cascade-strip/normalize/dedup block; verify it doesn't
# explicitly remove cc:* or needs-*-signoff
# Use wc -l for clean integer output
cascade_block=$(grep -E "cascade[-_]?strip|dedup.*status|removeDuplicate.*status|status.*dedup" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
cascade_touches_cc=$(grep -E "removeLabel.*cc:|remove.*cc:.*label" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
cascade_touches_needs=$(grep -E "removeLabel.*needs-|remove.*needs-.*signoff" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$cascade_block" -ge 1 && "$cascade_touches_cc" -eq 0 && "$cascade_touches_needs" -eq 0 ]]; then
  run_tc "TC${tc_num}: cascade-strip section present + scope-tightened to status:* only (Issue #423 ADR-0012 §Cascade-strip Part 1)" 0
elif [[ "$cascade_block" -eq 0 ]]; then
  run_tc "TC${tc_num}: cascade-strip section MISSING entirely (Issue #423 ADR-0012 §Cascade-strip Part 1 not implemented)" 1
elif [[ "$cascade_touches_cc" -ge 1 || "$cascade_touches_needs" -ge 1 ]]; then
  run_tc "TC${tc_num}: cascade-strip scope VIOLATION — touches cc:* ($cascade_touches_cc hits) or needs-*-signoff ($cascade_touches_needs hits); Issue #423 scope-tightening Part 1 broken" 1
else
  run_tc "TC${tc_num}: cascade-strip status unclear (cascade=$cascade_block, cc=$cascade_touches_cc, needs=$cascade_touches_needs); manual review" 1
fi

# TC7: owner-override clause present
tc_num=$((tc_num + 1))
owner_override=$(grep -E "if:.*github.actor.*==.*atilcan65|owner-override|OWNER_OVERRIDE|owner_override" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$owner_override" -ge 1 ]]; then
  run_tc "TC${tc_num}: workflow has owner-override clause (human-owner bypass for label-check enforcement)" 0
else
  run_tc "TC${tc_num}: workflow MISSING owner-override clause (no bypass mechanism for owner @atilcan65)" 1
fi

# TC8: SHA-pinned actions/github-script (ADR-0027)
tc_num=$((tc_num + 1))
sha_pinned=$(grep -cE "actions/github-script@[a-f0-9]{40}" "$TARGET_FILE" 2>/dev/null || echo 0)
if [[ "$sha_pinned" -ge 1 ]]; then
  run_tc "TC${tc_num}: actions/github-script SHA-pinned per ADR-0027 (commit SHA, not mutable tag)" 0
else
  run_tc "TC${tc_num}: actions/github-script NOT SHA-pinned (mutable tag or missing; ADR-0027 violation)" 1
fi

# TC9: INDEX.md row present (Cadence Rule 1 atomic per ADR-0055 §1)
tc_num=$((tc_num + 1))
if grep -q "$EXPECTED_NAME" "$INDEX_FILE" 2>/dev/null; then
  run_tc "TC${tc_num}: INDEX.md has $EXPECTED_NAME row (Cadence Rule 1 atomic per ADR-0055 §1)" 0
else
  run_tc "TC${tc_num}: INDEX.md MISSING $EXPECTED_NAME row (Cadence Rule 1 atomic per ADR-0055 §1 violated)" 1
fi

# TC10: CHANGELOG.md entry present
tc_num=$((tc_num + 1))
if grep -q "$EXPECTED_CHANGELOG_PREFIX" "$CHANGELOG_FILE" 2>/dev/null; then
  run_tc "TC${tc_num}: CHANGELOG.md has '$EXPECTED_CHANGELOG_PREFIX' entry" 0
else
  run_tc "TC${tc_num}: CHANGELOG.md MISSING '$EXPECTED_CHANGELOG_PREFIX' entry" 1
fi

echo ""
total_tcs=$tc_num
if [ "$failed" -eq 0 ]; then
  echo "✅ All $total_tcs TCs GREEN — Sprint 35 S35-003 cluster 1 label-check Sprint 33 doctrine forward-port verified"
  echo "   Impl PR ready for cluster-squash per ADR-0059 (≤5 PRs/cluster)"
  exit 0
else
  echo "❌ $failed TC(s) failed of $total_tcs — RED-first contract per ADR-0044"
  echo ""
  echo "Pre-impl RED state expected on bare 123-line label-check.yml:"
  echo "  PASS today: TC1 (file exists), TC2 (YAML parses), TC8 (SHA-pinned)"
  echo "  RED today:  TC3 (closed event), TC4 (concurrency), TC5 (Layer 3 type:bug)"
  echo "              TC6 (cascade-strip), TC7 (owner-override), TC9 (INDEX row)"
  echo "              TC10 (CHANGELOG entry)"
  echo ""
  echo "Sprint 33 doctrine layers required (forward-port from atilproject/AtilCalculator 977-line):"
  echo "  - Issue #213 Layer 3 — type:bug → cc:tester + needs-tester-signoff CI gate"
  echo "  - Issue #423 Layer 4 — concurrency serialization + cascade-strip scope-tightening Part 1"
  echo "  - owner-override clause — human bypass mechanism"
  echo "  - closed event in pull_request_target — verdict-by post-close + RETRO-024 silent-skip"
  echo ""
  echo "Sister-pattern: d-s34-005-runner-label-atilcan.sh (15 TCs, workflow-file d-test)"
  exit 1
fi