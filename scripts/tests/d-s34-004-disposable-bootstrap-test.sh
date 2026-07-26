#!/usr/bin/env bash
# scripts/tests/d-s34-004-disposable-bootstrap-test.sh
# S34-004 d-test — Disposable bootstrap test infra (public + private repo verification)
#
# Sister-pattern: d-s34-005-runner-label-atilcan.sh (S34-005 workflow-only fix 15/15 GREEN
# per cluster-squash #22 — same workflow-file d-test pattern).
#
# 10 TCs RED-first per ADR-0044 (≥6 baseline per ADR-0049, exceeds by 4):
#   TC1: workflow file exists at .github/workflows/disposable-bootstrap-test.yml
#   TC2: bash -n syntactic self-check (YAML tolerated via heredoc-style gate)
#   TC3: workflow has `workflow_dispatch` trigger (AC1 owner-driven manual trigger)
#   TC4: workflow defines `public-repo-bootstrap` job (AC1 public path)
#   TC5: workflow defines `private-repo-bootstrap` job gated on `run_private == 'true'` (AC1+AC2)
#   TC6: workflow has evidence capture (GITHUB_STEP_SUMMARY evidence pattern per AC1)
#   TC7: workflow has teardown step in `if: always()` block (AC1 cleanup invariant)
#   TC8: INDEX.md row present (Cadence Rule 1 atomic attestation per ADR-0055 §1)
#   TC9: CHANGELOG.md entry present (unique "Sprint 34 S34-004 disposable-bootstrap-test" prefix)
#   TC10: 'id: create' on both Create disposable public + private repo steps (NIT-1 BLOCKER
#         fix verification per arch verdict 🟡 cmt 5084623598 + cycle ~#3968Q+847
#         inline d-test amender pattern — without id: create, ${{ steps.create.outputs.REPO_NAME }}
#         resolves EMPTY at runtime, workflow FAILS at clone/delete)
#
# Doctrinal anchors:
#   ADR-0044 RED-first TDD (pre-port RED state NON-VACUOUS, post-port GREEN)
#   ADR-0049 ≥6 TCs baseline (9 TCs exceeds baseline by 3)
#   ADR-0055 §1 Cadence Rule 1 atomic (4-file same commit)
#   ADR-0027 §Threat model (SHA-pinned actions, least-privilege permissions)
#   ADR-0045 9-Lens coverage (lens a-i annotations in workflow header)
#   ADR-0031 owner squash gate (workflows/ human-only territory)
#   Issue #1224 AC1-AC4 (workflow + d-test + evidence + owner gate)
#
# Pre-port RED: 7 PASS + 2 FAIL (TC8 INDEX.md + TC9 CHANGELOG.md) verified NON-VACUOUS
# Post-port GREEN: 9/9 verified locally per cycle ~#3893Q v2 verify-locally-before-verdict
#
# Exit codes: 0 = all GREEN, 1 = at least one TC FAIL

set -uo pipefail

WORKFLOW=".github/workflows/disposable-bootstrap-test.yml"
INDEX="scripts/tests/INDEX.md"
CHANGELOG="CHANGELOG.md"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

pass=0
fail=0

# Helper: assert_pass / assert_fail
assert_pass() {
  local tc_name="$1"
  echo "  [PASS] $tc_name"
  pass=$((pass + 1))
}

assert_fail() {
  local tc_name="$1"
  local reason="$2"
  echo "  [FAIL] $tc_name — $reason"
  fail=$((fail + 1))
}

echo "=== S34-004 d-test: Disposable bootstrap test infra ==="
echo "REPO_ROOT: $REPO_ROOT"
echo ""

# TC1: workflow file exists
echo "TC1: workflow file exists at $WORKFLOW"
if [ -f "$WORKFLOW" ]; then
  assert_pass "TC1"
else
  assert_fail "TC1" "$WORKFLOW not found"
fi

# TC2: YAML syntactic check (Python yaml safe_load)
echo "TC2: workflow YAML syntactic self-check (python yaml.safe_load)"
if python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW'))" 2>/dev/null; then
  assert_pass "TC2"
else
  assert_fail "TC2" "YAML parse failed"
fi

# TC3: workflow_dispatch trigger present
echo "TC3: workflow has 'workflow_dispatch' trigger (AC1 owner-driven manual trigger)"
if grep -q "workflow_dispatch:" "$WORKFLOW"; then
  assert_pass "TC3"
else
  assert_fail "TC3" "workflow_dispatch: trigger not found"
fi

# TC4: public-repo-bootstrap job defined
echo "TC4: workflow defines 'public-repo-bootstrap' job (AC1 public path)"
if grep -q "public-repo-bootstrap:" "$WORKFLOW"; then
  assert_pass "TC4"
else
  assert_fail "TC4" "public-repo-bootstrap job not found"
fi

# TC5: private-repo-bootstrap job defined + gated on run_private
echo "TC5: workflow defines 'private-repo-bootstrap' job gated on 'run_private == true' (AC1+AC2 owner gate)"
if grep -q "private-repo-bootstrap:" "$WORKFLOW" && grep -q "run_private == 'true'" "$WORKFLOW"; then
  assert_pass "TC5"
else
  assert_fail "TC5" "private-repo-bootstrap job or run_private gate not found"
fi

# TC6: evidence capture (GITHUB_STEP_SUMMARY evidence pattern)
echo "TC6: workflow has evidence capture (GITHUB_STEP_SUMMARY evidence pattern per AC1)"
EVIDENCE_COUNT=$(grep -c "GITHUB_STEP_SUMMARY" "$WORKFLOW" 2>/dev/null || echo 0)
if [ "${EVIDENCE_COUNT:-0}" -ge 3 ]; then
  assert_pass "TC6"
else
  assert_fail "TC6" "expected ≥3 GITHUB_STEP_SUMMARY evidence refs, found ${EVIDENCE_COUNT:-0}"
fi

# TC7: teardown step in `if: always()` block
echo "TC7: workflow has teardown step in 'if: always()' block (AC1 cleanup invariant)"
if grep -q "Teardown" "$WORKFLOW" && grep -B1 "if: always()" "$WORKFLOW" | grep -q "Teardown"; then
  assert_pass "TC7"
else
  assert_fail "TC7" "Teardown step in 'if: always()' not found"
fi

# TC8: INDEX.md row present
echo "TC8: INDEX.md row present (Cadence Rule 1 atomic attestation)"
if grep -q "d-s34-004-disposable-bootstrap-test" "$INDEX" 2>/dev/null; then
  assert_pass "TC8"
else
  assert_fail "TC8" "INDEX.md row for d-s34-004 not found"
fi

# TC9: CHANGELOG.md entry present (unique Sprint 34 S34-004 disposable-bootstrap-test prefix)
echo "TC9: CHANGELOG.md entry present (unique 'Sprint 34 S34-004 disposable-bootstrap-test' prefix)"
if grep -q "Sprint 34 S34-004 disposable-bootstrap-test" "$CHANGELOG" 2>/dev/null; then
  assert_pass "TC9"
else
  assert_fail "TC9" "CHANGELOG.md entry for Sprint 34 S34-004 disposable-bootstrap-test not found"
fi

# TC10 (NIT-1 BLOCKER amender per arch verdict 🟡 cmt 5084623598 + cycle ~#3968Q+847
# owner-override inline d-test amender pattern): verify `id: create` is present on
# both Create disposable public repo + Create disposable private repo steps.
# Without id: create, ${{ steps.create.outputs.REPO_NAME }} (referenced at workflow
# lines 87/105/154 — clone/delete) resolves to EMPTY at runtime → workflow FAILS.
echo "TC10: workflow has 'id: create' on both Create disposable public + private repo steps"
PUBLIC_CREATE_LINE=$(grep -n "name: Create disposable public repo" "$WORKFLOW" | head -1 | cut -d: -f1)
PRIVATE_CREATE_LINE=$(grep -n "name: Create disposable private repo" "$WORKFLOW" | head -1 | cut -d: -f1)
PUBLIC_HAS_ID=0
PRIVATE_HAS_ID=0
if [ -n "$PUBLIC_CREATE_LINE" ]; then
  if sed -n "${PUBLIC_CREATE_LINE},/env:/p" "$WORKFLOW" | grep -q "id: create"; then
    PUBLIC_HAS_ID=1
  fi
fi
if [ -n "$PRIVATE_CREATE_LINE" ]; then
  if sed -n "${PRIVATE_CREATE_LINE},/env:/p" "$WORKFLOW" | grep -q "id: create"; then
    PRIVATE_HAS_ID=1
  fi
fi
if [ "$PUBLIC_HAS_ID" -eq 1 ] && [ "$PRIVATE_HAS_ID" -eq 1 ]; then
  assert_pass "TC10"
else
  assert_fail "TC10" "expected 'id: create' on both Create disposable public (line ${PUBLIC_CREATE_LINE:-?}) and private (line ${PRIVATE_CREATE_LINE:-?}) repo steps, found public=${PUBLIC_HAS_ID} private=${PRIVATE_HAS_ID}"
fi

echo ""
echo "=== Summary ==="
echo "PASS: $pass / 10"
echo "FAIL: $fail / 10"

if [ "$fail" -eq 0 ]; then
  echo "RESULT: GREEN — d-s34-004 10/10 GREEN"
  exit 0
else
  echo "RESULT: RED — d-s34-004 $fail FAIL"
  exit 1
fi