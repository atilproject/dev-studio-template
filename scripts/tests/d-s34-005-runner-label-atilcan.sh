#!/usr/bin/env bash
# d-s34-005-runner-label-atilcan.sh — Sprint 34 S34-005 runner label atilproject → atilcan sed verification
#
# Verifies S34-005 dispatch: 10 .github/workflows/*.yml files have self-hosted runner
# labels changed from `[self-hosted, Linux, X64, atilproject]` to
# `[self-hosted, Linux, X64, atilcan]` per Issue #1225 (owner-approved 22:10+03:00).
#
# Per ADR-0044 RED-first + ADR-0049 ≥6 TCs baseline.
#
# Usage: bash scripts/tests/d-s34-005-runner-label-atilcan.sh
# Exit: 0 = all TCs GREEN, non-zero = TC failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOWS_DIR="$SCRIPT_DIR/../../.github/workflows"
INDEX_FILE="$SCRIPT_DIR/INDEX.md"
CHANGELOG_FILE="$SCRIPT_DIR/../../CHANGELOG.md"

# S34-005 dispatch scope (Issue #1225 audit-verified 10 files)
SCOPE_FILES=(
  "ai-pr-review.yml"
  "ci.yml"
  "cross-repo-close.yml"
  "d050b-dispatch.yml"
  "deploy.yml"
  "label-check.yml"
  "label-cleanup.yml"
  "lint-and-test.yml"
  "post-squash.yml"
  "secret-canary.yml"
)

# Out-of-scope (NOT changed per orchestrator dispatch — preserves atilproject label)
OUT_OF_SCOPE="status-label-to-board.yml"

EXPECTED_LABEL="\[self-hosted, Linux, X64, atilcan\]"
FORBIDDEN_LABEL="\[self-hosted, Linux, X64, atilproject\]"

failed=0
tc_num=0

run_tc() {
  local tc_name="$1"
  local result="$2"
  if [ "$result" -eq 0 ]; then
    echo "✅ ${tc_name}"
  else
    echo "❌ ${tc_name}"
    failed=$((failed + 1))
  fi
}

# TC1: workflows directory exists
tc_num=$((tc_num + 1))
if [ -d "$WORKFLOWS_DIR" ]; then
  run_tc "TC${tc_num}: workflows directory exists at $WORKFLOWS_DIR" 0
else
  run_tc "TC${tc_num}: workflows directory MISSING at $WORKFLOWS_DIR" 1
fi

# TC2-TC11: each scope file present + has atilcan label
for f in "${SCOPE_FILES[@]}"; do
  tc_num=$((tc_num + 1))
  filepath="$WORKFLOWS_DIR/$f"
  if [ ! -f "$filepath" ]; then
    run_tc "TC${tc_num}: $f MISSING at $filepath" 1
    continue
  fi
  grep_count=$(grep -E "$EXPECTED_LABEL" "$filepath" 2>/dev/null | wc -l)
  if [ "$grep_count" -ge 1 ]; then
    run_tc "TC${tc_num}: $f has $grep_count atilcan self-hosted label(s)" 0
  else
    run_tc "TC${tc_num}: $f has 0 atilcan self-hosted labels (sed not applied?)" 1
  fi
done

# TC12: no residual atilproject in scope files
tc_num=$((tc_num + 1))
residual_count=0
for f in "${SCOPE_FILES[@]}"; do
  filepath="$WORKFLOWS_DIR/$f"
  if [ -f "$filepath" ]; then
    count=$(grep -E "$FORBIDDEN_LABEL" "$filepath" 2>/dev/null | wc -l)
    residual_count=$((residual_count + count))
  fi
done
if [ "$residual_count" -eq 0 ]; then
  run_tc "TC${tc_num}: 0 residual [atilproject] self-hosted labels in scope files (sed complete)" 0
else
  run_tc "TC${tc_num}: $residual_count residual [atilproject] labels in scope (sed incomplete)" 1
fi

# TC13: out-of-scope file preserved
tc_num=$((tc_num + 1))
oos_filepath="$WORKFLOWS_DIR/$OUT_OF_SCOPE"
if [ ! -f "$oos_filepath" ]; then
  run_tc "TC${tc_num}: out-of-scope file $OUT_OF_SCOPE NOT present (skip — non-blocking)" 0
else
  oos_grep_count=$(grep -E "$FORBIDDEN_LABEL" "$oos_filepath" 2>/dev/null | wc -l)
  if [ "$oos_grep_count" -ge 1 ]; then
    run_tc "TC${tc_num}: out-of-scope $OUT_OF_SCOPE preserved atilproject label ($oos_grep_count occurrence) — dispatch scope fidelity" 0
  else
    run_tc "TC${tc_num}: out-of-scope $OUT_OF_SCOPE unexpectedly changed (dispatch scope violation)" 1
  fi
fi

# TC14: INDEX.md row present
tc_num=$((tc_num + 1))
if grep -q "d-s34-005-runner-label-atilcan" "$INDEX_FILE"; then
  run_tc "TC${tc_num}: INDEX.md row present (Cadence Rule 1 atomic marker per ADR-0055 §1)" 0
else
  run_tc "TC${tc_num}: INDEX.md row MISSING for d-s34-005-runner-label-atilcan" 1
fi

# TC15: CHANGELOG.md entry present
tc_num=$((tc_num + 1))
if grep -q "S34-005" "$CHANGELOG_FILE" && grep -q "Issue #1225" "$CHANGELOG_FILE"; then
  run_tc "TC${tc_num}: CHANGELOG.md entry present (Sprint 34 S34-005 Issue #1225)" 0
else
  run_tc "TC${tc_num}: CHANGELOG.md entry MISSING for Sprint 34 S34-005 Issue #1225" 1
fi

echo ""
total_tcs=$tc_num
if [ "$failed" -eq 0 ]; then
  echo "✅ All $total_tcs TCs GREEN — Sprint 34 S34-005 runner label atilcan verified"
  echo "   Issue #1225 (Closes #1225 anchor)"
  echo "   Scope: 10 .github/workflows/*.yml files"
  echo "   Label: [self-hosted, Linux, X64, atilcan]"
  exit 0
else
  echo "❌ $failed TC(s) failed — RED-first contract per ADR-0044"
  exit 1
fi
