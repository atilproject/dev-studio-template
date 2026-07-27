#!/usr/bin/env bash
# d-s35-003-c2-lint-and-test.sh —
#   Sprint 35 S35-003 cluster 2 RED-first d-test verifying lint-and-test.yml
#   forward-port from bare 119-line tmpl → AtilCalculator's post-Sprint 33
#   131-line canonical (d031/dreg → d058/d064 swap).
#
# Why this test exists
# --------------------
# Sprint 35 S35-003 cluster 2 forward-ports 4 sister workflows from the bare
# dev-studio-template canonical to AtilCalculator's post-Sprint 33 status.
# Per ADR-0075 template-launcher-parity-matrix, dev-studio-template = source
# of truth for new project bootstraps, so a new project scaffolded today would
# land with the bare version, missing:
#
#   - **d031/dreg → d058/d064 swap** — bare version uses template-appropriate
#     substitute d-tests (`d031-claim-next-ready.sh` + `dreg-post-restart
#     -label-guard.sh`) because the original d058/d064 d-tests from
#     AtilCalculator don't exist in the bare template's scripts/tests/
#     inventory. The S29-010 themed impl PR header explicitly documents
#     this substitution and provides downstream adaptation guidance.
#
#     The canonical AtilCalculator version uses the ORIGINAL d058-claim-wip
#     -workstream.sh (Sprint 14 P1 #6 AC5, Issue #508, Closes #497 AC5) +
#     d064-cluster-lag.sh (Sprint 18 P1, Issue #611, refs STORY-S18-008).
#     Forward-port MUST swap d031/dreg → d058/d064 to match canonical.
#
#   - **d058 explanatory header comment** — bare version has the
#     S29-010 adaptation rationale; canonical has the Sprint 14 P1 #6
#     AC5 + Issue #508 + Closes #497 AC5 doctrinal anchor. Forward-port
#     drops the S29-010 substitution note and replaces with original
#     AtilCalc doctrinal anchor.
#
# S35-003 cluster 2 = the d-test for this forward-port, RED-first per ADR-0044.
# Once this d-test is GREEN, the impl PR (dev lane, ADR-0059 cluster-squash
# cadence ≤5 PRs/cluster) can land the forward-port.
#
# Sister-pattern lineage:
#   - d-s35-003-c2-status-label-to-board.sh — direct sister (10 TCs,
#     workflow-file d-test, --self-test discipline, Cadence Rule 1 INDEX.md
#     + CHANGELOG.md)
#   - d-s35-003-c2-label-cleanup.sh — direct sister (cluster 2 #2, 10 TCs)
#   - d-s35-003-c1-label-check-sprint33-doctrine-forward-port.sh — cluster 1
#     direct sister (10 TCs, workflow-file d-test)
#   - d-s34-005-runner-label-atilcan.sh — workflow-file d-test sister
#     (15 TCs, sed verification of `atilproject` → `atilcan` label across
#     10 workflow files)
#   - d-s34-004-disposable-bootstrap-test.sh — workflow-file d-test sister
#     (10 TCs, includes Python yaml.safe_load syntactic check TC2)
#   - d096-soul-files-template.sh — d-test framework ≥5 TCs baseline (ADR-0049)
#
# 10 TCs (≥6 baseline per ADR-0049 + ADR-0044; ≥5 d-test framework + 5 Sprint 33
# doctrine-layer specific):
#   TC1: workflow file exists at .github/workflows/lint-and-test.yml
#   TC2: YAML syntactic check (Python yaml.safe_load parses cleanly)
#   TC3: workflow references `d058-claim-wip-workstream.sh` (canonical
#        Sprint 14 P1 #6 AC5 d-test; NOT template substitute d031)
#   TC4: workflow references `d064-cluster-lag.sh` (canonical Sprint 18 P1
#        d-test; NOT template substitute dreg)
#   TC5: workflow does NOT reference `d031-claim-next-ready.sh` (template
#        substitute, must be removed in forward-port)
#   TC6: workflow does NOT reference `dreg-post-restart-label-guard.sh`
#        (template substitute, must be removed in forward-port)
#   TC7: SHA-pinned `actions/checkout` per ADR-0027 + Issue #567 SHA-pin
#        sweep (commit SHA `34e1148...`, NOT mutable tag — currently PASS)
#   TC8: 9-Lens coverage header comment present (ADR-0045 — lens a-i
#        annotations; sister-pattern to other workflow files)
#   TC9: INDEX.md has d-s35-003-c2-lint-and-test row (Cadence Rule 1 atomic
#        per ADR-0055 §1)
#   TC10: CHANGELOG.md has "Sprint 35 S35-003 cluster 2 lint-and-test" entry
#         (unique prefix so duplicate-file detection works)
#
# Pre-impl RED state (verified 2026-07-27T20:48Z against bare 119-line target):
#   - TC1: PASS (file exists)
#   - TC2: PASS (YAML parses)
#   - TC3: FAIL (workflow references d031, NOT d058 — bare version)
#   - TC4: FAIL (workflow references dreg, NOT d064 — bare version)
#   - TC5: FAIL (workflow references d031 — must be removed)
#   - TC6: FAIL (workflow references dreg — must be removed)
#   - TC7: PASS (SHA-pinned actions/checkout already present)
#   - TC8: PASS (9-Lens coverage header present)
#   - TC9: FAIL (no INDEX.md row yet)
#   - TC10: FAIL (no CHANGELOG.md entry yet)
# Expected exit code: 1 (RED state) per ADR-0044 RED-first VERIFIED.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOWS_DIR="$SCRIPT_DIR/../../.github/workflows"
TARGET_FILE="$WORKFLOWS_DIR/lint-and-test.yml"
INDEX_FILE="$SCRIPT_DIR/INDEX.md"
CHANGELOG_FILE="$SCRIPT_DIR/../../CHANGELOG.md"
EXPECTED_NAME="d-s35-003-c2-lint-and-test"
EXPECTED_CHANGELOG_PREFIX="Sprint 35 S35-003 cluster 2 lint-and-test"

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

echo "==== d-s35-003-c2-lint-and-test ===="
echo "Target: $TARGET_FILE"
echo "INDEX:  $INDEX_FILE"
echo "CHANGELOG: $CHANGELOG_FILE"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# TC1: workflow file exists
tc_num=$((tc_num + 1))
if [ -f "$TARGET_FILE" ]; then
  run_tc "TC${tc_num}: workflow file exists at .github/workflows/lint-and-test.yml" 0
else
  run_tc "TC${tc_num}: workflow file MISSING at .github/workflows/lint-and-test.yml" 1
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

# TC3: workflow references d058-claim-wip-workstream.sh (canonical Sprint 14 P1 #6 AC5)
tc_num=$((tc_num + 1))
# Use wc -l for clean integer output (cycle ~#3968Q+847 inline d-test amender pattern)
d058_ref=$(grep -E "d058-claim-wip-workstream" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$d058_ref" -ge 1 ]]; then
  run_tc "TC${tc_num}: workflow references d058-claim-wip-workstream.sh (canonical Sprint 14 P1 #6 AC5, Issue #508, Closes #497 AC5)" 0
else
  run_tc "TC${tc_num}: workflow MISSING d058 reference (bare version uses d031 substitute — forward-port must swap d031 → d058)" 1
fi

# TC4: workflow references d064-cluster-lag.sh (canonical Sprint 18 P1)
tc_num=$((tc_num + 1))
d064_ref=$(grep -E "d064-cluster-lag" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$d064_ref" -ge 1 ]]; then
  run_tc "TC${tc_num}: workflow references d064-cluster-lag.sh (canonical Sprint 18 P1, Issue #611, refs STORY-S18-008)" 0
else
  run_tc "TC${tc_num}: workflow MISSING d064 reference (bare version uses dreg substitute — forward-port must swap dreg → d064)" 1
fi

# TC5: workflow does NOT reference d031-claim-next-ready.sh (template substitute must be removed)
tc_num=$((tc_num + 1))
d031_ref=$(grep -E "d031-claim-next-ready" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$d031_ref" -eq 0 ]]; then
  run_tc "TC${tc_num}: workflow does NOT reference d031-claim-next-ready.sh (template substitute removed in forward-port — d058 swap complete)" 0
else
  run_tc "TC${tc_num}: workflow STILL references d031-claim-next-ready.sh ($d031_ref occurrences — template substitute NOT removed; forward-port incomplete)" 1
fi

# TC6: workflow does NOT reference dreg-post-restart-label-guard.sh (template substitute must be removed)
tc_num=$((tc_num + 1))
dreg_ref=$(grep -E "dreg-post-restart-label-guard" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$dreg_ref" -eq 0 ]]; then
  run_tc "TC${tc_num}: workflow does NOT reference dreg-post-restart-label-guard.sh (template substitute removed in forward-port — d064 swap complete)" 0
else
  run_tc "TC${tc_num}: workflow STILL references dreg-post-restart-label-guard.sh ($dreg_ref occurrences — template substitute NOT removed; forward-port incomplete)" 1
fi

# TC7: SHA-pinned actions/checkout per ADR-0027 + Issue #567 SHA-pin sweep
tc_num=$((tc_num + 1))
# Look for SHA-pinned actions/checkout (40-char hex SHA, not mutable tag like @v4)
sha_pinned=$(grep -E "actions/checkout@[a-f0-9]{40}" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$sha_pinned" -ge 1 ]]; then
  run_tc "TC${tc_num}: actions/checkout SHA-pinned per ADR-0027 + Issue #567 SHA-pin sweep (commit SHA 34e1148..., NOT mutable @v4 tag)" 0
else
  run_tc "TC${tc_num}: actions/checkout NOT SHA-pinned (mutable tag or missing; ADR-0027 violation + Issue #567 SHA-pin sweep incomplete)" 1
fi

# TC8: 9-Lens coverage header comment present (ADR-0045)
tc_num=$((tc_num + 1))
# Look for "9-Lens" coverage annotation in header (lens a-i per ADR-0045)
lens_annot=$(grep -iE "9-Lens|9 lens|lens \([a-i]\)" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$lens_annot" -ge 1 ]]; then
  run_tc "TC${tc_num}: 9-Lens coverage header comment present (ADR-0045 lens a-i annotations; sister-pattern to other workflow files)" 0
else
  run_tc "TC${tc_num}: 9-Lens coverage header comment MISSING (ADR-0045 lens a-i annotations absent)" 1
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
  run_tc "TC${tc_num}: CHANGELOG.md has '$EXPECTED_CHANGELOG_PREFIX' entry (unique prefix so duplicate-file detection works)" 0
else
  run_tc "TC${tc_num}: CHANGELOG.md MISSING '$EXPECTED_CHANGELOG_PREFIX' entry" 1
fi

echo ""
total_tcs=$tc_num
if [ "$failed" -eq 0 ]; then
  echo "✅ All $total_tcs TCs GREEN — Sprint 35 S35-003 cluster 2 lint-and-test forward-port verified"
  echo "   Impl PR ready for cluster-squash per ADR-0059 (≤5 PRs/cluster)"
  exit 0
else
  echo "❌ $failed TC(s) failed of $total_tcs — RED-first contract per ADR-0044"
  echo ""
  echo "Pre-impl RED state expected on bare 119-line lint-and-test.yml:"
  echo "  PASS today: TC1 (file exists), TC2 (YAML parses),"
  echo "              TC7 (SHA-pinned actions/checkout), TC8 (9-Lens header)"
  echo "  RED today:  TC3 (d058 reference MISSING — d031 substitute),"
  echo "              TC4 (d064 reference MISSING — dreg substitute),"
  echo "              TC5 (d031 reference STILL PRESENT — must be removed),"
  echo "              TC6 (dreg reference STILL PRESENT — must be removed),"
  echo "              TC9 (INDEX.md row missing), TC10 (CHANGELOG.md entry missing)"
  echo ""
  echo "Sprint 33 doctrine layers required (forward-port from atilproject/AtilCalculator 131-line):"
  echo "  - d031/dreg → d058/d064 swap (Sprint 14 P1 #6 AC5 + Sprint 18 P1 d-tests)"
  echo "  - d058-claim-wip-workstream.sh reference (Issue #508, Closes #497 AC5)"
  echo "  - d064-cluster-lag.sh reference (Issue #611, refs STORY-S18-008)"
  echo ""
  echo "Sister-pattern: d-s35-003-c2-status-label-to-board.sh (10 TCs, workflow-file d-test)"
  echo "Sister-pattern: d-s35-003-c2-label-cleanup.sh (10 TCs, cluster 2 #2)"
  echo "Sister-pattern: d-s35-003-c1-label-check-sprint33-doctrine-forward-port.sh (10 TCs, cluster 1)"
  exit 1
fi