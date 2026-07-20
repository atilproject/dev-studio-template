#!/usr/bin/env bash
# d164-s32-027-b-deferred.sh — S32-027 DEFERRED cluster remaining 5 ADRs regression test
# (5 TCs, ADR-0049 sister-pattern + Cadence Rule 1 atomic per ADR-0055 §1).
#
# Why this test exists
# --------------------
# PR #163 (S32-027 port batch) landed 10 ADRs + resolved 6 RESERVED slots, but
# 5 of the 7 DEFERRED items remained: ADR-0059 (INDEX.md stale), ADR-0062 + ADR-0063
# (amendments, fold-into-parent per ADR-0057 §amendment-via-parent), ADR-0064 +
# ADR-0065 (clean slots, port possible per PORT-DECISIONS.md §B).
#
# PR #1176 (ADR-0060 → ADR-0074 renumber on calc) and PR #1178 (REMOVE calc ADR-0061)
# already landed calc-side AC1+AC2. Issue tmpl#164 AC4 mandates: "File sister-issue
# per ADR renumbering (Cadence Rule 2 chain) OR include in single batch PR per
# ADR-0059 cluster-squash". This d-test verifies the single-batch-PR option: all 5
# remaining DEFERRED ADRs resolved on tmpl side in one go.
#
# 5 TCs (per ADR-0049 ≥5 TCs invariant + Cadence Rule 1 atomic per ADR-0055 §1):
#   TC1: tmpl INDEX.md ADR-0059 row no longer "[RESERVED — Sprint 28]" prefix
#        + status not "Proposed (reserved)"
#   TC2: tmpl ADR-0048 file has "## Amendment" section containing "Layer 5 Label-Change
#        Event Verdict-Gate Extension" phrase (ADR-0062 folded into parent per
#        ADR-0057 amendment-via-parent pattern)
#   TC3: tmpl ADR-0012 file has "Cascade-strip Part 2.5" / "Lane-Transition Skip"
#        section containing ADR-0063 doctrine (folded into parent)
#   TC4: tmpl ADR-0064-cross-user-env-var-pattern.md + ADR-0065-cpython-3-12-13-\
#        asyncio-get-running-loop-fix.md byte-equal to calc source
#   TC5: tmpl INDEX.md removes ADR-0062 + ADR-0063 row entries (since folded); adds
#        ADR-0064 + ADR-0065 row entries pointing at real (non-RESERVED) content
#
# Sister-pattern to:
#   - d156-s32-027-adr-port-batch.sh (PR #163 / Issue #156 port-batch precedent)
#   - d983-s28-003-forward-port-parity.sh
#   - ADR-0057 §amendment-via-parent (HYBRID fold pattern)
#   - ADR-0059 cluster-squash (single-batch-PR AC4 option)
#
# Run: bash scripts/tests/d164-s32-027-b-deferred.sh
#
# Exit code: 0 = all pass, 1 = at least one fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INDEX_MD="$REPO_ROOT/docs/decisions/INDEX.md"
ADR_0048="$REPO_ROOT/docs/decisions/ADR-0048-status-ready-auto-add-gating.md"
ADR_0012="$REPO_ROOT/docs/decisions/ADR-0012-required-label-set.md"
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
if [ ! -r "$ADR_0048" ]; then
  echo "ERROR: ADR-0048 not found at $ADR_0048" >&2
  exit 127
fi
if [ ! -r "$ADR_0012" ]; then
  echo "ERROR: ADR-0012 not found at $ADR_0012" >&2
  exit 127
fi
if [ ! -d "$CALC_DECISIONS" ]; then
  echo "ERROR: calc decisions dir not found at $CALC_DECISIONS" >&2
  exit 127
fi

# ============================================================================
section "TC1: tmpl INDEX.md ADR-0059 row no longer RESERVED prefix + status Accepted/Proposed"
TC1_FAIL=0
# Extract ADR-0059 row (skip the section header that has 'ADR-0059-cluster-...' in it)
INDEX_0059_LINE=$(grep -E "^\| \[ADR-0059\]\(" "$INDEX_MD" | head -1)
if [ -z "$INDEX_0059_LINE" ]; then
  fail "TC1" "no ADR-0059 row found in INDEX.md"
  TC1_FAIL=1
else
  if echo "$INDEX_0059_LINE" | grep -q "RESERVED — Sprint 28"; then
    fail "TC1" "ADR-0059 row still has '[RESERVED — Sprint 28]' prefix"
    TC1_FAIL=1
  fi
  if echo "$INDEX_0059_LINE" | grep -q "Proposed (reserved)"; then
    fail "TC1" "ADR-0059 row status still 'Proposed (reserved)'"
    TC1_FAIL=1
  fi
  if [ "$TC1_FAIL" -eq 0 ]; then
    pass "ADR-0059 INDEX row updated (no RESERVED prefix, non-(reserved) status)"
  fi
fi

# ============================================================================
section "TC2: tmpl ADR-0048 has §Amendment section with ADR-0062 doctrine (Layer 5 Label-Change Verdict-Gate)"
TC2_FAIL=0
if grep -qE "^## Amendment" "$ADR_0048"; then
  pass "ADR-0048 has '## Amendment' section header"
else
  # Could be inside §Decision or §Implementation sub-section; check for the
  # doctrine marker phrase anywhere in the file
  if grep -q "Layer 5 Label-Change Event Verdict-Gate" "$ADR_0048"; then
    pass "ADR-0048 contains ADR-0062 doctrine marker 'Layer 5 Label-Change Event Verdict-Gate'"
  else
    fail "TC2" "ADR-0048 missing '## Amendment' section AND 'Layer 5 Label-Change Event Verdict-Gate' doctrine marker (ADR-0062 fold-into-parent incomplete)"
    TC2_FAIL=1
  fi
fi
if [ "$TC2_FAIL" -eq 0 ]; then
  # Cross-check: the folded amendment MUST reference calc ADR-0062 for traceability
  if grep -qE "ADR-0062" "$ADR_0048"; then
    pass "ADR-0048 references ADR-0062 (calc→tmpl amendment lineage trace per ADR-0057 §amendment-via-parent)"
  else
    fail "TC2-cross-ref" "ADR-0048 missing 'ADR-0062' reference (lineage trace required per ADR-0057 §amendment-via-parent)"
  fi
fi

# ============================================================================
section "TC3: tmpl ADR-0012 has 'Cascade-strip Part 2.5' / 'Lane-Transition Skip' section (ADR-0063 fold)"
TC3_FAIL=0
# Check for the Part 2.5 section OR the doctrine marker
if grep -qE "Cascade-strip Part 2\.5|Cascade-Strip Part 2\.5|Lane-Transition Skip" "$ADR_0012"; then
  pass "ADR-0012 contains ADR-0063 doctrine marker (Part 2.5 / Lane-Transition Skip)"
else
  fail "TC3" "ADR-0012 missing Cascade-strip Part 2.5 / Lane-Transition Skip section (ADR-0063 fold-into-parent incomplete)"
  TC3_FAIL=1
fi
if [ "$TC3_FAIL" -eq 0 ]; then
  if grep -qE "ADR-0063" "$ADR_0012"; then
    pass "ADR-0012 references ADR-0063 (calc→tmpl amendment lineage trace)"
  else
    fail "TC3-cross-ref" "ADR-0012 missing 'ADR-0063' reference (lineage trace required)"
  fi
fi

# ============================================================================
section "TC4: tmpl ADR-0064 + ADR-0065 files byte-equal to calc source"
PORT_ADRS=(
  "ADR-0064-cross-user-env-var-pattern"
  "ADR-0065-cpython-3-12-13-asyncio-get-running-loop-fix"
)
BYTE_DIFFS=()
for slug in "${PORT_ADRS[@]}"; do
  calc_fp="$CALC_DECISIONS/${slug}.md"
  tmpl_fp="$REPO_ROOT/docs/decisions/${slug}.md"
  if [ ! -r "$calc_fp" ]; then
    BYTE_DIFFS+=("${slug}: calc source missing")
    continue
  fi
  if [ ! -r "$tmpl_fp" ]; then
    BYTE_DIFFS+=("${slug}: tmpl file missing (port not done)")
    continue
  fi
  if ! cmp -s "$calc_fp" "$tmpl_fp"; then
    BYTE_DIFFS+=("${slug}: byte-diff detected")
  fi
done
if [ "${#BYTE_DIFFS[@]}" -eq 0 ]; then
  pass "ADR-0064 + ADR-0065 tmpl files byte-equal to calc source"
else
  fail "${#BYTE_DIFFS[@]} of 2 port-file ADRs NOT byte-equal" \
       "failures: ${BYTE_DIFFS[*]}"
fi

# ============================================================================
section "TC5: tmpl INDEX.md removes 0062+0063 rows, adds 0064+0065 real rows"
TC5_FAIL=0
# 0062 row should be REMOVED (since folded into ADR-0048)
if grep -qE "^\| \[ADR-0062\]" "$INDEX_MD"; then
  fail "TC5-0062" "ADR-0062 row still present in INDEX.md (should be removed — folded into ADR-0048)"
  TC5_FAIL=1
else
  pass "ADR-0062 row removed from INDEX.md (folded into ADR-0048)"
fi
# 0063 row should be REMOVED (since folded into ADR-0012)
if grep -qE "^\| \[ADR-0063\]" "$INDEX_MD"; then
  fail "TC5-0063" "ADR-0063 row still present in INDEX.md (should be removed — folded into ADR-0012)"
  TC5_FAIL=1
else
  pass "ADR-0063 row removed from INDEX.md (folded into ADR-0012)"
fi
# 0064 row should be PRESENT and NOT RESERVED
INDEX_0064_LINE=$(grep -E "^\| \[ADR-0064\]\(" "$INDEX_MD" | head -1)
if [ -z "$INDEX_0064_LINE" ]; then
  fail "TC5-0064" "ADR-0064 row missing from INDEX.md (port incomplete)"
  TC5_FAIL=1
elif echo "$INDEX_0064_LINE" | grep -qE "RESERVED"; then
  fail "TC5-0064" "ADR-0064 row still RESERVED in INDEX.md"
  TC5_FAIL=1
else
  pass "ADR-0064 row present in INDEX.md with non-RESERVED status"
fi
# 0065 row should be PRESENT and NOT RESERVED
INDEX_0065_LINE=$(grep -E "^\| \[ADR-0065\]\(" "$INDEX_MD" | head -1)
if [ -z "$INDEX_0065_LINE" ]; then
  fail "TC5-0065" "ADR-0065 row missing from INDEX.md (port incomplete)"
  TC5_FAIL=1
elif echo "$INDEX_0065_LINE" | grep -qE "RESERVED"; then
  fail "TC5-0065" "ADR-0065 row still RESERVED in INDEX.md"
  TC5_FAIL=1
else
  pass "ADR-0065 row present in INDEX.md with non-RESERVED status"
fi

# ============================================================================
printf "\n${B}==== SUMMARY ====${D}\n"
printf "  ${G}PASS${D}: %d\n" "$PASS"
printf "  ${R}FAIL${D}: %d\n" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo
  echo "d164 REGRESSION FAILED — S32-027 DEFERRED cluster remaining 5 ADRs incomplete."
  echo "Fix scope:"
  echo "  - tmpl INDEX.md: ADR-0059 row drop '[RESERVED — Sprint 28]' prefix;"
  echo "    ADR-0062 + ADR-0063 row REMOVE (folded into parents);"
  echo "    ADR-0064 + ADR-0065 row update to non-RESERVED with real slug."
  echo "  - tmpl ADR-0048: add '## Amendment: Layer 5 Label-Change Event Verdict-Gate'"
  echo "    section referencing ADR-0062 (calc→tmpl amendment lineage)."
  echo "  - tmpl ADR-0012: add 'Cascade-strip Part 2.5' / 'Lane-Transition Skip'"
  echo "    section referencing ADR-0063."
  echo "  - tmpl docs/decisions/ADR-0064-cross-user-env-var-pattern.md: copy from calc."
  echo "  - tmpl docs/decisions/ADR-0065-cpython-3-12-13-asyncio-get-running-loop-fix.md: copy from calc."
  exit 1
fi
echo
echo "d164 REGRESSION PASS — S32-027 DEFERRED cluster remaining 5 ADRs honored."
exit 0
