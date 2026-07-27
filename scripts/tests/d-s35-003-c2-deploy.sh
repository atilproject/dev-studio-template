#!/usr/bin/env bash
# d-s35-003-c2-deploy.sh —
#   Sprint 35 S35-003 cluster 2 RED-first d-test verifying deploy.yml
#   forward-port from bare 112-line tmpl → AtilCalculator's post-Sprint 33
#   123-line canonical (DEPLOY-001 v5 doctrinal anchors forward-port).
#
# Why this test exists
# --------------------
# Sprint 35 S35-003 cluster 2 forward-ports 4 sister workflows from the bare
# dev-studio-template canonical to AtilCalculator's post-Sprint 33 status.
# Per ADR-0075 template-launcher-parity-matrix, dev-studio-template = source
# of truth for new project bootstraps, so a new project scaffolded today would
# land with the bare version, missing:
#
#   - **DEPLOY-001 v5 doctrinal anchors** — bare version header is
#     "S29-010 themed impl PR 4/4 (PR-D) — DEPLOY-001 v5 + S29-001 4-tuple
#     baseline" with OWNER APPROVAL GRANTED gate notes + PR #1047 d0cf929
#     reference + S29-001 4-tuple render adaptation notes. This is the
#     TEMPLATE-RENDERED INSTANCE adaptation, NOT the canonical doctrinal
#     home.
#
#     Canonical AtilCalculator header is "DEPLOY-001 v5 (refs #130, #138,
#     #155, ADR-0030)" with full doctrinal cite of Issues #130 (DEPLOY-001
#     user story), #138 (P0 incident), #143 (DEPLOY-005 self-hosted runner),
#     #145 (workflow YAML update), #148 (RCA-5/6 closed by v4), #152 (RCA-7/8
#     P0 incident — manual unblock at 2026-06-20T05:02:42Z), #155 (DEPLOY-001
#     v5 spec), ADR-0030 (self-hosted runner for LAN deploy — SUPERSEDES
#     ADR-0027 §1), ADR-0027 §Decision.2+3+5 (unchanged), ADR-0030 §Threat
#     model (push-only trigger, gh-actions-runner user hardening, SHA pinning),
#     ADR-0010 (prod host + systemd user-service precedent), DEPLOY-003 (#132,
#     #134 merged) — GET /healthz smoke-test target.
#
#   - **S29-010 OWNER APPROVAL header REMOVED** — bare version's OWNER
#     APPROVAL GRANTED note (2026-07-13T21:01Z by @atilcan65) + S29-001
#     4-tuple render adaptations are template-instance-specific, NOT
#     canonical doctrinal content. Forward-port MUST remove.
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
#   - d-s35-003-c2-lint-and-test.sh — direct sister (cluster 2 #3, 10 TCs)
#   - d-s35-003-c1-label-check-sprint33-doctrine-forward-port.sh — cluster 1
#     direct sister (10 TCs, workflow-file d-test)
#   - d-s34-005-runner-label-atilcan.sh — workflow-file d-test sister
#     (15 TCs, sed verification of `atilproject` → `atilcan` label across
#     10 workflow files)
#   - d-s34-004-disposable-bootstrap-test.sh — workflow-file d-test sister
#   - d096-soul-files-template.sh — d-test framework ≥5 TCs baseline (ADR-0049)
#
# 10 TCs (≥6 baseline per ADR-0049 + ADR-0044; ≥5 d-test framework + 5 Sprint 33
# doctrine-layer specific):
#   TC1: workflow file exists at .github/workflows/deploy.yml
#   TC2: YAML syntactic check (Python yaml.safe_load parses cleanly)
#   TC3: workflow has `DEPLOY-001 v5` doctrinal header anchor (canonical
#        Issue #130 / #138 / #155 doctrinal cite)
#   TC4: workflow does NOT have `S29-010 themed impl PR` header (template
#        render adaptation must be REMOVED in forward-port)
#   TC5: workflow references Issue #130 (canonical anchor — DEPLOY-001
#        user story + closed)
#   TC6: workflow references ADR-0030 (canonical anchor — self-hosted
#        runner for LAN deploy, SUPERSEDES ADR-0027 §1)
#   TC7: SHA-pinned `actions/checkout` per ADR-0027 + Issue #567 SHA-pin
#        sweep (commit SHA `b4ffde6...`, NOT mutable tag — currently PASS)
#   TC8: 9-Lens coverage header comment present (ADR-0045 — lens a-i
#        annotations; sister-pattern to other workflow files)
#   TC9: INDEX.md has d-s35-003-c2-deploy row (Cadence Rule 1 atomic
#        per ADR-0055 §1)
#   TC10: CHANGELOG.md has "Sprint 35 S35-003 cluster 2 deploy" entry
#         (unique prefix so duplicate-file detection works)
#
# Pre-impl RED state (verified 2026-07-27T20:54Z against bare 112-line target):
#   - TC1: PASS (file exists)
#   - TC2: PASS (YAML parses)
#   - TC3: FAIL (no DEPLOY-001 v5 doctrinal anchor — bare has S29-010 themed header)
#   - TC4: FAIL (S29-010 themed impl PR header still present in bare)
#   - TC5: FAIL (no Issue #130 reference in bare)
#   - TC6: FAIL (no ADR-0030 reference in bare — bare uses S29-001 4-tuple instead)
#   - TC7: PASS (SHA-pinned actions/checkout already present)
#   - TC8: PASS (9-Lens coverage header present)
#   - TC9: FAIL (no INDEX.md row yet)
#   - TC10: FAIL (no CHANGELOG.md entry yet)
# Expected exit code: 1 (RED state) per ADR-0044 RED-first VERIFIED.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOWS_DIR="$SCRIPT_DIR/../../.github/workflows"
TARGET_FILE="$WORKFLOWS_DIR/deploy.yml"
INDEX_FILE="$SCRIPT_DIR/INDEX.md"
CHANGELOG_FILE="$SCRIPT_DIR/../../CHANGELOG.md"
EXPECTED_NAME="d-s35-003-c2-deploy"
EXPECTED_CHANGELOG_PREFIX="Sprint 35 S35-003 cluster 2 deploy"

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

echo "==== d-s35-003-c2-deploy ===="
echo "Target: $TARGET_FILE"
echo "INDEX:  $INDEX_FILE"
echo "CHANGELOG: $CHANGELOG_FILE"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# TC1: workflow file exists
tc_num=$((tc_num + 1))
if [ -f "$TARGET_FILE" ]; then
  run_tc "TC${tc_num}: workflow file exists at .github/workflows/deploy.yml" 0
else
  run_tc "TC${tc_num}: workflow file MISSING at .github/workflows/deploy.yml" 1
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

# TC3: workflow has DEPLOY-001 v5 doctrinal anchor (canonical Issue #130 / #138 / #155 cite)
tc_num=$((tc_num + 1))
# Use wc -l for clean integer output (cycle ~#3968Q+847 inline d-test amender pattern)
deploy_anchor=$(grep -E "DEPLOY-001 v5" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$deploy_anchor" -ge 1 ]]; then
  run_tc "TC${tc_num}: workflow has DEPLOY-001 v5 doctrinal anchor (canonical Issue #130 / #138 / #155 cite)" 0
else
  run_tc "TC${tc_num}: workflow MISSING DEPLOY-001 v5 doctrinal anchor (bare has S29-010 themed header instead — forward-port must swap to canonical)" 1
fi

# TC4: workflow does NOT have S29-010 themed impl PR header (template adaptation REMOVED)
tc_num=$((tc_num + 1))
s29_ref=$(grep -E "S29-010 themed impl PR|S29-001 4-tuple baseline|PR #1047 d0cf929" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$s29_ref" -eq 0 ]]; then
  run_tc "TC${tc_num}: workflow does NOT have S29-010 themed impl PR header (template render adaptation REMOVED — canonical doctrinal cite applied)" 0
else
  run_tc "TC${tc_num}: workflow STILL has S29-010 themed impl PR header ($s29_ref occurrences — template adaptation NOT removed; forward-port incomplete)" 1
fi

# TC5: workflow references Issue #130 (canonical anchor — DEPLOY-001 user story + closed)
tc_num=$((tc_num + 1))
issue_130=$(grep -E "Issue #130|#130" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$issue_130" -ge 1 ]]; then
  run_tc "TC${tc_num}: workflow references Issue #130 (canonical anchor — DEPLOY-001 user story + closed)" 0
else
  run_tc "TC${tc_num}: workflow MISSING Issue #130 reference (bare has S29-001 4-tuple anchor instead — canonical doctrinal cite missing)" 1
fi

# TC6: workflow references ADR-0030 (canonical anchor — self-hosted runner for LAN deploy)
tc_num=$((tc_num + 1))
adr_0030=$(grep -E "ADR-0030" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$adr_0030" -ge 1 ]]; then
  run_tc "TC${tc_num}: workflow references ADR-0030 (canonical anchor — self-hosted runner for LAN deploy, SUPERSEDES ADR-0027 §1)" 0
else
  run_tc "TC${tc_num}: workflow MISSING ADR-0030 reference (bare uses S29-001 4-tuple anchor instead — canonical doctrinal cite missing)" 1
fi

# TC7: SHA-pinned actions/checkout per ADR-0027 + Issue #567 SHA-pin sweep
tc_num=$((tc_num + 1))
# Look for SHA-pinned actions/checkout (40-char hex SHA, not mutable tag like @v4)
sha_pinned=$(grep -E "actions/checkout@[a-f0-9]{40}" "$TARGET_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$sha_pinned" -ge 1 ]]; then
  run_tc "TC${tc_num}: actions/checkout SHA-pinned per ADR-0027 + Issue #567 SHA-pin sweep (commit SHA b4ffde6..., NOT mutable @v4 tag)" 0
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
  echo "✅ All $total_tcs TCs GREEN — Sprint 35 S35-003 cluster 2 deploy forward-port verified"
  echo "   Impl PR ready for cluster-squash per ADR-0059 (≤5 PRs/cluster)"
  exit 0
else
  echo "❌ $failed TC(s) failed of $total_tcs — RED-first contract per ADR-0044"
  echo ""
  echo "Pre-impl RED state expected on bare 112-line deploy.yml:"
  echo "  PASS today: TC1 (file exists), TC2 (YAML parses),"
  echo "              TC7 (SHA-pinned actions/checkout), TC8 (9-Lens header)"
  echo "  RED today:  TC3 (DEPLOY-001 v5 anchor MISSING — bare has S29-010 header),"
  echo "              TC4 (S29-010 themed impl PR header STILL PRESENT — must be removed),"
  echo "              TC5 (Issue #130 reference MISSING — bare uses S29-001 4-tuple),"
  echo "              TC6 (ADR-0030 reference MISSING — bare uses S29-001 4-tuple),"
  echo "              TC9 (INDEX.md row missing), TC10 (CHANGELOG.md entry missing)"
  echo ""
  echo "Sprint 33 doctrine layers required (forward-port from atilproject/AtilCalculator 123-line):"
  echo "  - DEPLOY-001 v5 doctrinal anchor (Issue #130 / #138 / #155 + ADR-0030)"
  echo "  - Issue #130 (DEPLOY-001 user story + closed)"
  echo "  - Issue #138 (P0 incident — public runner could not reach private LAN)"
  echo "  - Issue #143 (DEPLOY-005 self-hosted runner install, owner-impl in flight)"
  echo "  - Issue #152 (RCA-7 + RCA-8 P0 incident)"
  echo "  - Issue #155 (DEPLOY-001 v5 spec — RCA-7 4-layer fix)"
  echo "  - ADR-0030 (self-hosted runner for LAN deploy — SUPERSEDES ADR-0027 §1)"
  echo "  - ADR-0027 §Decision.2+3+5 (secrets, smoke test + rollback, idempotency — unchanged)"
  echo "  - ADR-0030 §Threat model (push-only trigger, gh-actions-runner user hardening, SHA pinning)"
  echo "  - ADR-0010 (prod host + systemd user-service precedent; Sprint 4 supplement needed)"
  echo "  - DEPLOY-003 (#132, #134 merged) — GET /healthz smoke-test target"
  echo ""
  echo "Sister-pattern: d-s35-003-c2-status-label-to-board.sh (10 TCs, workflow-file d-test)"
  echo "Sister-pattern: d-s35-003-c2-label-cleanup.sh (10 TCs, cluster 2 #2)"
  echo "Sister-pattern: d-s35-003-c2-lint-and-test.sh (10 TCs, cluster 2 #3)"
  echo "Sister-pattern: d-s35-003-c1-label-check-sprint33-doctrine-forward-port.sh (10 TCs, cluster 1)"
  exit 1
fi