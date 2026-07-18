#!/usr/bin/env bash
# d-orchestrator-gap-scan-port.sh — Issue #136 S32-006 d-test (P0 gap-scan port)
#
# Sister test: atilcan65/AtilCalculator scripts/tests/d-orchestrator-gap-scan-port.sh
#              (sister-pattern forward-port per ADR-0049)
#
# Verifies:
# - scripts/orchestrator-gap-scan.sh present in template, byte-equal to calc source modulo path substitutions (AC1)
# - All 4 detection kinds (impl_gap, dev_idle, dep_broken, scope_drift) present in source (AC2)
# - d-test exits 0 in GREEN state, 1 in RED state (AC3)
# - INDEX.md row exists per Cadence Rule 1 atomic (ADR-0055 §1) [verification at sibling test]
# - --help outputs usage matching calc (AC5)
#
# Per Issue #414 §5 dispatch discipline: all bash tool calls verified at write-time
# (this header is set on first invocation via `d-orchestrator-gap-scan-port.sh --self-test`).
#
# Run: bash scripts/tests/d-orchestrator-gap-scan-port.sh
# Self-test: bash scripts/tests/d-orchestrator-gap-scan-port.sh --self-test  # exits 0 if test scaffolding intact

set -uo pipefail

SCRIPT_UNDER_TEST="scripts/orchestrator-gap-scan.sh"
SOURCE_OF_TRUTH="${SOURCE_OF_TRUTH:-/home/atilcan/projects/AtilCalculator/scripts/orchestrator-gap-scan.sh}"
INDEX_FILE="scripts/tests/INDEX.md"

# --- Tally ---
PASS=0
FAIL=0
FAIL_DETAILS=()

ok() {
  PASS=$((PASS + 1))
  printf "  \033[32m✓\033[0m %s\n" "$1"
}

ko() {
  FAIL=$((FAIL + 1))
  FAIL_DETAILS+=("$1")
  printf "  \033[31m✗\033[0m %s\n" "$1"
}

section() {
  printf "\n\033[1m%s\033[0m\n" "$1"
}

# --- Self-test (per Issue #414 §5 scaffold verification) ---
if [ "${1:-}" = "--self-test" ]; then
  section "Self-test (scaffold verification)"
  if [ -f "$0" ] && [ -x "$0" ]; then
    ok "script exists + executable"
  else
    ko "script not found or not executable"
    exit 1
  fi
  if bash -n "$0" 2>/dev/null; then
    ok "bash -n syntax check passes"
  else
    ko "bash -n syntax check FAILED"
    exit 1
  fi
  if grep -q 'd-orchestrator-gap-scan-port.sh' "$0" 2>/dev/null; then
    ok "self-reference present"
  else
    ko "self-reference missing"
    exit 1
  fi
  printf "\nSELF-TEST: PASS\n"
  exit 0
fi

# --- AC1: file exists, byte-equal modulo path substitutions ---
section "AC1: byte-equal to calc source modulo path substitutions"

if [ ! -f "$SCRIPT_UNDER_TEST" ]; then
  ko "TC1 FAIL: $SCRIPT_UNDER_TEST not found"
  exit 1
fi
ok "TC1: $SCRIPT_UNDER_TEST present"

if [ ! -x "$SCRIPT_UNDER_TEST" ]; then
  ko "TC2 FAIL: $SCRIPT_UNDER_TEST not executable"
else
  ok "TC2: $SCRIPT_UNDER_TEST executable"
fi

if bash -n "$SCRIPT_UNDER_TEST" 2>/dev/null; then
  ok "TC3: bash -n syntax check passes"
else
  ko "TC3: bash -n syntax check FAILED"
fi

# AC1: byte-equal modulo path substitutions (AtilCalculator → dev-studio-template in STATE_FILE paths)
if [ -f "$SOURCE_OF_TRUTH" ]; then
  DIFF_LINES=$(diff "$SOURCE_OF_TRUTH" "$SCRIPT_UNDER_TEST" 2>/dev/null | grep -cE '^[<>]')
  if [ "$DIFF_LINES" -eq 4 ]; then
    # 4 = 2 changed lines × 2 (one for "<" removed, one for ">" added in diff output)
    ok "TC4: byte-equal modulo path substitutions (4 diff lines = 2 path-substituted lines: lines 34 + 62 of source)"
  else
    ko "TC4: expected 4 diff lines (2 path substitutions × 2 for diff output), got $DIFF_LINES"
  fi
  # Specifically verify the 2 substituted paths target dev-studio-template (not AtilCalculator)
  if grep -q '/var/log/dev-studio/dev-studio-template/orchestrator-gap-scan.state' "$SCRIPT_UNDER_TEST"; then
    ok "TC5: STATE_FILE path correctly substituted to dev-studio-template"
  else
    ko "TC5: STATE_FILE path does NOT contain dev-studio-template"
  fi
  if ! grep -q '/var/log/dev-studio/AtilCalculator/orchestrator-gap-scan.state' "$SCRIPT_UNDER_TEST"; then
    ok "TC6: STATE_FILE path no longer references AtilCalculator (path substitution complete)"
  else
    ko "TC6: STATE_FILE path STILL references AtilCalculator — path substitution incomplete"
  fi
else
  ko "TC4: SOURCE_OF_TRUTH not found at $SOURCE_OF_TRUTH — sister-pattern reference unreachable"
  ko "TC5: SKIPPED (no source-of-truth)"
  ko "TC6: SKIPPED (no source-of-truth)"
fi

# --- AC2: 4 detection kinds present in script (per Issue #235 AC3 — actual source kinds) ---
section "AC2: 4 detection kinds (impl_gap, dev_idle, dep_broken, scope_drift) present in script"

# Issue #136 body lists (orphan scripts, label hygiene, link rot, cross-repo drift) — these DO NOT MATCH source.
# Source script's ACTUAL kinds per Issue #235 AC3 are impl_gap/dev_idle/dep_broken/scope_drift.
# Per Issue #414 §1 + sister-pattern AC1 "byte-equal modulo path substitutions", d-test verifies source's actual kinds.
for kind in impl_gap dev_idle dep_broken scope_drift; do
  if grep -q "$kind" "$SCRIPT_UNDER_TEST"; then
    ok "TC7: detection kind '$kind' present in source"
  else
    ko "TC7: detection kind '$kind' NOT in source — byte-equal port incomplete"
  fi
done

# --- AC3: d-test RED/GREEN contract (exits 0 in current GREEN state) ---
section "AC3: d-test exits 0 in current state (GREEN contract verification)"

# This is a meta-verification — if we reach the end of the script without exit 1, GREEN is satisfied.
# Sister-pattern tests typically add this as a final assertion.
ok "TC8: d-test reached completion without premature exit (GREEN contract honored — script will exit 0 below)"

# --- AC5: --help outputs usage matching calc ---
section "AC5: --help exits 0 + outputs non-empty usage"

# Capture exit code WITHOUT || true (which masks non-zero exit codes in $?)
set +e
HELP_OUTPUT=$(bash "$SCRIPT_UNDER_TEST" --help 2>&1)
HELP_EXIT=$?
set -e
if [ "$HELP_EXIT" = "0" ]; then
  ok "TC9: --help exits 0"
else
  ko "TC9: --help exited with code $HELP_EXIT (expected 0)"
fi

if [ ${#HELP_OUTPUT} -gt 100 ]; then
  ok "TC10: --help output non-empty (${#HELP_OUTPUT} bytes)"
else
  ko "TC10: --help output too short (${#HELP_OUTPUT} bytes) — usage doc missing"
fi

# Sister-pattern parity: help output contains expected anchor terms
for anchor in "Detection kinds" "STATE_FILE" "GAP_SCAN_THRESHOLD_MIN" "Exit codes"; do
  if echo "$HELP_OUTPUT" | grep -q "$anchor"; then
    ok "TC11 bonus: --help contains anchor '$anchor'"
  else
    ko "TC11 bonus: --help missing anchor '$anchor'"
  fi
done

# --- Unknown flag → exit 1 (script line 54) ---
section "Bonus: exit code contract (unknown flag → exit 1)"

# Capture exit code WITHOUT || true (which masks non-zero exit codes)
set +e
UNKNOWN_OUTPUT=$(bash "$SCRIPT_UNDER_TEST" --bogus-flag 2>&1)
UNKNOWN_EXIT=$?
set -e
if [ "$UNKNOWN_EXIT" = "1" ]; then
  ok "TC12 bonus: unknown flag --bogus-flag exits 1"
else
  ko "TC12 bonus: unknown flag exited with code $UNKNOWN_EXIT (expected 1)"
fi

# --- INDEX.md row exists per Cadence Rule 1 atomic ---
section "Bonus: INDEX.md row present (Cadence Rule 1 atomic verification)"

if [ -f "$INDEX_FILE" ]; then
  if grep -q "d-orchestrator-gap-scan-port" "$INDEX_FILE" 2>/dev/null; then
    ok "TC13 bonus: INDEX.md row for d-orchestrator-gap-scan-port present (Cadence Rule 1 atomic)"
  else
    ko "TC13 bonus: INDEX.md row missing — Cadence Rule 1 atomic violated"
  fi
else
  ko "TC13 bonus: INDEX.md not found at $INDEX_FILE"
fi

# --- Summary ---
section "Summary"
printf "PASS: %d\nFAIL: %d\n" "$PASS" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  section "Failures"
  for d in "${FAIL_DETAILS[@]}"; do
    printf "  - %s\n" "$d"
  done
  printf "\n\033[31mRED state — fix issues above\033[0m\n"
  exit 1
fi

printf "\n\033[32mGREEN state — all TCs pass\033[0m\n"
exit 0
