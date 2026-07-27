#!/usr/bin/env bash
# d-s35-003-c2-status-label-to-board.sh —
#   Sprint 35 S35-003 cluster 2 RED-first d-test verifying
#   status-label-to-board.yml forward-port from bare tmpl → calc canonical
#   (Issue #571 §Layer 5 idempotency reconcile per ADR-0056).
#
# Why this test exists
# --------------------
# Sprint 35 S35-003 cluster 2 forward-ports 4 sister workflows from the bare
# dev-studio-template canonical to AtilCalculator's post-Sprint 33 status.
# Per ADR-0075 template-launcher-parity-matrix, dev-studio-template = source
# of truth for new project bootstraps, so a new project scaffolded today would
# land with the bare version, missing:
#
#   - **Issue #571 §Layer 5 idempotency reconcile (ADR-0056)** — workflow must
#     have a `concurrency:` block with `group: sync-status-${{ ... }}` and
#     `cancel-in-progress: true` to serialize concurrent sync-status runs per
#     issue/PR. Without this, a label-flip burst fans out into a rate-limit
#     cascade (sister-pattern to label-check.yml Layer 4 scope-tightening).
#
#   - **Issue #571 §Layer 5 rate-limit cascade fix (ADR-0056)** — workflow must
#     have a `withRetryOnRateLimit()` helper that wraps every github.graphql()
#     call with DETERMINISTIC X-RateLimit-Reset sleep + single retry (arch
#     verdict cycle 282 — REJECTED exponential backoff as cheaper-fix violation,
#     per ADR-0052 §CI re-run race codification).
#
#   - **Issue #571 §silent_skip helper (ADR-0056 §silent_skip)** — workflow
#     must have a `silentSkipOnRateLimit()` helper that catches exhausted-retry
#     rate-limit errors and exits 0 with core.warning. Non-rate-limit errors
#     propagate (selective). Sister-pattern: d055 cascade-strip 404-silent-skip.
#
#   - **Issue #571 try-catch wrapping GraphQL block** — workflow must wrap
#     the GraphQL block in try-catch so exhausted-retry rate-limit errors
#     silently-skip with core.warning + exit 0 (per ADR-0056 §silent_skip).
#
#   - **Issue #567 SHA-pin sweep** — actions/github-script SHA-pinned to v7
#     commit SHA matching label-check.yml L54/178/243/329/450 (per ADR-0045
#     lens h + TD-028). SHA-pinning protects against supply-chain compromise
#     of the version tag.
#
# S35-003 cluster 2 = the d-test for this forward-port, RED-first per ADR-0044.
# Once this d-test is GREEN, the impl PR (dev lane, ADR-0059 cluster-squash
# cadence ≤5 PRs/cluster) can land the forward-port.
#
# Sister-pattern lineage:
#   - d-s35-003-c1-label-check-sprint33-doctrine-forward-port.sh — direct
#     sister (10 TCs, workflow-file d-test, --self-test discipline, Cadence
#     Rule 1 INDEX.md + CHANGELOG.md)
#   - d-s34-005-runner-label-atilcan.sh — workflow-file d-test sister
#     (15 TCs, sed verification of `atilproject` → `atilcan` label across 10
#     workflow files)
#   - d-s34-004-disposable-bootstrap-test.sh — workflow-file d-test sister
#     (10 TCs, includes Python yaml.safe_load syntactic check TC2)
#   - d096-soul-files-template.sh — d-test framework ≥5 TCs baseline (ADR-0049)
#     + --self-test discipline + Cadence Rule 1 INDEX.md row
#   - d055 cascade-strip 404-silent-skip — direct doctrine-layer sister
#     (silentSkipOnRateLimit sister-pattern)
#   - d056 TC6 warn on silent-skip — silent-skip sister pattern
#
# 10 TCs (≥6 baseline per ADR-0049 + ADR-0044; ≥5 d-test framework + 5 Sprint 33
# doctrine-layer specific):
#   TC1: workflow file exists at .github/workflows/status-label-to-board.yml
#   TC2: YAML syntactic check (Python yaml.safe_load parses cleanly)
#   TC3: workflow has `concurrency:` block (Issue #571 §Layer 5 idempotency
#        reconcile per ADR-0056)
#   TC4: concurrency group key includes pull_request.number OR issue.number
#        (serialization key per-issue/per-PR, not global)
#   TC5: concurrency `cancel-in-progress: true` (Issue #571 §Layer 5 — newer
#        runs supersede older ones; we want the LATEST label state to win)
#   TC6: workflow has `withRetryOnRateLimit` helper function (Issue #571
#        §Layer 5 rate-limit cascade fix per ADR-0056)
#   TC7: workflow has `silentSkipOnRateLimit` helper function (Issue #571
#        §silent_skip per ADR-0056 — exhausted-retry rate-limit → exit 0)
#   TC8: workflow wraps GraphQL block in try-catch (per ADR-0056 §silent_skip
#        — exhausted-retry rate-limit errors silently-skip with core.warning)
#   TC9: actions/github-script SHA-pinned to commit SHA per ADR-0027 + Issue
#        #567 SHA-pin sweep (matching label-check.yml L54 SHA)
#   TC10: INDEX.md has d-s35-003-c2-status-label-to-board row (Cadence Rule 1
#         atomic per ADR-0055 §1)
#
# Pre-impl RED state (verified 2026-07-27T20:30Z against bare 199-line target):
#   - TC1: PASS (file exists)
#   - TC2: PASS (YAML parses)
#   - TC3: FAIL (no `concurrency:` block in bare tmpl)
#   - TC4: FAIL (no concurrency group to inspect)
#   - TC5: FAIL (no cancel-in-progress)
#   - TC6: FAIL (no withRetryOnRateLimit helper)
#   - TC7: FAIL (no silentSkipOnRateLimit helper)
#   - TC8: FAIL (no try-catch wrap)
#   - TC9: PASS (SHA-pinned already in bare version per Issue #567)
#   - TC10: FAIL (no INDEX.md row yet)
# Expected exit code: 1 (RED state) per ADR-0044 RED-first VERIFIED.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOWS_DIR="$SCRIPT_DIR/../../.github/workflows"
TARGET_FILE="$WORKFLOWS_DIR/status-label-to-board.yml"
INDEX_FILE="$SCRIPT_DIR/INDEX.md"
EXPECTED_NAME="d-s35-003-c2-status-label-to-board"

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

echo "==== d-s35-003-c2-status-label-to-board ===="
echo "Target: $TARGET_FILE"
echo "INDEX:  $INDEX_FILE"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# TC1: workflow file exists
tc_num=$((tc_num + 1))
if [ -f "$TARGET_FILE" ]; then
  run_tc "TC${tc_num}: workflow file exists at .github/workflows/status-label-to-board.yml" 0
else
  run_tc "TC${tc_num}: workflow file MISSING at .github/workflows/status-label-to-board.yml" 1
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

# TC3: workflow has concurrency: block (Issue #571 §Layer 5)
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
  run_tc "TC${tc_num}: workflow has concurrency: block (Issue #571 §Layer 5 idempotency reconcile per ADR-0056) — FOUND: '$concurrency_block' — MISSING" 1
else
  run_tc "TC${tc_num}: workflow has concurrency: block (Issue #571 §Layer 5) — FOUND: '$concurrency_block'" 0
fi

# TC4: concurrency group key includes pull_request.number OR issue.number
tc_num=$((tc_num + 1))
group_has_serial_key=$(grep -E "group:.*sync-status.*\\\$\\{\\{\\s*github\\.event\\.pull_request\\.number\\b|group:.*sync-status.*\\\$\\{\\{\\s*github\\.event\\.issue\\.number\\b" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$group_has_serial_key" -ge 1 ]]; then
  run_tc "TC${tc_num}: concurrency group key includes pull_request.number OR issue.number (serialization key per-issue/per-PR, not global)" 0
else
  run_tc "TC${tc_num}: concurrency group key MISSING per-issue/per-PR serialization (Issue #571 §Layer 5 — must serialize per issue/PR, not globally)" 1
fi

# TC5: concurrency cancel-in-progress is true
tc_num=$((tc_num + 1))
cancel_in_progress=$(python3 -c "
import yaml, sys
with open('$TARGET_FILE') as f:
    doc = yaml.safe_load(f)
conc = doc.get('concurrency', None)
if not isinstance(conc, dict):
    print('not-dict')
else:
    cip = conc.get('cancel-in-progress', None)
    print(str(cip).lower() if cip is not None else 'unset')
" 2>/dev/null)
if [[ "$cancel_in_progress" == "true" ]]; then
  run_tc "TC${tc_num}: concurrency cancel-in-progress is true (Issue #571 §Layer 5 — newer runs supersede older; LATEST label state wins)" 0
elif [[ "$cancel_in_progress" == "false" ]]; then
  run_tc "TC${tc_num}: concurrency cancel-in-progress is FALSE (Issue #571 §Layer 5 VIOLATED — newer runs would queue, not supersede; rate-limit cascade risk)" 1
elif [[ "$cancel_in_progress" == "not-dict" ]]; then
  run_tc "TC${tc_num}: concurrency block not a dict (Issue #571 §Layer 5 — bare 'concurrency: <string>' form not allowed; must be dict with group + cancel-in-progress)" 1
else
  run_tc "TC${tc_num}: concurrency cancel-in-progress UNSET or unrecognized ('$cancel_in_progress'; Issue #571 §Layer 5 requires explicit true)" 1
fi

# TC6: workflow has withRetryOnRateLimit helper function
tc_num=$((tc_num + 1))
# Use wc -l pattern (always emits clean integer, even on no-match) — sister-pattern to d-s35-003-c1 cluster 1 fix (cycle ~#3968Q+847 inline amender pattern)
retry_helper=$(grep -E "function withRetryOnRateLimit|async function withRetryOnRateLimit|withRetryOnRateLimit\s*\(" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$retry_helper" -ge 1 ]]; then
  run_tc "TC${tc_num}: workflow has withRetryOnRateLimit helper function (Issue #571 §Layer 5 rate-limit cascade fix per ADR-0056)" 0
else
  run_tc "TC${tc_num}: workflow MISSING withRetryOnRateLimit helper (Issue #571 §Layer 5 — bare version has no rate-limit retry; ADR-0056 silent-skip contract not implemented)" 1
fi

# TC7: workflow has silentSkipOnRateLimit helper function
tc_num=$((tc_num + 1))
skip_helper=$(grep -E "function silentSkipOnRateLimit|silentSkipOnRateLimit\s*\(" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$skip_helper" -ge 1 ]]; then
  run_tc "TC${tc_num}: workflow has silentSkipOnRateLimit helper function (Issue #571 §silent_skip per ADR-0056 — exhausted-retry rate-limit → exit 0)" 0
else
  run_tc "TC${tc_num}: workflow MISSING silentSkipOnRateLimit helper (Issue #571 §silent_skip per ADR-0056 — bare version lacks selective silent-skip contract)" 1
fi

# TC8: workflow wraps GraphQL block in try-catch (per ADR-0056 §silent_skip)
tc_num=$((tc_num + 1))
# Detect: try { ... await github.graphql ... } pattern in the script block
try_catch_wrap=$(grep -E "^\s*try\s*\{|^\s*\}\s*catch\s*\(" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$try_catch_wrap" -ge 2 ]]; then
  run_tc "TC${tc_num}: workflow wraps GraphQL block in try-catch (Issue #571 §silent_skip per ADR-0056 — exhausted-retry rate-limit errors silently-skip)" 0
elif [[ "$try_catch_wrap" -eq 1 ]]; then
  run_tc "TC${tc_num}: workflow has PARTIAL try-catch (only 1 occurrence found — Issue #571 §silent_skip needs wrap around GraphQL block, not just helper)" 1
else
  run_tc "TC${tc_num}: workflow MISSING try-catch around GraphQL block (Issue #571 §silent_skip per ADR-0056 — bare version has no error containment)" 1
fi

# TC9: actions/github-script SHA-pinned per ADR-0027 + Issue #567 SHA-pin sweep
tc_num=$((tc_num + 1))
# Use wc -l pattern (always emits clean integer) — sister-pattern to TC6 fix
sha_pinned=$(grep -E "actions/github-script@[a-f0-9]{40}" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$sha_pinned" -ge 1 ]]; then
  run_tc "TC${tc_num}: actions/github-script SHA-pinned per ADR-0027 + Issue #567 SHA-pin sweep (commit SHA, not mutable tag; sister-pattern to label-check.yml L54)" 0
else
  run_tc "TC${tc_num}: actions/github-script NOT SHA-pinned (mutable tag or missing; ADR-0027 violation + Issue #567 SHA-pin sweep incomplete)" 1
fi

# TC10: INDEX.md has d-s35-003-c2-status-label-to-board row (Cadence Rule 1 atomic)
tc_num=$((tc_num + 1))
if grep -q "$EXPECTED_NAME" "$INDEX_FILE" 2>/dev/null; then
  run_tc "TC${tc_num}: INDEX.md has $EXPECTED_NAME row (Cadence Rule 1 atomic per ADR-0055 §1)" 0
else
  run_tc "TC${tc_num}: INDEX.md MISSING $EXPECTED_NAME row (Cadence Rule 1 atomic per ADR-0055 §1 violated)" 1
fi

echo ""
total_tcs=$tc_num
if [ "$failed" -eq 0 ]; then
  echo "✅ All $total_tcs TCs GREEN — Sprint 35 S35-003 cluster 2 status-label-to-board forward-port verified"
  echo "   Impl PR ready for cluster-squash per ADR-0059 (≤5 PRs/cluster)"
  exit 0
else
  echo "❌ $failed TC(s) failed of $total_tcs — RED-first contract per ADR-0044"
  echo ""
  echo "Pre-impl RED state expected on bare 199-line status-label-to-board.yml:"
  echo "  PASS today: TC1 (file exists), TC2 (YAML parses), TC9 (SHA-pinned)"
  echo "  RED today:  TC3 (concurrency block), TC4 (serialization key),"
  echo "              TC5 (cancel-in-progress true), TC6 (withRetryOnRateLimit),"
  echo "              TC7 (silentSkipOnRateLimit), TC8 (try-catch wrap),"
  echo "              TC10 (INDEX row)"
  echo ""
  echo "Sprint 33 doctrine layers required (forward-port from atilproject/AtilCalculator 250-line):"
  echo "  - Issue #571 §Layer 5 idempotency reconcile (ADR-0056) — concurrency block"
  echo "  - Issue #571 §Layer 5 rate-limit cascade fix (ADR-0056) — withRetryOnRateLimit"
  echo "  - Issue #571 §silent_skip (ADR-0056) — silentSkipOnRateLimit + try-catch"
  echo "  - Issue #567 SHA-pin sweep — github-script SHA (already PASS today)"
  echo ""
  echo "Sister-pattern: d-s35-003-c1-label-check-sprint33-doctrine-forward-port.sh (10 TCs)"
  exit 1
fi
