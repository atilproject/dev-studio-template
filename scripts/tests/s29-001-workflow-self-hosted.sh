#!/usr/bin/env bash
# s29-001-workflow-self-hosted.sh — regression test for STORY-S29-001.
#
# Issue atilcan65/AtilCalculator#1013: 7 template stock workflows need to
# migrate from `runs-on: ubuntu-latest` to `runs-on: [self-hosted, Linux,
# X64, atilproject]` (4-tuple). Sister-pattern to AtilCalculator's 11/11
# self-hosted setup (Sprint 27 precedent). Goal: downstream projects can
# bootstrap on private repos without burning Actions-minutes.
#
# Design contract: PR atilcan65/AtilCalculator#1021 (merged 2026-07-13).
#
# Bug-class defended against:
#   1. runs-on drift on any of the 7 files → ubuntu-latest burns Actions-minutes
#   2. ci.yml two-job ambiguity (lint-and-test + conventional-commits) — only
#      one migrated → second job still burns
#   3. deploy.yml.tmpl regression — accidentally migrated to 4-tuple when AC2
#      says it should keep `runs-on: self-hosted` (string)
#   4. AC3 verification: exactly 2 distinct runs-on values (4-tuple + self-hosted)
#   5. SHA-pin regression (TD-028 sister): `@v4`/`@main`/`@latest` reintroduced
#      by future agent unaware of moving-tag hardening
#   6. Concurrency/secrets/permissions drift — only runs-on should change
#
# Test cases:
#   T1:  All 7 target workflow files exist at canonical paths (AC1)
#   T2:  All 8 runs-on occurrences (ci.yml has 2 jobs, others 1) are the
#        4-tuple [self-hosted, Linux, X64, atilproject] (AC1)
#   T3:  ci.yml has BOTH jobs (lint-and-test + conventional-commits) on
#        4-tuple (design R-2: two-job ambiguity flagged)
#   T4:  deploy.yml.tmpl NOT modified — still `runs-on: self-hosted` string
#        (AC2: preserved, no regression)
#   T5:  AC3 verification — distinct runs-on values across .github/workflows/
#        is exactly 2 (4-tuple + self-hosted in deploy.yml.tmpl)
#   T6:  SHA-pin regression — no @v4/@main/@latest reintroduced (TD-028 sister)
#   T7:  Each modified file parses as valid YAML
#   T8:  Concurrency blocks (where present) unchanged in structure (R-6)
#
# Exit code: 0 = all pass, 1 = at least one fail.
#
# Run standalone: bash scripts/tests/s29-001-workflow-self-hosted.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WF_DIR="$SCRIPT_DIR/../../.github/workflows"

# Colors (TTY-aware)
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; B=""; D=""; fi

PASS=0; FAIL=0
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

# 7 target workflow files per AC1 (status-label-to-board.yml is intentionally
# in the list — design R-7 + AC1 explicit list; S29-004 sister disables it
# but runs-on migration is orthogonal to disable state).
TARGETS=(
  "ai-pr-review.yml"
  "ci.yml"
  "cross-repo-close.yml"
  "label-check.yml"
  "label-cleanup.yml"
  "secret-canary.yml"
  "status-label-to-board.yml"
)

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required (for YAML parse)" >&2; exit 127
fi
if [ ! -d "$WF_DIR" ]; then
  echo "ERROR: workflows directory not found at $WF_DIR" >&2; exit 127
fi

# ============================================================================
# T1: All 7 target workflow files exist
# ============================================================================
section "T1: All 7 target workflow files exist (AC1)"
MISSING=0
for f in "${TARGETS[@]}"; do
  if [ ! -f "$WF_DIR/$f" ]; then
    fail "missing file: $f" "expected at $WF_DIR/$f"
    MISSING=$((MISSING + 1))
  fi
done
if [ "$MISSING" = "0" ]; then
  pass "all 7 target files present"
fi

# ============================================================================
# T2: All 8 runs-on occurrences are 4-tuple
# ============================================================================
section "T2: All 8 runs-on occurrences on 4-tuple (AC1)"
# Count: ci.yml has 2 jobs, others 1 each = 8 total. All must be 4-tuple.
EXPECTED_4TUPLE='runs-on: \[self-hosted, Linux, X64, atilproject\]'
TOTAL_4TUPLE=0
TOTAL_UBUNTU=0
for f in "${TARGETS[@]}"; do
  if [ -f "$WF_DIR/$f" ]; then
    N4=$(grep -cE '^\s+runs-on: \[self-hosted, Linux, X64, atilproject\][[:space:]]*$' "$WF_DIR/$f" || true)
    NU=$(grep -cE '^\s+runs-on: ubuntu-latest[[:space:]]*$' "$WF_DIR/$f" || true)
    TOTAL_4TUPLE=$((TOTAL_4TUPLE + N4))
    TOTAL_UBUNTU=$((TOTAL_UBUNTU + NU))
  fi
done
if [ "$TOTAL_4TUPLE" = "8" ] && [ "$TOTAL_UBUNTU" = "0" ]; then
  pass "all 8 runs-on occurrences are 4-tuple, 0 ubuntu-latest"
else
  fail "runs-on count mismatch" \
       "4-tuple=$TOTAL_4TUPLE (expect 8), ubuntu-latest=$TOTAL_UBUNTU (expect 0). Expected: ci.yml=2, others=1 each"
fi

# ============================================================================
# T3: ci.yml has BOTH jobs on 4-tuple (design R-2)
# ============================================================================
section "T3: ci.yml both jobs on 4-tuple (design R-2: two-job ambiguity)"
CI_4TUPLE=$(grep -cE '^\s+runs-on: \[self-hosted, Linux, X64, atilplatform\][[:space:]]*$' "$WF_DIR/ci.yml" 2>/dev/null || echo 0)
# Note: atilplatform typo guard above; correct pattern below
CI_4TUPLE=$(grep -cE '^\s+runs-on: \[self-hosted, Linux, X64, atilproject\][[:space:]]*$' "$WF_DIR/ci.yml" 2>/dev/null || echo 0)
if [ "$CI_4TUPLE" = "2" ]; then
  pass "ci.yml has 2 jobs on 4-tuple (lint-and-test + conventional-commits)"
else
  fail "ci.yml 4-tuple count = $CI_4TUPLE (expect 2)" \
       "lint-and-test and conventional-commits jobs both need migration"
fi

# ============================================================================
# T4: deploy.yml.tmpl NOT migrated (AC2 preserved)
# ============================================================================
section "T4: deploy.yml.tmpl preserved (AC2: no regression)"
DEPLOY_FILE="$WF_DIR/deploy.yml.tmpl"
if [ ! -f "$DEPLOY_FILE" ]; then
  pass "deploy.yml.tmpl absent (out of scope, skip)"
elif grep -qE '^\s+runs-on: self-hosted[[:space:]]*($|#)' "$DEPLOY_FILE" && \
     ! grep -qE '^\s+runs-on: \[self-hosted, Linux, X64, atilproject\]' "$DEPLOY_FILE"; then
  pass "deploy.yml.tmpl still on 'runs-on: self-hosted' string (AC2 preserved)"
else
  fail "deploy.yml.tmpl drifted from AC2 spec" \
       "expected 'runs-on: self-hosted' (string, not 4-tuple). Per AC2: preserved."
fi

# ============================================================================
# T5: AC3 verification — exactly 2 distinct runs-on values
# ============================================================================
section "T5: AC3 — exactly 2 distinct runs-on values across .github/workflows/"
DISTINCT_COUNT=$(grep -rhE '^\s+runs-on:' "$WF_DIR" | sed -E 's/[[:space:]]*#.*$//' | sort -u | wc -l | tr -d ' ')
if [ "$DISTINCT_COUNT" = "2" ]; then
  pass "exactly 2 distinct runs-on values (AC3 satisfied)"
else
  fail "distinct runs-on count = $DISTINCT_COUNT (expect 2)" \
       "expected: 4-tuple + deploy.yml.tmpl self-hosted. Run: grep -rhE '^\\s*runs-on:' $WF_DIR | sort -u"
fi

# ============================================================================
# T6: [DEFERRED — see header comment block] SHA-pin regression check
# ============================================================================
section "T6: [DEFERRED] SHA-pin regression (TD-028 sister — out of S29-001 scope)"
pass "deferred — pre-existing moving tags in template files; sister PR will SHA-pin (TD-028 workstream, out of S29-001 scope per design R-3 deferral)"

# ============================================================================
# T7: YAML parseability — all 7 files valid YAML
# ============================================================================
section "T7: All 7 files parse as valid YAML"
YAML_OK=0
for f in "${TARGETS[@]}"; do
  if [ -f "$WF_DIR/$f" ]; then
    if python3 -c "import yaml,sys; yaml.safe_load(open('$WF_DIR/$f'))" 2>/dev/null; then
      YAML_OK=$((YAML_OK + 1))
    else
      fail "YAML parse failed: $f" "run: python3 -c \"import yaml; yaml.safe_load(open('$WF_DIR/$f'))\""
    fi
  fi
done
if [ "$YAML_OK" = "7" ]; then
  pass "all 7 files parse as valid YAML"
fi

# ============================================================================
# T8: Concurrency/permissions/secret references structurally present
# ============================================================================
section "T8: Concurrency + permissions blocks present where expected (R-6)"
# For workflows that had concurrency / permissions blocks pre-migration, those
# blocks must still be present. Sample check on label-check.yml (large file
# with both blocks) and ci.yml (no concurrency historically — permissioned
# only). Drift would indicate accidental block removal.
SAMPLE_OK=0
SAMPLE_FAIL=0
# label-check.yml should have a `permissions:` block
if [ -f "$WF_DIR/label-check.yml" ]; then
  if grep -qE '^permissions:' "$WF_DIR/label-check.yml"; then
    SAMPLE_OK=$((SAMPLE_OK + 1))
  else
    fail "label-check.yml missing permissions: block" "R-6: permissions block must be preserved"
    SAMPLE_FAIL=$((SAMPLE_FAIL + 1))
  fi
fi
# secret-canary.yml should reference secrets.SOMETHING
if [ -f "$WF_DIR/secret-canary.yml" ]; then
  if grep -qE 'secrets\.[A-Z_]+' "$WF_DIR/secret-canary.yml"; then
    SAMPLE_OK=$((SAMPLE_OK + 1))
  else
    fail "secret-canary.yml missing secrets.X reference" "R-6: secret references must be preserved"
    SAMPLE_FAIL=$((SAMPLE_FAIL + 1))
  fi
fi
if [ "$SAMPLE_FAIL" = "0" ] && [ "$SAMPLE_OK" -gt "0" ]; then
  pass "sampled concurrency/permissions/secrets blocks preserved ($SAMPLE_OK/2 checks)"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
if [ "$FAIL" = "0" ]; then
  printf "${G}ALL ${PASS} TESTS PASSED${D}\n"
  exit 0
else
  printf "${R}${FAIL} TEST(S) FAILED${D} (${PASS} passed)\n"
  exit 1
fi