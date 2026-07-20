#!/usr/bin/env bash
# d165-s32-027-d-hybrid.sh — S32-027 HYBRID cluster 10 ADR amendments regression test
# (≥5 TCs per ADR-0049 + Cadence Rule 1 atomic per ADR-0055 §1).
#
# Why this test exists
# --------------------
# Issue #165 (S32-027-cadence-rule-2-D) — 10 HYBRID ADR amendments need fold-into-parent
# on tmpl per ADR-0057 §amendment-via-parent pattern. Calc is source-of-truth per
# Path A v26 (PORT-DECISIONS.md §D table). The 10 amendments span 6 parent ADRs:
#   - ADR-0002 (1 amendment: stale-verdict-filter-scope)
#   - ADR-0024 (2 amendments: auto-verdict-by-hook, stale-verdict-supersede)
#   - ADR-0038 (2 amendments: watcher-enforcement, workstream-awareness)
#   - ADR-0048 (3 amendments: initial-add-defensive-guard, verdict-state-aware, initial-trigger-verdict-state-guard)
#   - ADR-0049 (1 amendment: subcheck-k)
#   - ADR-0057 (1 amendment: closes-vs-refs-intent)
#
# Plus ADR-0007 standalone (NOT in scope for this issue — ported separately).
#
# PR #194 (Issue #164, S32-027-cadence-rule-2-B) folded calc ADR-0062 into tmpl ADR-0048
# as `## Amendment: Layer 5 Label-Change Event Verdict-Gate Extension`. That fold is
# NOT in scope for this test (PR #194 still pending owner-squash, not yet on tmpl main).
# This d-test focuses on the OTHER 10 HYBRID amendments from PORT-DECISIONS.md §D.
#
# 5 TCs (per ADR-0049 ≥5 TCs invariant + Cadence Rule 1 atomic per ADR-0055 §1):
#   TC1: Each of 10 amendments has a unique doctrine marker present in the corresponding
#        tmpl parent ADR §Amendments section (doctrine-presence check)
#   TC2: Each parent tmpl ADR file has an `## Amendment` section header (or equivalent)
#   TC3: Each amendment in parent §Amendments references its calc canonical source (lineage
#        trace per ADR-0057 §amendment-via-parent)
#   TC4: No orphan calc-amendment-named standalone files on tmpl docs/decisions/ (the
#        fold replaces the standalone-file pattern; tmpl-side standalone ADR files that
#        happen to match the calc pattern must not be created in this PR)
#   TC5: INDEX.md entries for the 6 parent ADRs unchanged (fold stays inside parent ADR
#        file; no new INDEX row needed for the amendments themselves)
#
# Sister-pattern to:
#   - d156-s32-027-adr-port-batch.sh (PR #163 / Issue #156 port-batch precedent)
#   - d164-s32-027-b-deferred.sh (PR #194 / Issue #164 DEFERRED fold precedent — direct sister)
#   - d983-s28-003-forward-port-parity.sh
#   - ADR-0057 §amendment-via-parent (HYBRID fold pattern codification)
#   - ADR-0059 cluster-squash (single-batch-PR option)
#
# Run: bash scripts/tests/d165-s32-027-d-hybrid.sh
# Exit code: 0 = all pass, 1 = at least one fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INDEX_MD="$REPO_ROOT/docs/decisions/INDEX.md"
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

# --- pre-flight ---
if [ ! -r "$INDEX_MD" ]; then
  echo "ERROR: INDEX.md not found at $INDEX_MD" >&2
  exit 127
fi
if [ ! -d "$CALC_DECISIONS" ]; then
  echo "ERROR: calc decisions dir not found at $CALC_DECISIONS" >&2
  exit 127
fi

# ============================================================================
# Mapping: amendment file slug → parent tmpl ADR slug → doctrine marker phrase
# ============================================================================
# (parent_slug, calc_amendment_slug, doctrine_marker, marker_description)
AMENDMENTS=(
  "ADR-0002-autonomy-loop|ADR-0002-amendment-1-stale-verdict-filter-scope|stale-verdict filter scope|stale-verdict filter doctrine"
  "ADR-0024-stale-verdict-watchdog-schema|ADR-0024-amendment-auto-verdict-by-hook|auto-verdict-by hook|verdict-by hook auto-issuance"
  "ADR-0024-stale-verdict-watchdog-schema|ADR-0024-amendment-stale-verdict-supersede|stale-verdict-supersede|verdict-by supersede rule"
  "ADR-0038-auto-claim-protocol|ADR-0038-amendment-watcher-enforcement|watcher enforcement|watcher WIP-cap enforcement"
  "ADR-0038-auto-claim-protocol|ADR-0038-amendment-workstream-awareness|workstream awareness|multi-workstream awareness"
  "ADR-0048-status-ready-auto-add-gating|ADR-0048-amendment-initial-add-defensive-guard|defensive guard|Layer 5 defensive guard"
  "ADR-0048-status-ready-auto-add-gating|ADR-0048-amendment-verdict-state-aware|verdict-state aware|Layer 5 verdict-state awareness"
  "ADR-0048-status-ready-auto-add-gating|ADR-0048-amendment-3-initial-trigger-verdict-state-guard|initial-trigger verdict-state guard|initial trigger verdict-state guard"
  "ADR-0049-behavioral-workflow-test-framework|ADR-0049-amendment-subcheck-k|subcheck k|d-test subcheck k framework extension"
  "ADR-0057-closes-anchor-guard|ADR-0057-amendment-closes-vs-refs-intent|closes-vs-refs intent|Closes vs Refs intent classification"
)

# ============================================================================
section "TC1: Each of 10 amendments has doctrine marker present in tmpl parent §Amendments"
TC1_FAIL=0
while IFS='|' read -r parent_slug calc_amend_slug marker desc; do
  parent_fp="$REPO_ROOT/docs/decisions/${parent_slug}.md"
  if [ ! -r "$parent_fp" ]; then
    fail "TC1 ${calc_amend_slug}" "parent ADR file not found: $parent_fp"
    TC1_FAIL=1
    continue
  fi
  # Doctrine marker must appear in the parent ADR (anywhere — typically in §Amendment section)
  if grep -qiE "$marker" "$parent_fp"; then
    pass "${calc_amend_slug} → ${desc} (marker: '${marker}' found in ${parent_slug})"
  else
    fail "TC1 ${calc_amend_slug}" "marker '${marker}' NOT found in ${parent_slug}.md — fold-into-parent incomplete"
    TC1_FAIL=1
  fi
done < <(printf '%s\n' "${AMENDMENTS[@]}")
if [ "$TC1_FAIL" -eq 0 ]; then
  pass "All 10 amendments have doctrine markers present in respective tmpl parent ADRs"
fi

# ============================================================================
section "TC2: Each parent tmpl ADR has '## Amendment' section header"
TC2_FAIL=0
PARENTS=(
  "ADR-0002-autonomy-loop"
  "ADR-0024-stale-verdict-watchdog-schema"
  "ADR-0038-auto-claim-protocol"
  "ADR-0048-status-ready-auto-add-gating"
  "ADR-0049-behavioral-workflow-test-framework"
  "ADR-0057-closes-anchor-guard"
)
for parent_slug in "${PARENTS[@]}"; do
  parent_fp="$REPO_ROOT/docs/decisions/${parent_slug}.md"
  if [ ! -r "$parent_fp" ]; then
    fail "TC2 ${parent_slug}" "parent ADR file missing"
    TC2_FAIL=1
    continue
  fi
  if grep -qE "^## Amendment" "$parent_fp"; then
    pass "${parent_slug} has '## Amendment' section header"
  else
    fail "TC2 ${parent_slug}" "no '## Amendment' section header in ${parent_slug}.md — fold target missing"
    TC2_FAIL=1
  fi
done
if [ "$TC2_FAIL" -eq 0 ]; then
  pass "All 6 parent ADRs have ## Amendment section headers"
fi

# ============================================================================
section "TC3: Each parent §Amendment references its calc canonical amendment source (ADR-0057 §amendment-via-parent lineage trace)"
TC3_FAIL=0
while IFS='|' read -r parent_slug calc_amend_slug marker desc; do
  parent_fp="$REPO_ROOT/docs/decisions/${parent_slug}.md"
  if [ ! -r "$parent_fp" ]; then
    fail "TC3 ${calc_amend_slug}" "parent ADR file missing"
    TC3_FAIL=1
    continue
  fi
  # Cross-link requirement: parent ADR must mention the calc amendment slug (lineage trace)
  # Extract the slug stem (without .md) — the slug should appear as a reference like "ADR-NNNN-amendment-..."
  # We check for the calc_amend_slug stem (which is unique per amendment)
  if grep -qE "$calc_amend_slug" "$parent_fp"; then
    pass "${calc_amend_slug} lineage trace referenced in ${parent_slug}"
  else
    fail "TC3 ${calc_amend_slug}" "calc amendment slug '${calc_amend_slug}' NOT referenced in ${parent_slug}.md (lineage trace required per ADR-0057 §amendment-via-parent)"
    TC3_FAIL=1
  fi
done < <(printf '%s\n' "${AMENDMENTS[@]}")
if [ "$TC3_FAIL" -eq 0 ]; then
  pass "All 10 amendments have lineage trace cross-link to calc canonical source"
fi

# ============================================================================
section "TC4: No orphan calc-amendment-style standalone files on tmpl docs/decisions/ (folds done — not copies)"
# This PR should NOT create standalone tmpl ADR files matching the calc amendment
# pattern (ADR-NNNN-amendment-*.md). The fold-into-parent pattern REPLACES the
# standalone-file pattern. Tmpl may have its own amendment files for OTHER amendments
# (not in this PR's scope) — we only check that none of the 10 calc amendment files
# have been ported as-is to tmpl.
TC4_FAIL=0
while IFS='|' read -r parent_slug calc_amend_slug marker desc; do
  tmpl_amend_fp="$REPO_ROOT/docs/decisions/${calc_amend_slug}.md"
  if [ -r "$tmpl_amend_fp" ]; then
    fail "TC4 ${calc_amend_slug}" "tmpl has standalone amendment file (should be folded into parent, NOT copied): $tmpl_amend_fp"
    TC4_FAIL=1
  else
    pass "${calc_amend_slug} NOT present as standalone tmpl file (fold-into-parent honored)"
  fi
done < <(printf '%s\n' "${AMENDMENTS[@]}")
if [ "$TC4_FAIL" -eq 0 ]; then
  pass "All 10 amendments folded (no orphan calc-amendment-style standalone files on tmpl)"
fi

# ============================================================================
section "TC5: INDEX.md entries for the 6 parent ADRs unchanged (no new INDEX rows for amendments)"
# The 6 parent ADRs already have INDEX rows. The amendments fold INTO the parent ADR
# file's §Amendment section, NOT into INDEX.md. No new INDEX row should be added for
# each of the 10 amendments — that would be the standalone-file pattern.
TC5_FAIL=0
for parent_slug in "${PARENTS[@]}"; do
  if grep -qE "^\| \[${parent_slug%-*}\]\(" "$INDEX_MD"; then
    pass "INDEX.md row exists for parent ADR family of ${parent_slug}"
  else
    # Some parents may use the base ADR-NNNN form in INDEX
    base_num=$(echo "$parent_slug" | grep -oE "ADR-[0-9]+" | head -1)
    if grep -qE "^\| \[${base_num}\]\(" "$INDEX_MD"; then
      pass "INDEX.md row exists for ${base_num} (parent ADR family of ${parent_slug})"
    else
      fail "TC5 ${parent_slug}" "no INDEX.md row for parent ADR family"
      TC5_FAIL=1
    fi
  fi
done
# Also: confirm no orphan INDEX rows for the 10 amendment slugs
while IFS='|' read -r parent_slug calc_amend_slug marker desc; do
  if grep -qE "^\| \[${calc_amend_slug%-*}\]\(" "$INDEX_MD"; then
    base_num=$(echo "$calc_amend_slug" | grep -oE "ADR-[0-9]+" | head -1)
    if grep -qE "^\| \[${base_num}-amendment" "$INDEX_MD"; then
      fail "TC5 INDEX ${calc_amend_slug}" "INDEX.md has row for amendment slug '${calc_amend_slug}' — should NOT have standalone amendment row (fold-into-parent)"
      TC5_FAIL=1
    fi
  fi
done < <(printf '%s\n' "${AMENDMENTS[@]}")
if [ "$TC5_FAIL" -eq 0 ]; then
  pass "All 6 parent ADR INDEX rows preserved; no orphan amendment INDEX rows added"
fi

# ============================================================================
printf "\n${B}==== SUMMARY ====${D}\n"
printf "  ${G}PASS${D}: %d\n" "$PASS"
printf "  ${R}FAIL${D}: %d\n" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo
  echo "d165 REGRESSION FAILED — S32-027 HYBRID cluster 10 ADR amendments not folded into parents."
  echo "Fix scope:"
  echo "  - tmpl ADR-0002-autonomy-loop.md: add ## Amendment section with stale-verdict-filter-scope doctrine"
  echo "  - tmpl ADR-0024-stale-verdict-watchdog-schema.md: add ## Amendment section with auto-verdict-by-hook + stale-verdict-supersede doctrines"
  echo "  - tmpl ADR-0038-auto-claim-protocol.md: add ## Amendment section with watcher-enforcement + workstream-awareness doctrines"
  echo "  - tmpl ADR-0048-status-ready-auto-add-gating.md: add ## Amendment section with initial-add-defensive-guard + verdict-state-aware + initial-trigger-verdict-state-guard doctrines"
  echo "  - tmpl ADR-0049-behavioral-workflow-test-framework.md: add ## Amendment section with subcheck-k doctrine"
  echo "  - tmpl ADR-0057-closes-anchor-guard.md: add ## Amendment section with closes-vs-refs-intent doctrine"
  echo "  - Each ## Amendment section MUST reference its calc canonical source (lineage trace per ADR-0057)"
  echo "  - Each ## Amendment section MUST include the doctrine marker phrase from the calc source"
  echo "  - Do NOT create standalone tmpl ADR files matching the calc amendment pattern (folds, not copies)"
  echo "  - Do NOT add new INDEX.md rows for the amendments (stays inside parent ADR)"
  exit 1
fi
echo
echo "d165 REGRESSION PASS — S32-027 HYBRID cluster 10 ADR amendments folded into parents per ADR-0057."
exit 0