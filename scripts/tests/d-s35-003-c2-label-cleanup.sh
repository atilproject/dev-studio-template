#!/usr/bin/env bash
# d-s35-003-c2-label-cleanup.sh —
#   Sprint 35 S35-003 cluster 2 RED-first d-test verifying label-cleanup.yml
#   forward-port from bare 108-line tmpl → AtilCalculator's post-Sprint 33
#   132-line canonical (TD-067 TRANSIENT_REGEX scope-tightening per Issue #922).
#
# Why this test exists
# --------------------
# Sprint 35 S35-003 cluster 2 forward-ports 4 sister workflows from the bare
# dev-studio-template canonical to AtilCalculator's post-Sprint 33 status.
# Per ADR-0075 template-launcher-parity-matrix, dev-studio-template = source
# of truth for new project bootstraps, so a new project scaffolded today would
# land with the bare version, missing:
#
#   - **TD-067 (Issue #922) TRANSIENT_REGEX scope-tightening** — bare version
#     uses `TRANSIENT_REGEX='^(cc:|agent:|needs-)|^agent-stall$'` which removes
#     `cc:*` and `agent:*` labels on pull_request:closed event. This breaks
#     the 4-cat invariant (ADR-0012) on closed PRs and suppresses pr_labeled
#     wake audit trail (ADR-0009 §10.3 + ADR-0038). The fix narrows to
#     `TRANSIENT_REGEX='^(needs-)|^agent-stall$'` so `cc:*` and `agent:*`
#     labels are PRESERVED on closed PRs. Required by:
#       - 4-cat invariant (ADR-0012) on closed PRs
#       - pr_labeled wake audit trail (ADR-0009 §10.3 + ADR-0038)
#       - RETRO-016 sister-pattern lineage (TD-067/TD-068 sister-fix)
#
#   - **TD-067 explanatory header comment** — bare version header doesn't
#     reference Issue #922 / TD-067, so the next developer touching this
#     workflow has no rationale anchor for why the scope was tightened.
#     Canonical header cites the design contract `docs/designs/TD-067-TD-068
#     -sister-fix-design.md` + Issue #922 + RETRO-016 sister-pattern.
#
#   - **STATUS_ADVANCE_REGEX preserved** — both versions have it (workflow
#     contract for status:in-* → status:done advancement on PR merge); the
#     forward-port must NOT accidentally remove or break this regex.
#
# S35-003 cluster 2 = the d-test for this forward-port, RED-first per ADR-0044.
# Once this d-test is GREEN, the impl PR (dev lane, ADR-0059 cluster-squash
# cadence ≤5 PRs/cluster) can land the forward-port.
#
# Sister-pattern lineage:
#   - d-s35-003-c2-status-label-to-board.sh — direct sister (10 TCs,
#     workflow-file d-test, --self-test discipline, Cadence Rule 1 INDEX.md
#     + CHANGELOG.md)
#   - d-s35-003-c1-label-check-sprint33-doctrine-forward-port.sh — cluster 1
#     direct sister (10 TCs, workflow-file d-test)
#   - d-s34-005-runner-label-atilcan.sh — workflow-file d-test sister
#     (15 TCs, sed verification of `atilproject` → `atilcan` label across
#     10 workflow files)
#   - d-s34-004-disposable-bootstrap-test.sh — workflow-file d-test sister
#     (10 TCs, includes Python yaml.safe_load syntactic check TC2)
#   - d096-soul-files-template.sh — d-test framework ≥5 TCs baseline (ADR-0049)
#     + --self-test discipline + Cadence Rule 1 INDEX.md row
#
# 10 TCs (≥6 baseline per ADR-0049 + ADR-0044; ≥5 d-test framework + 5 Sprint 33
# doctrine-layer specific):
#   TC1: workflow file exists at .github/workflows/label-cleanup.yml
#   TC2: YAML syntactic check (Python yaml.safe_load parses cleanly)
#   TC3: TRANSIENT_REGEX does NOT match `cc:*` labels (TD-067 scope-tightening
#        Part 1 — preserve cc labels per ADR-0012 4-cat invariant on closed PRs)
#   TC4: TRANSIENT_REGEX does NOT match `agent:*` labels (TD-067 scope-tightening
#        Part 2 — preserve agent labels per ADR-0012 4-cat invariant)
#   TC5: TRANSIENT_REGEX DOES match `needs-*` labels (preserves workflow
#        transient removal signal — `needs-tester-signoff`, `needs-architect-review`)
#   TC6: TRANSIENT_REGEX DOES match `agent-stall` label (preserves stall detection)
#   TC7: TD-067 explanatory header comment present (Issue #922 reference +
#        design contract anchor + ADR-0012/ADR-0009 doctrinal rationale)
#   TC8: STATUS_ADVANCE_REGEX preserved (workflow contract not broken — both
#        bare and canonical have `^status:(in-progress|in-review|ready|blocked|backlog)$`)
#   TC9: INDEX.md has d-s35-003-c2-label-cleanup row (Cadence Rule 1 atomic
#        per ADR-0055 §1)
#   TC10: CHANGELOG.md has "Sprint 35 S35-003 cluster 2 label-cleanup" entry
#         (unique prefix so duplicate-file detection works)
#
# Pre-impl RED state (verified 2026-07-27T20:43Z against bare 108-line target):
#   - TC1: PASS (file exists)
#   - TC2: PASS (YAML parses)
#   - TC3: FAIL (TRANSIENT_REGEX `^(cc:|agent:|needs-)|^agent-stall$` matches cc:tester — over-aggressive)
#   - TC4: FAIL (TRANSIENT_REGEX matches agent:tester — over-aggressive)
#   - TC5: PASS (TRANSIENT_REGEX matches needs-tester-signoff — correct)
#   - TC6: PASS (TRANSIENT_REGEX matches agent-stall — correct)
#   - TC7: FAIL (bare header has no TD-067/Issue #922 reference)
#   - TC8: PASS (STATUS_ADVANCE_REGEX already present in bare)
#   - TC9: FAIL (no INDEX.md row yet)
#   - TC10: FAIL (no CHANGELOG.md entry yet)
# Expected exit code: 1 (RED state) per ADR-0044 RED-first VERIFIED.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOWS_DIR="$SCRIPT_DIR/../../.github/workflows"
TARGET_FILE="$WORKFLOWS_DIR/label-cleanup.yml"
INDEX_FILE="$SCRIPT_DIR/INDEX.md"
CHANGELOG_FILE="$SCRIPT_DIR/../../CHANGELOG.md"
EXPECTED_NAME="d-s35-003-c2-label-cleanup"
EXPECTED_CHANGELOG_PREFIX="Sprint 35 S35-003 cluster 2 label-cleanup"

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

echo "==== d-s35-003-c2-label-cleanup ===="
echo "Target: $TARGET_FILE"
echo "INDEX:  $INDEX_FILE"
echo "CHANGELOG: $CHANGELOG_FILE"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# TC1: workflow file exists
tc_num=$((tc_num + 1))
if [ -f "$TARGET_FILE" ]; then
  run_tc "TC${tc_num}: workflow file exists at .github/workflows/label-cleanup.yml" 0
else
  run_tc "TC${tc_num}: workflow file MISSING at .github/workflows/label-cleanup.yml" 1
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

# TC3: TRANSIENT_REGEX does NOT match `cc:*` (TD-067 scope-tightening Part 1)
tc_num=$((tc_num + 1))
# Extract TRANSIENT_REGEX value from workflow file
transient_regex=$(grep -E "^[[:space:]]*TRANSIENT_REGEX=" "$TARGET_FILE" 2>/dev/null | head -1 | sed -E "s/^[[:space:]]*TRANSIENT_REGEX='//; s/'$//")
# Test the regex against `cc:tester` — should NOT match after TD-067 fix
cc_match=$(echo '["cc:tester"]' | jq -r --arg re "$transient_regex" '[.[] | select(test($re))] | .[]' 2>/dev/null | wc -l | tr -d ' ')
if [[ -z "$transient_regex" ]]; then
  run_tc "TC${tc_num}: TRANSIENT_REGEX not found in workflow file (regex extraction failed; cannot verify TD-067 scope-tightening)" 1
elif [[ "$cc_match" -eq 0 ]]; then
  run_tc "TC${tc_num}: TRANSIENT_REGEX does NOT match cc:tester (TD-067 scope-tightening Part 1 — preserve cc labels per ADR-0012 4-cat invariant)" 0
else
  run_tc "TC${tc_num}: TRANSIENT_REGEX matches cc:tester (TD-067 VIOLATION — TRANSIENT_REGEX='$transient_regex' is over-aggressive; 4-cat invariant broken on closed PRs)" 1
fi

# TC4: TRANSIENT_REGEX does NOT match `agent:*` (TD-067 scope-tightening Part 2)
tc_num=$((tc_num + 1))
# Test the regex against `agent:developer` — should NOT match after TD-067 fix
agent_match=$(echo '["agent:developer"]' | jq -r --arg re "$transient_regex" '[.[] | select(test($re))] | .[]' 2>/dev/null | wc -l | tr -d ' ')
if [[ -z "$transient_regex" ]]; then
  run_tc "TC${tc_num}: TRANSIENT_REGEX not found in workflow file (regex extraction failed)" 1
elif [[ "$agent_match" -eq 0 ]]; then
  run_tc "TC${tc_num}: TRANSIENT_REGEX does NOT match agent:developer (TD-067 scope-tightening Part 2 — preserve agent labels per ADR-0012 4-cat invariant)" 0
else
  run_tc "TC${tc_num}: TRANSIENT_REGEX matches agent:developer (TD-067 VIOLATION — TRANSIENT_REGEX='$transient_regex' is over-aggressive)" 1
fi

# TC5: TRANSIENT_REGEX DOES match `needs-*` (preserves workflow transient removal)
tc_num=$((tc_num + 1))
# Test the regex against `needs-tester-signoff` — should match
needs_match=$(echo '["needs-tester-signoff"]' | jq -r --arg re "$transient_regex" '[.[] | select(test($re))] | .[]' 2>/dev/null | wc -l | tr -d ' ')
if [[ -z "$transient_regex" ]]; then
  run_tc "TC${tc_num}: TRANSIENT_REGEX not found in workflow file (regex extraction failed)" 1
elif [[ "$needs_match" -ge 1 ]]; then
  run_tc "TC${tc_num}: TRANSIENT_REGEX matches needs-tester-signoff (workflow transient removal signal preserved — sister-pattern to d-test framework needs-* signoff labels)" 0
else
  run_tc "TC${tc_num}: TRANSIENT_REGEX MISSING needs-* match (TRANSIENT_REGEX='$transient_regex' — would leave stale needs-* labels on closed PRs)" 1
fi

# TC6: TRANSIENT_REGEX DOES match `agent-stall` (preserves stall detection)
tc_num=$((tc_num + 1))
# Test the regex against `agent-stall` — should match
stall_match=$(echo '["agent-stall"]' | jq -r --arg re "$transient_regex" '[.[] | select(test($re))] | .[]' 2>/dev/null | wc -l | tr -d ' ')
if [[ -z "$transient_regex" ]]; then
  run_tc "TC${tc_num}: TRANSIENT_REGEX not found in workflow file (regex extraction failed)" 1
elif [[ "$stall_match" -ge 1 ]]; then
  run_tc "TC${tc_num}: TRANSIENT_REGEX matches agent-stall (stall detection preserved — sister-pattern to agent-watch.sh stall-loop doctrine)" 0
else
  run_tc "TC${tc_num}: TRANSIENT_REGEX MISSING agent-stall match (TRANSIENT_REGEX='$transient_regex' — would leave stale agent-stall labels)" 1
fi

# TC7: TD-067 explanatory header comment present (Issue #922 + design contract anchor)
tc_num=$((tc_num + 1))
# Use wc -l for clean integer output (cycle ~#3968Q+847 inline d-test amender pattern)
td067_ref=$(grep -iE "TD-067|Issue #922|922|docs/designs/TD-067" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$td067_ref" -ge 1 ]]; then
  run_tc "TC${tc_num}: TD-067 explanatory header comment present (Issue #922 reference + design contract anchor + doctrinal rationale)" 0
else
  run_tc "TC${tc_num}: TD-067 explanatory header comment MISSING (bare header has no Issue #922 / TD-067 reference; next developer has no rationale anchor)" 1
fi

# TC8: STATUS_ADVANCE_REGEX preserved (workflow contract not broken)
tc_num=$((tc_num + 1))
# Extract STATUS_ADVANCE_REGEX value from workflow file
status_regex=$(grep -E "^[[:space:]]*STATUS_ADVANCE_REGEX=" "$TARGET_FILE" 2>/dev/null | head -1 | sed -E "s/^[[:space:]]*STATUS_ADVANCE_REGEX='//; s/'$//")
if [[ -z "$status_regex" ]]; then
  run_tc "TC${tc_num}: STATUS_ADVANCE_REGEX not found in workflow file (workflow contract broken — status:in-* won't advance to status:done on merge)" 1
elif [[ "$status_regex" == *"in-progress"* ]] && [[ "$status_regex" == *"in-review"* ]] && [[ "$status_regex" == *"ready"* ]] && [[ "$status_regex" == *"blocked"* ]] && [[ "$status_regex" == *"backlog"* ]]; then
  run_tc "TC${tc_num}: STATUS_ADVANCE_REGEX preserved (covers all 5 status transitions: in-progress/in-review/ready/blocked/backlog → done on merge)" 0
else
  run_tc "TC${tc_num}: STATUS_ADVANCE_REGEX present but incomplete ('$status_regex' — missing one or more status transitions; workflow contract broken)" 1
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
  echo "✅ All $total_tcs TCs GREEN — Sprint 35 S35-003 cluster 2 label-cleanup forward-port verified"
  echo "   Impl PR ready for cluster-squash per ADR-0059 (≤5 PRs/cluster)"
  exit 0
else
  echo "❌ $failed TC(s) failed of $total_tcs — RED-first contract per ADR-0044"
  echo ""
  echo "Pre-impl RED state expected on bare 108-line label-cleanup.yml:"
  echo "  PASS today: TC1 (file exists), TC2 (YAML parses),"
  echo "              TC5 (needs-* match preserved), TC6 (agent-stall match preserved),"
  echo "              TC8 (STATUS_ADVANCE_REGEX preserved)"
  echo "  RED today:  TC3 (TRANSIENT_REGEX matches cc:tester — TD-067 violation),"
  echo "              TC4 (TRANSIENT_REGEX matches agent:developer — TD-067 violation),"
  echo "              TC7 (no TD-067/Issue #922 header reference),"
  echo "              TC9 (INDEX.md row missing), TC10 (CHANGELOG.md entry missing)"
  echo ""
  echo "Sprint 33 doctrine layers required (forward-port from atilproject/AtilCalculator 132-line):"
  echo "  - TD-067 (Issue #922) TRANSIENT_REGEX scope-tightening Part 1 — preserve cc:*"
  echo "  - TD-067 (Issue #922) TRANSIENT_REGEX scope-tightening Part 2 — preserve agent:*"
  echo "  - TD-067 explanatory header comment — Issue #922 + design contract anchor"
  echo "  - STATUS_ADVANCE_REGEX preserved — workflow contract not broken"
  echo ""
  echo "Sister-pattern: d-s35-003-c2-status-label-to-board.sh (10 TCs, workflow-file d-test)"
  echo "Sister-pattern: d-s35-003-c1-label-check-sprint33-doctrine-forward-port.sh (10 TCs, cluster 1)"
  exit 1
fi