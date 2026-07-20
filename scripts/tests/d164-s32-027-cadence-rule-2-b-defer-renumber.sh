#!/usr/bin/env bash
# d164-s32-027-cadence-rule-2-b-defer-renumber.sh — S32-027 Cadence-Rule-2-B
# DEFERRED ADR renumber/port batch regression test (6 TCs, ADR-0049 sister-pattern
# + Cadence Rule 1 atomic per ADR-0055 §1).
#
# Why this test exists
# --------------------
# Issue #164 (S32-027-cadence-rule-2-B) is the DEFERRED follow-up cluster from the
# PORT-DECISIONS.md §(B) classification table (7 calc ADRs blocked on number-
# collision). This PR resolves them:
#   - calc ADR-0062/0063/0064/0065 → ported into pre-reserved tmpl sister slots
#     0062/0063/0064/0065 (same number, no renumber needed).
#   - calc ADR-0060 (§AC Mapping Verification) → RENUMBERED to tmpl ADR-0061
#     (tmpl 0060 is the distinct Claude-Code agent-flag doctrine — real collision).
#   - calc ADR-0061 (agent-flag dup) → NO PORT (duplicate of tmpl 0060; calc-side
#     deletion tracked by AtilCalculator PR #1178).
#   - calc ADR-0059 → already byte-synced; stale INDEX RESERVED status + broken
#     link (`-lag.md` → `-lag-detection.md`) corrected.
#
# 6 TCs (per ADR-0049 ≥5 TCs invariant + Cadence Rule 1 atomic per ADR-0055 §1):
#   TC1: 5 ported/renumbered ADR files exist in tmpl docs/decisions/
#   TC2: No RESERVED placeholder rows remain in INDEX.md for 0059, 0061-0065
#   TC3: Link integrity — every INDEX link for ADR-0059/0061-0065 resolves to an
#        existing file (guards the calc-PR-#1178 orphan-link defect class)
#   TC4: ADR-0061 renumber integrity — title is "# ADR-0061" (self-ref renumbered)
#        AND tmpl ADR-0060 agent-flag doctrine remains distinct (no collision)
#   TC5: PORT-DECISIONS.md §(B) DEFERRED table — no "**DEFERRED**" remains for the
#        7 rows (all flipped to ✅ RESOLVED)
#   TC6: Cadence Rule 1 atomic — scripts/tests/INDEX.md references this test file
#
# Sister-pattern to:
#   - d156-s32-027-adr-port-batch.sh (S32-027 parent port batch d-test — DIRECT sister)
#   - d983-s28-003-forward-port-parity.sh (forward-port parity)
#   - d1138-template-agent-wake-fix-4b.sh (tmpl ADR port d-test sister)
#
# Run: bash scripts/tests/d164-s32-027-cadence-rule-2-b-defer-renumber.sh
#
# Exit code: 0 = all pass, 1 = at least one fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DECISIONS="$REPO_ROOT/docs/decisions"
INDEX_MD="$DECISIONS/INDEX.md"
PORT_DECISIONS="$DECISIONS/PORT-DECISIONS.md"
TESTS_INDEX="$REPO_ROOT/scripts/tests/INDEX.md"

PASS=0; FAIL=0
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; B=""; D=""
fi
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s${D}\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

# --- pre-flight ---
for f in "$INDEX_MD" "$PORT_DECISIONS" "$TESTS_INDEX"; do
  if [ ! -r "$f" ]; then echo "ERROR: required artifact not found: $f" >&2; exit 127; fi
done

# Ported/renumbered target files (basename, must exist)
PORTED_FILES=(
  "ADR-0061-ac-mapping-verification-doctrine.md"
  "ADR-0062-layer5-label-change-verdict.md"
  "ADR-0063-layer4-cascade-strip-skip.md"
  "ADR-0064-cross-user-env-var.md"
  "ADR-0065-cpython-asyncio-fix.md"
)

section "TC1: 5 ported/renumbered ADR files exist"
tc1_ok=1
for bn in "${PORTED_FILES[@]}"; do
  if [ -f "$DECISIONS/$bn" ]; then
    pass "exists: $bn"
  else
    fail "missing ported ADR file: $bn"; tc1_ok=0
  fi
done

section "TC2: no RESERVED placeholder rows remain for 0059,0061-0065"
tc2_ok=1
for id in 0059 0061 0062 0063 0064 0065; do
  row="$(grep -E "^\| \[ADR-$id\]" "$INDEX_MD" | head -1)"
  if [ -z "$row" ]; then fail "no INDEX row for ADR-$id"; tc2_ok=0; continue; fi
  # Match the canonical placeholder-status MARKERS ("[RESERVED —" title prefix or
  # "Proposed (reserved)" status), NOT any substring — a corrective note may mention
  # the word "RESERVED" while the row is Accepted (avoids false-positive per ADR-0068).
  if grep -qiE '\[RESERVED[[:space:]]*—|Proposed[[:space:]]*\(reserved\)' <<<"$row"; then
    fail "ADR-$id INDEX row still carries a RESERVED-status marker" "$row"; tc2_ok=0
  else
    pass "ADR-$id INDEX row is non-RESERVED"
  fi
done

section "TC3: INDEX link integrity for ADR-0059,0061-0065 (orphan-link guard)"
tc3_ok=1
for id in 0059 0061 0062 0063 0064 0065; do
  # extract the ./ADR-....md link target from the row
  link="$(grep -E "^\| \[ADR-$id\]" "$INDEX_MD" | head -1 | grep -oE '\./ADR-[0-9]{4}[^)]*\.md' | head -1)"
  if [ -z "$link" ]; then fail "ADR-$id: no parseable link in INDEX row"; tc3_ok=0; continue; fi
  target="$DECISIONS/${link#./}"
  if [ -f "$target" ]; then
    pass "ADR-$id link resolves: $link"
  else
    fail "ADR-$id BROKEN link (orphan): $link" "target missing: $target"; tc3_ok=0
  fi
done

section "TC4: ADR-0061 renumber integrity + no ADR-0060 collision"
tc4_ok=1
adr61="$DECISIONS/ADR-0061-ac-mapping-verification-doctrine.md"
if head -1 "$adr61" 2>/dev/null | grep -qE '^# ADR-0061:'; then
  pass "ADR-0061 title line correctly renumbered (# ADR-0061:)"
else
  fail "ADR-0061 title not renumbered (expected '# ADR-0061:')" "$(head -1 "$adr61" 2>/dev/null)"; tc4_ok=0
fi
# tmpl ADR-0060 must remain the distinct agent-flag doctrine (collision-free)
if [ -f "$DECISIONS/ADR-0060-claude-code-2.1.207-agent-flag.md" ]; then
  pass "tmpl ADR-0060 agent-flag doctrine intact (no collision with renumbered 0061)"
else
  fail "tmpl ADR-0060 agent-flag file missing — collision-integrity broken"; tc4_ok=0
fi

section "TC5: PORT-DECISIONS §(B) DEFERRED table fully resolved"
tc5_ok=1
# The 7 DEFERRED rows reference these calc ADR link anchors; none may still say **DEFERRED**
deferred_left="$(grep -cE '\*\*DEFERRED\*\*' "$PORT_DECISIONS" || true)"
if [ "$deferred_left" -eq 0 ]; then
  pass "no **DEFERRED** markers remain in PORT-DECISIONS.md (all ✅ RESOLVED)"
else
  fail "PORT-DECISIONS.md still has $deferred_left **DEFERRED** marker(s)"; tc5_ok=0
fi

section "TC6: Cadence Rule 1 atomic — tests INDEX references this d-test"
tc6_ok=1
if grep -q "d164-s32-027-cadence-rule-2-b-defer-renumber.sh" "$TESTS_INDEX"; then
  pass "scripts/tests/INDEX.md references d164 (Cadence Rule 1 atomic, ADR-0055 §1)"
else
  fail "scripts/tests/INDEX.md missing d164 reference (Cadence Rule 1 atomic violation)"; tc6_ok=0
fi

section "SUMMARY"
printf "  %s%d passed%s, %s%d failed%s\n" "$G" "$PASS" "$D" "$R" "$FAIL" "$D"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
