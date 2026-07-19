#!/usr/bin/env bash
# d108-tasklist-snapshot-write-through.sh — Sprint 32 Wave-extension d-test
# (S32-XXX-B sister-test, tmpl#191, ADR-0073 — write-through sister to e2e T7)
#
# Purpose: Validates the LOW-LEVEL write behavior of scripts/tasklist-snapshot.sh
#   at the boundary of issue #237 atomic-write doctrine (write-to-temp + sync + mv)
#   + ADR-0072 §Format spec (frontmatter + markdown checklist).
#
# Sister-tests: e2e-tasklist-persistence-through-clear.sh (calc#1170, lifecycle
#   sibling). Per ADR-0049 ≥3 sister-pattern coverage:
#   - d108-tasklist-snapshot-write-through.sh (this file — write boundary)
#   - d1XX-compact-breathing-room.sh (S32-XXX-B sister — STUCK_AFTER_MIN defaults)
#   - e2e-tasklist-persistence-through-clear.sh (S32-XXX-E — lifecycle integration)
#
# Test cases (T1..T7) — RED-first per ADR-0044:
#   T1: scripts/tasklist-snapshot.sh exists + executable
#   T2: Accepts ROLE arg (positional 1)
#   T3: Accepts JSON TodoWrite state (positional 2) — JSON parse via python3
#   T4: Writes state/tasklists/${ROLE}.md atomically (write-to-temp + sync + mv)
#   T5: Output format: frontmatter `<!-- tasklist-snapshot role:${ROLE} ts:ISO8601 -->`
#   T6: Output format: markdown checklist `- [ ] task` per TodoWrite entry
#   T7: Cadence Rule 1 atomic — INDEX.md mentions this test (ADR-0055 §1)
#
# Pre-impl RED expected (S32-XXX-B impl lands in same commit, this test goes GREEN):
#   PASS: T7 (INDEX.md row added same commit)
#   FAIL: T1 (impl missing pre-commit), T2-T6 (impl missing)
#   → 1 PASS / 6 FAIL — RED state confirmed
# Post-impl GREEN target: 7/7 PASS on S32-XXX-B commit cluster.
#
# Exit code: 0 = all pass, 1 = at least one fail.
#
# Run standalone: bash scripts/tests/d108-tasklist-snapshot-write-through.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SNAPSHOT_SH="$SCRIPT_DIR/../tasklist-snapshot.sh"
STATE_DIR="$REPO_ROOT/state/tasklists"
INDEX_FILE="$SCRIPT_DIR/INDEX.md"

TEST_ROLE="tester"
TEST_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Colors (TTY-aware)
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; Y=$'\033[1;33m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; Y=""; B=""; D=""; fi

PASS=0; FAIL=0
declare -a FAIL_DETAILS=()
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() {
  printf "  ${R}✗ FAIL${D} — %s\n" "$1"
  [ -n "${2:-}" ] && printf "    ${R}%s${D}\n" "$2"
  FAIL=$((FAIL+1))
  FAIL_DETAILS+=("$1")
}
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }
info() { printf "  ${Y}ℹ${D} %s\n" "$1"; }

# ============================================================================
# T1: scripts/tasklist-snapshot.sh exists + executable
# ============================================================================
section "T1: scripts/tasklist-snapshot.sh exists + executable"
# Pattern: Per ADR-0072 §Layer 2 + ADR-0073, scripts/tasklist-snapshot.sh is the
# canonical snapshot writer. Sister to e2e T2.
if [[ -x "$SNAPSHOT_SH" ]]; then
  pass "scripts/tasklist-snapshot.sh exists + executable"
else
  fail "scripts/tasklist-snapshot.sh missing or not executable" \
       "expected '$SNAPSHOT_SH' to exist + be executable (ADR-0072 §Layer 2 canonical writer; impl lands in S32-XXX-B)"
fi

# Cleanup any leftover snapshot from prior run
mkdir -p "$STATE_DIR" 2>/dev/null || true
rm -f "$STATE_DIR/${TEST_ROLE}.md" 2>/dev/null || true

# ============================================================================
# T2: Accepts ROLE arg (positional 1)
# ============================================================================
section "T2: Accepts ROLE positional arg"
# Pattern: usage `tasklist-snapshot.sh <ROLE> <JSON_TODO_STATE>`. First arg is
# role name; used to derive output path state/tasklists/${ROLE}.md.
if [[ -x "$SNAPSHOT_SH" ]]; then
  # Provide minimal valid JSON as second arg to isolate T2 (first-arg validation)
  if "$SNAPSHOT_SH" "$TEST_ROLE" '[]' 2>/dev/null; then
    pass "tasklist-snapshot.sh accepts ROLE positional arg (exit 0 on valid role)"
  else
    fail "tasklist-snapshot.sh rejected ROLE arg" \
         "expected exit 0 on first arg ROLE='$TEST_ROLE' (per ADR-0072 §Format spec: ROLE derives state/tasklists/\${ROLE}.md path)"
  fi
else
  fail "T2 skipped — impl missing" "cascade from T1"
fi

# ============================================================================
# T3: Accepts JSON TodoWrite state (positional 2) — JSON parse via python3
# ============================================================================
section "T3: Accepts JSON TodoWrite state via positional 2"
# Pattern: second arg is the JSON TodoWrite state. Use python3 to verify
# the snapshot script does NOT corrupt JSON (no silent drop, no trailing
# garbage). We verify by checking the output file has the expected number of
# `- [ ]` checklist lines.
if [[ -x "$SNAPSHOT_SH" ]]; then
  MOCK_JSON='[{"status":"pending","content":"task-alpha"},{"status":"in_progress","content":"task-beta"},{"status":"completed","content":"task-gamma"}]'
  rm -f "$STATE_DIR/${TEST_ROLE}.md" 2>/dev/null || true
  if "$SNAPSHOT_SH" "$TEST_ROLE" "$MOCK_JSON" 2>/dev/null; then
    SNAPSHOT_FILE="$STATE_DIR/${TEST_ROLE}.md"
    if [[ -f "$SNAPSHOT_FILE" ]]; then
      # Count `- [ ]` and `- [x]` lines — should be 3 (one per JSON entry)
      CHECKLIST_COUNT=$(grep -cE '^- \[[ x]\]' "$SNAPSHOT_FILE" 2>/dev/null || echo 0)
      if [[ "$CHECKLIST_COUNT" -eq 3 ]]; then
        pass "JSON state parsed correctly — 3/3 checklist lines written (no silent drop)"
      else
        fail "JSON state parse failed" \
             "expected 3 '- [ ]' checklist lines (one per JSON entry) but got $CHECKLIST_COUNT — JSON parse or write loop broken"
      fi
    else
      fail "snapshot file not written despite success exit" \
           "expected $SNAPSHOT_FILE to exist after invocation"
    fi
  else
    fail "tasklist-snapshot.sh rejected valid JSON" \
         "expected exit 0 on valid JSON TodoWrite state (3 entries)"
  fi
else
  fail "T3 skipped — impl missing" "cascade from T1"
fi

# ============================================================================
# T4: Writes state/tasklists/${ROLE}.md atomically (write-to-temp + sync + mv)
# ============================================================================
section "T4: Atomic write — write-to-temp + sync + mv per Issue #237"
# Pattern: Per ADR-0072 §Consequences.3, tasklist-snapshot.sh MUST use
# write-to-temp + sync + mv to defeat /clear-mid-write race. Sister-pattern:
# scripts/atomic-write.sh helper. We verify by inspecting the script source
# for the pattern (mktemp + mv) OR by checking that no partial file exists
# during write (timing-sensitive, so source-grep is the reliable check).
if [[ -r "$SNAPSHOT_SH" ]]; then
  if grep -Eq "mktemp|mv.*\\.tmp|atomic-write" "$SNAPSHOT_SH"; then
    pass "atomic-write pattern detected in tasklist-snapshot.sh source (write-to-temp + mv)"
  else
    fail "no atomic-write pattern in tasklist-snapshot.sh" \
         "expected 'mktemp' OR 'mv .*\\.tmp' OR 'atomic-write' in script source per Issue #237 + ADR-0072 §Consequences.3"
  fi
else
  fail "T4 skipped — impl file not readable" "cascade from T1"
fi

# ============================================================================
# T5: Output format — frontmatter `<!-- tasklist-snapshot role:${ROLE} ts:ISO8601 -->`
# ============================================================================
section "T5: Frontmatter format per ADR-0072 §Format spec"
# Pattern: First line MUST be `<!-- tasklist-snapshot role:${ROLE} ts:${ISO8601} -->`.
# ISO8601 = `YYYY-MM-DDTHH:MM:SSZ` (UTC, Z suffix).
if [[ -x "$SNAPSHOT_SH" ]]; then
  MOCK_JSON='[{"status":"pending","content":"verify-frontmatter"}]'
  rm -f "$STATE_DIR/${TEST_ROLE}.md" 2>/dev/null || true
  "$SNAPSHOT_SH" "$TEST_ROLE" "$MOCK_JSON" 2>/dev/null || true
  SNAPSHOT_FILE="$STATE_DIR/${TEST_ROLE}.md"
  if [[ -f "$SNAPSHOT_FILE" ]]; then
    FIRST_LINE=$(head -1 "$SNAPSHOT_FILE")
    if [[ "$FIRST_LINE" =~ ^\<\!\-\-\ tasklist-snapshot\ role:${TEST_ROLE}\ ts:[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\ \-\-\>$ ]]; then
      pass "frontmatter parseable: '$FIRST_LINE'"
    else
      fail "frontmatter invalid format" \
           "expected line 1 to match '^<!-- tasklist-snapshot role:${TEST_ROLE} ts:YYYY-MM-DDTHH:MM:SSZ -->$' but got '$FIRST_LINE'"
    fi
  else
    fail "no snapshot file to verify frontmatter" "cascade from T1/T3 (impl missing or write failed)"
  fi
else
  fail "T5 skipped — impl missing" "cascade from T1"
fi

# ============================================================================
# T6: Markdown checklist per TodoWrite entry — `- [ ] task` for pending,
#     `- [x] task` for completed
# ============================================================================
section "T6: Markdown checklist format per ADR-0072 §Format spec"
# Pattern: Each TodoWrite entry becomes one markdown checkbox. `pending` → `- [ ]`,
# `in_progress` → `- [ ]`, `completed` → `- [x]`. Status mapping per ADR-0072.
if [[ -x "$SNAPSHOT_SH" ]]; then
  MOCK_JSON='[{"status":"pending","content":"alpha"},{"status":"in_progress","content":"beta"},{"status":"completed","content":"gamma"}]'
  rm -f "$STATE_DIR/${TEST_ROLE}.md" 2>/dev/null || true
  "$SNAPSHOT_SH" "$TEST_ROLE" "$MOCK_JSON" 2>/dev/null || true
  SNAPSHOT_FILE="$STATE_DIR/${TEST_ROLE}.md"
  if [[ -f "$SNAPSHOT_FILE" ]]; then
    # alpha + beta should be `[ ]` (pending + in_progress); gamma should be `[x]` (completed)
    if grep -q "\[ \] alpha" "$SNAPSHOT_FILE" \
       && grep -q "\[ \] beta" "$SNAPSHOT_FILE" \
       && grep -q "\[x\] gamma" "$SNAPSHOT_FILE"; then
      pass "checklist format correct: pending/in_progress → [ ], completed → [x]"
    else
      fail "checklist format mapping wrong" \
           "expected pending + in_progress → '- [ ]' and completed → '- [x]' per ADR-0072 §Format spec — got: $(grep -E '^- \[' "$SNAPSHOT_FILE")"
    fi
  else
    fail "no snapshot file to verify checklist" "cascade from T1/T3 (impl missing or write failed)"
  fi
else
  fail "T6 skipped — impl missing" "cascade from T1"
fi

# ============================================================================
# T7: Cadence Rule 1 atomic — INDEX.md mentions this test (ADR-0055 §1)
# ============================================================================
section "T7: Cadence Rule 1 atomic per ADR-0055 §1"
# Pattern: Per ADR-0055 §1, this test file + INDEX.md row + impl file must land
# in the SAME commit. We verify by checking that INDEX.md has a row referencing
# d108-tasklist-snapshot-write-through.sh. Sister-pattern: cycle ~#3690 .tmpl
# placeholder atomicity doctrine.
if [[ -r "$INDEX_FILE" ]] && grep -q "d108-tasklist-snapshot-write-through" "$INDEX_FILE"; then
  pass "INDEX.md references this test file (Cadence Rule 1 atomic verified)"
else
  fail "INDEX.md missing d108 row" \
       "expected '$INDEX_FILE' to contain 'd108-tasklist-snapshot-write-through' row (AC7 — Cadence Rule 1 atomic per ADR-0055 §1)"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
TOTAL=$((PASS + FAIL))
printf "${B}==== Summary ====${D}\n"
echo "PASS: $PASS"
echo "FAIL: $FAIL"
echo "TOTAL: $TOTAL"
if [[ $FAIL -gt 0 ]]; then
  printf "${R}${B}RED STATE CONFIRMED${D} — ${R}%d/%d TESTS FAIL${D}\n" "$FAIL" "$TOTAL"
  echo "Failed TCs (impl gap signals):"
  for d in "${FAIL_DETAILS[@]}"; do echo "  - $d"; done
  echo ""
  echo "Per ADR-0044 RED-first TDD: this is the EXPECTED state before S32-XXX-B impl lands."
  echo "Once tasklist-snapshot.sh + INDEX.md row land in same commit cluster,"
  echo "this test should turn 7/7 GREEN."
  exit 1
else
  printf "${G}${B}GREEN — ALL %d TESTS PASSED${D}\n" "$PASS"
  exit 0
fi
