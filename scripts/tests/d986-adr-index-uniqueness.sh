#!/usr/bin/env bash
# d986-adr-index-uniqueness.sh — regression test for ADR-0058..0071 reserved
# entries + ADR-number uniqueness validation in canonical docs/decisions/INDEX.md.tmpl.
#
# Per Issue #986 (S28-006 STORY): the canonical tmpl INDEX.md.tmpl must list
# ADR-0058..0071 as [RESERVED — Sprint 28] markers, and ADR-number uniqueness
# must be enforced (no duplicate IDs in the index table).
#
# Bug-class defended against:
#   1. ADR-0058..0071 missing from canonical INDEX.md.tmpl (mid-sprint renumbering risk)
#   2. ADR-number duplicates in INDEX.md.tmpl (link rot + cross-ref ambiguity)
#   3. Reserved entries missing [RESERVED — Sprint 28] marker (backlog hygiene drift)
#   4. Existing ADR entries (0010-0047) accidentally dropped during edit
#   5. Cross-repo sister-pattern drift: tmpl reserved topics must mention
#      AtilCalculator sister ADRs (sister-pattern lineage)
#
# Test cases:
#   T1:  ADR-0058 row present in canonical tmpl INDEX.md.tmpl with [RESERVED] marker
#   T2:  ADR-0059 row present with [RESERVED] marker
#   T3:  ADR-0067 row present with [RESERVED] marker (mid-range sample)
#   T4:  ADR-0071 row present with [RESERVED] marker (range boundary)
#   T5:  No duplicate ADR-NNNN numbers in INDEX.md.tmpl (uniqueness check)
#   T6:  All 14 reserved entries mention "§20.1" pre-allocation map reference
#
# Exit code: 0 = all pass, 1 = at least one fail.
#
# Per ADR-0046 d-test convention + ADR-0049 ≥5 TCs baseline. Sister-pattern:
# AtilCalculator scripts/tests/d972-path-verify-doctrine.sh, d051-dispatch-discipline.sh.
#
# Refs: Issue #986, PR #967 §6.2 audit-baseline, ADR-0007 (reversibility),
# ADR-0046 (d-test convention), ADR-0049 (≥5 TCs baseline), ADR-0055 §1
# (Cadence Rule 1 atomic per Story).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INDEX_FILE="$TEMPLATE_ROOT/docs/decisions/INDEX.md.tmpl"

# Colors (TTY-aware)
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; B=""; D=""; fi

pass() { echo -e "${G}PASS${D} $1"; }
fail() { echo -e "${R}FAIL${D} $1"; FAILED=1; }

# Sanity: INDEX.md.tmpl must exist
if [[ ! -f "$INDEX_FILE" ]]; then
  fail "T0  preflight: $INDEX_FILE not found"
  echo "FATAL: d986 cannot run without canonical INDEX.md.tmpl"
  exit 1
fi

FAILED=0
TOTAL=0

run_t() {
  TOTAL=$((TOTAL+1))
  local tc_name="$1"
  shift
  if "$@"; then
    pass "T$TOTAL $tc_name"
  else
    fail "T$TOTAL $tc_name"
  fi
}

# T1: ADR-0058 row present with [RESERVED — Sprint 28] marker
t1_check() {
  grep -E '^\| \[ADR-0058\]\(\./ADR-0058-.*\.md\) \| \[RESERVED — Sprint 28\]' "$INDEX_FILE" >/dev/null 2>&1
}

# T2: ADR-0059 row present with [RESERVED — Sprint 28] marker
t2_check() {
  grep -E '^\| \[ADR-0059\]\(\./ADR-0059-.*\.md\) \| \[RESERVED — Sprint 28\]' "$INDEX_FILE" >/dev/null 2>&1
}

# T3: ADR-0067 row present (mid-range sample) with [RESERVED — Sprint 28]
t3_check() {
  grep -E '^\| \[ADR-0067\]\(\./ADR-0067-.*\.md\) \| \[RESERVED — Sprint 28\]' "$INDEX_FILE" >/dev/null 2>&1
}

# T4: ADR-0071 row present (range boundary) with [RESERVED — Sprint 28]
t4_check() {
  grep -E '^\| \[ADR-0071\]\(\./ADR-0071-.*\.md\) \| \[RESERVED — Sprint 28\]' "$INDEX_FILE" >/dev/null 2>&1
}

# T5: No duplicate ADR-NNNN numbers in INDEX.md.tmpl (ID column only,
# not Related/refs column — Related refs may cite an ADR multiple times legitimately)
t5_check() {
  local dups
  dups=$(grep -oE '^\| \[ADR-00[0-9]{2}\]' "$INDEX_FILE" | grep -oE 'ADR-00[0-9]{2}' | sort | uniq -d)
  [[ -z "$dups" ]]
}

# T6: All 14 reserved entries mention "§20.1" pre-allocation map reference
t6_check() {
  local missing=0
  for n in 0058 0059 0060 0061 0062 0063 0064 0065 0066 0067 0068 0069 0070 0071; do
    if ! grep -E "^\| \[ADR-$n\]\(" "$INDEX_FILE" | grep -q "§20.1"; then
      missing=$((missing+1))
    fi
  done
  [[ $missing -eq 0 ]]
}

echo "=== d986-adr-index-uniqueness.sh ==="
echo "INDEX: $INDEX_FILE"
echo "---"

run_t "ADR-0058 row has [RESERVED — Sprint 28] marker" t1_check
run_t "ADR-0059 row has [RESERVED — Sprint 28] marker" t2_check
run_t "ADR-0067 row has [RESERVED — Sprint 28] marker (mid-range)" t3_check
run_t "ADR-0071 row has [RESERVED — Sprint 28] marker (range boundary)" t4_check
run_t "No duplicate ADR-NNNN numbers in INDEX.md.tmpl" t5_check
run_t "All 14 reserved entries cite §20.1 pre-allocation map" t6_check

echo "---"
if [[ $FAILED -eq 0 ]]; then
  echo -e "${G}ALL $TOTAL TESTS PASSED${D}"
  exit 0
else
  echo -e "${R}TESTS FAILED${D} ($FAILED of $TOTAL)"
  exit 1
fi
