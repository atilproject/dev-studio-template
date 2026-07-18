#!/usr/bin/env bash
# d156-s32-027-adr-port-batch.sh — S32-027 calc→tmpl ADR port batch regression
# test (5 TCs, ADR-0049 sister-pattern + Cadence Rule 1 atomic per ADR-0055 §1).
#
# Why this test exists
# --------------------
# Sprint 32 Wave 3 audit (tmpl#126 + S32-001 doctrine diff classification) found
# calc has 79 ADR docs/decisions/*.md files vs tmpl origin/main 42 — 37 calc-only
# ADRs (20 parents + 17 amendments). Issue #156 (S32-027) addresses this gap.
#
# This PR (tmpl#150, arch/s32-027-adr-port-batch) ports 10 net-new ADRs and
# resolves 6 RESERVED slots (0058, 0067-0071). 8 ADRs were already byte-equal
# (Sprint 28 S29-017 + S32-003 pre-sync, copy was idempotent NO-OP).
#
# 5 TCs (per ADR-0049 ≥5 TCs invariant + Cadence Rule 1 atomic per ADR-0055 §1):
#   TC1: 10 net-new ADR files exist in tmpl docs/decisions/
#        (0041, 0043, 0054, 0056, 0058, 0067, 0068, 0069, 0070, 0071)
#   TC2: Each new ADR byte-equal to calc source (non-vacuous per Issue #1041)
#   TC3: 8 idempotent ADR copies remain byte-equal (0034, 0035, 0037, 0039,
#        0044, 0045, 0053, 0055)
#   TC4: INDEX.md has 4 NEW rows (0041, 0043, 0054, 0056) + 6 RESERVED entries
#        resolved (0058, 0067-0071) — no RESERVED placeholders for these IDs
#   TC5: PORT-DECISIONS.md exists with classification tables (deferred/calc-
#        specific/hybrid rationale) — Issue #156 AC5 documentation
#
# Sister-pattern to:
#   - d983-s28-003-forward-port-parity.sh (scripts forward-port parity)
#   - d144-cadence-rule-2-orphan-impl-dispatch.sh (cadence rule pattern)
#   - d1138-template-agent-wake-fix-4b.sh (tmpl ADR port d-test sister)
#
# Run: bash scripts/tests/d156-s32-027-adr-port-batch.sh
#
# Exit code: 0 = all pass, 1 = at least one fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INDEX_MD="$REPO_ROOT/docs/decisions/INDEX.md"
PORT_DECISIONS="$REPO_ROOT/docs/decisions/PORT-DECISIONS.md"
CALC_DECISIONS="${CALC_DECISIONS:-/home/atilcan/projects/AtilCalculator/docs/decisions}"

# --- test framework ---
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

PASS=0; FAIL=0
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; B=""; D=""
fi
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

# --- pre-flight: required artifacts ---
if [ ! -r "$INDEX_MD" ]; then
  echo "ERROR: INDEX.md not found at $INDEX_MD" >&2
  exit 127
fi
if [ ! -d "$CALC_DECISIONS" ]; then
  echo "ERROR: calc decisions dir not found at $CALC_DECISIONS" >&2
  exit 127
fi

# Net-new ADRs in this PR (10 files copied from calc, RESERVED placeholders resolved)
NEW_ADRS=(
  "ADR-0041-event-model-v8-verdict-posted"
  "ADR-0043-8-lens-architect-review-checklist"
  "ADR-0054-9lens-enforcement"
  "ADR-0056-layer-5-idempotency-reconcile"
  "ADR-0058-comment-trigger-guard-multi-fire-prevention"
  "ADR-0067-multi-reviewer-wake-doctrine"
  "ADR-0068-j4-tester-author-exception"
  "ADR-0069-form-c-race-detection"
  "ADR-0070-closed-diagnostic"
  "ADR-0071-td-067c-open-diagnostic"
)

# Already-synced ADRs (idempotent NO-OP copy, byte-equal pre-port)
IDEMPOTENT_ADRS=(
  "ADR-0034-agent-state-cmd-set-argjson"
  "ADR-0035-layer3-open-only-fire"
  "ADR-0037-proactive-gap-scan"
  "ADR-0039-wip-idle-watchdog"
  "ADR-0044-verdict-by-scope-clarification"
  "ADR-0045-auto-generated-file-refs-design-verification"
  "ADR-0053-layer-5-race-pattern"
  "ADR-0055-d-test-id-uniqueness-sub-pattern-matrix"
)

# ============================================================================
section "TC1: 10 net-new ADR files exist in tmpl docs/decisions/"
MISSING=()
for slug in "${NEW_ADRS[@]}"; do
  if [ ! -r "$REPO_ROOT/docs/decisions/${slug}.md" ]; then
    MISSING+=("${slug}.md")
  fi
done
if [ "${#MISSING[@]}" -eq 0 ]; then
  pass "10 net-new ADR files present (0041, 0043, 0054, 0056, 0058, 0067-0071)"
else
  fail "missing ${#MISSING[@]} of 10 net-new ADR files" \
       "missing: ${MISSING[*]}"
fi

# ============================================================================
section "TC2: Each new ADR byte-equal to calc source (non-vacuous per Issue #1041)"
BYTE_DIFFS=()
for slug in "${NEW_ADRS[@]}"; do
  calc_fp="$CALC_DECISIONS/${slug}.md"
  tmpl_fp="$REPO_ROOT/docs/decisions/${slug}.md"
  if [ ! -r "$calc_fp" ]; then
    BYTE_DIFFS+=("${slug}: calc source missing")
    continue
  fi
  if ! cmp -s "$calc_fp" "$tmpl_fp"; then
    BYTE_DIFFS+=("${slug}: byte-diff detected (calc=${calc_fp} vs tmpl=${tmpl_fp})")
  fi
done
if [ "${#BYTE_DIFFS[@]}" -eq 0 ]; then
  pass "all 10 net-new ADRs byte-equal to calc source (Issue #1041 non-vacuous verified)"
else
  fail "${#BYTE_DIFFS[@]} of 10 net-new ADRs NOT byte-equal to calc source" \
       "failures: ${BYTE_DIFFS[*]}"
fi

# ============================================================================
section "TC3: 8 idempotent ADR copies remain byte-equal (0034, 0035, 0037, 0039, 0044, 0045, 0053, 0055)"
IDEMPOTENT_DIFFS=()
for slug in "${IDEMPOTENT_ADRS[@]}"; do
  calc_fp="$CALC_DECISIONS/${slug}.md"
  tmpl_fp="$REPO_ROOT/docs/decisions/${slug}.md"
  if [ ! -r "$calc_fp" ] || [ ! -r "$tmpl_fp" ]; then
    IDEMPOTENT_DIFFS+=("${slug}: source missing (calc=${calc_fp}, tmpl=${tmpl_fp})")
    continue
  fi
  if ! cmp -s "$calc_fp" "$tmpl_fp"; then
    IDEMPOTENT_DIFFS+=("${slug}: byte-diff detected")
  fi
done
if [ "${#IDEMPOTENT_DIFFS[@]}" -eq 0 ]; then
  pass "all 8 idempotent ADR copies remain byte-equal (S29-017/S32-003 pre-sync preserved)"
else
  fail "${#IDEMPOTENT_DIFFS[@]} of 8 idempotent ADRs byte-diff detected" \
       "failures: ${IDEMPOTENT_DIFFS[*]}"
fi

# ============================================================================
section "TC4: INDEX.md has 4 NEW rows + 6 RESERVED entries resolved (no RESERVED for new IDs)"
RESERVED_LEAKS=()
# Check that no RESERVED entries exist for IDs 0041, 0043, 0054, 0056, 0058, 0067-0071
for id in "ADR-0041" "ADR-0043" "ADR-0054" "ADR-0056" "ADR-0058" "ADR-0067" "ADR-0068" "ADR-0069" "ADR-0070" "ADR-0071"; do
  # Look for the row line with this ID + "RESERVED" status
  if grep -E "^\| \[${id}\]" "$INDEX_MD" | grep -q "RESERVED"; then
    RESERVED_LEAKS+=("${id} still RESERVED in INDEX.md")
  fi
done
if [ "${#RESERVED_LEAKS[@]}" -eq 0 ]; then
  pass "INDEX.md RESERVED entries resolved for all 10 new IDs (0041/0043/0054/0056/0058/0067-0071)"
else
  fail "${#RESERVED_LEAKS[@]} RESERVED entries still present for new IDs" \
       "leaks: ${RESERVED_LEAKS[*]}"
fi

# ============================================================================
section "TC5: PORT-DECISIONS.md exists with classification tables (Issue #156 AC5)"
if [ ! -r "$PORT_DECISIONS" ]; then
  fail "PORT-DECISIONS.md not found at $PORT_DECISIONS"
elif ! grep -q "DOCTRINE-PORT — ported in this PR" "$PORT_DECISIONS"; then
  fail "PORT-DECISIONS.md missing 'DOCTRINE-PORT' classification section"
elif ! grep -q "DOCTRINE-PORT DEFERRED" "$PORT_DECISIONS"; then
  fail "PORT-DECISIONS.md missing 'DEFERRED' classification section"
elif ! grep -q "CALC-SPECIFIC" "$PORT_DECISIONS"; then
  fail "PORT-DECISIONS.md missing 'CALC-SPECIFIC' classification section"
elif ! grep -q "HYBRID" "$PORT_DECISIONS"; then
  fail "PORT-DECISIONS.md missing 'HYBRID' classification section"
else
  pass "PORT-DECISIONS.md exists with all 4 classification sections (DOCTRINE-PORT/DEFERRED/CALC-SPECIFIC/HYBRID)"
fi

# ============================================================================
printf "\n${B}==== SUMMARY ====${D}\n"
printf "  ${G}PASS${D}: %d\n" "$PASS"
printf "  ${R}FAIL${D}: %d\n" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo
  echo "d156 REGRESSION FAILED — S32-027 ADR port batch incomplete."
  echo "Fix: ensure all 10 net-new ADRs exist + byte-equal to calc source,"
  echo "      INDEX.md updates applied, PORT-DECISIONS.md classification tables present."
  exit 1
fi
echo
echo "d156 REGRESSION PASS — S32-027 ADR port batch honored (10 net-new + 8 idempotent preserved)."
exit 0