#!/usr/bin/env bash
# d1043-template-agent-watch-flags-parser-fix.sh — sister-template d-test for d1043
#
# Per Issue #107 (sister-pattern mirror of AtilCalculator Issue #1086 + PR #1087,
# d1043), the dev-studio-template's `scripts/agent-watch.sh` carries an
# identical latent crash on the MODE parser at line ~143:
#
#   Bug A: `MODE="${2:---once}"` positional grab captures the flag string when
#          --repo follows <role> directly. Result: "Unknown mode: --repo" at
#          the script's terminal `case "$MODE" in` check, exit 2.
#
# Sister-pattern lineage:
#   d1043 (AtilCalculator, PR #1087 MERGED cba23c5) — DIRECT source-of-truth sister
#   Issue #1086 (calc-side spec origin, MERGED via PR #1087)
#   Issue #107 (sister-side spec, this d-test's home)
#   PR #106 (sister-template org-scan + line-294 length-guard, held-pending-d1043)
#
# Sister-side scope notes (deltas vs calc-side d1043):
# - Bug A (MODE-walker) at line ~143 — IDENTICAL to calc-side, mirrored verbatim.
# - Bug B (REPOS[] length-guard for org-scan `_seen_repos` assoc-array) — N/A in
#   sister-repo main: the org-scan block lands via PR #106 (sister-template
#   d1041+d1042 mirror), which already brings its own line-294 length-guard
#   (`REPO="${REPOS[0]:-}"`). d1043 sister-side therefore focuses on Bug A +
#   regression coverage of the existing REPOS[] empty-check guard
#   (sister-side d1042-style invariant from PR #106 branch).
#
# Test design (static-source checks, no runtime setup deps):
# All 7 TCs are source-shape / file-existence checks. This avoids the
# state-helper setup requirement that runtime invocations need in worktree
# contexts (`/var/log/dev-studio/<basename>/agent-state` must be pre-created).
# Static-source checks are equivalent in regression-guard value (they fail when
# the shape regresses, pass when the fix lands) and avoid env coupling.
#
# Note on line-range robustness: d-test checks the WHOLE file (no line ranges)
# because the MODE-walker insertion shifts subsequent line numbers. Patterns
# are specific enough to avoid false matches.
#
# Test cases (≥5 per ADR-0049; this d-test = 7):
#   TC1: RED — file must NOT contain `MODE="${2:---once}"` positional grab
#        (Bug A regression guard, source-shape)
#   TC2: RED — file MUST contain argv walker pattern `case "$_arg" in`
#        (Bug A fix-shape, source-shape)
#   TC3: GREEN — file MUST contain d1042-style length-guard
#        `if [ "${#REPOS[@]}" -eq 0 ]; then` (sister-side d1042 invariant
#        preserved across d1043 fix)
#   TC4: GREEN — file MUST contain argv parser walker
#        `while [ "$ARG_IDX" -le "$#" ]` (sister-side d1047-style invariant)
#   TC5: GREEN — file MUST contain `--repo=*)` (no-space form)
#        (backward-compat flag-equality syntax regression guard)
#   TC6: GREEN — file MUST contain `--repo)` (positional form)
#        (positional flag syntax regression guard)
#   TC7: RED — `scripts/tests/INDEX.md` MUST contain a `d1043-template-` entry
#        (Cadence Rule 1 atomic per ADR-0055 §1)
#
# Exit code: 0 = all pass, 1 = at least one fail.
#
# TDD status: RED-first verified on dev-studio-template HEAD (1d467cd).
# Pre-fix expected: 4 PASS (TC3/TC4/TC5/TC6) + 3 FAIL (TC1/TC2/TC7).
# Post-fix expected: 7/7 PASS. Sister-side Cadence Rule 1 atomic with impl +
# INDEX.md row per ADR-0055 §1.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH_SH="$SCRIPT_DIR/../agent-watch.sh"
INDEX_MD="$SCRIPT_DIR/INDEX.md"

if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
else
  GREEN=''; RED=''; NC=''
fi

PASS=0; FAIL=0; TESTS=0

record_pass() {
  PASS=$((PASS + 1))
  printf "${GREEN}✅ %s${NC} %s\n" "$1" "$2"
}
record_fail() {
  FAIL=$((FAIL + 1))
  printf "${RED}❌ %s${NC} %s\n  %s\n" "$1" "$2" "$3"
}

[ -f "$WATCH_SH" ] || { echo "ERROR: $WATCH_SH not found" >&2; exit 2; }
[ -f "$INDEX_MD" ] || { echo "ERROR: $INDEX_MD not found" >&2; exit 2; }

# --- TC1: file must NOT contain positional MODE="${2:---once}" grab ---
TESTS=$((TESTS + 1))
if grep -qF 'MODE="${2:---once}"' "$WATCH_SH"; then
  record_fail "TC1" "file must NOT contain positional MODE=\${2:-} grab (Bug A regression guard)" \
    "FAIL: file still uses MODE=\${2:-...} positional grab — Bug A unfixed"
else
  record_pass "TC1" "file does NOT contain positional MODE=\${2:-} grab (Bug A regression guard)"
fi

# --- TC2: file MUST contain argv walker (`case "$_arg" in`) ---
TESTS=$((TESTS + 1))
if grep -qE 'case[[:space:]]+"\$_arg"[[:space:]]+in' "$WATCH_SH"; then
  record_pass "TC2" "file contains argv walker (case \"\$_arg\" in) (Bug A fix-shape)"
else
  record_fail "TC2" "file contains argv walker (case \"\$_arg\" in) (Bug A fix-shape)" \
    "FAIL: no argv walker (case \$_arg in) detected — fix not applied"
fi

# --- TC3: sister-side d1042-style length-guard preserved (anywhere in file) ---
TESTS=$((TESTS + 1))
if grep -qF 'if [ "${#REPOS[@]}" -eq 0 ]' "$WATCH_SH"; then
  record_pass "TC3" "sister-side d1042-style length-guard preserved (d1042 invariant)"
else
  record_fail "TC3" "sister-side d1042-style length-guard preserved (d1042 invariant)" \
    "FAIL: d1042-style length-guard missing — d1043 fix may have regressed sister-side d1042 invariant"
fi

# --- TC4: argv parser walker (`while [ "$ARG_IDX" -le "$#" ]`) present ---
TESTS=$((TESTS + 1))
if grep -qE 'while[[:space:]]+\[\s+"\$ARG_IDX"[[:space:]]+-le[[:space:]]+"\$#"[[:space:]]+\]' "$WATCH_SH"; then
  record_pass "TC4" "argv parser walker present (sister-side d1047 invariant)"
else
  record_fail "TC4" "argv parser walker present (sister-side d1047 invariant)" \
    "FAIL: argv parser walker (while [ \"\$ARG_IDX\" -le \"\$\#\" ]) not found — sister-side d1047 invariant regressed"
fi

# --- TC5: --repo=* (no-space form) handled ---
TESTS=$((TESTS + 1))
if grep -qF -- '--repo=*)' "$WATCH_SH"; then
  record_pass "TC5" "--repo=* (no-space) handled (backward-compat regression guard)"
else
  record_fail "TC5" "--repo=* (no-space) handled (backward-compat regression guard)" \
    "FAIL: --repo=* (no-space) pattern not found — backward-compat regression"
fi

# --- TC6: --repo (positional form) handled ---
TESTS=$((TESTS + 1))
if grep -qE '^[[:space:]]+--repo\)' "$WATCH_SH"; then
  record_pass "TC6" "--repo (positional form) handled (positional flag regression guard)"
else
  record_fail "TC6" "--repo (positional form) handled (positional flag regression guard)" \
    "FAIL: --repo (positional form) pattern not found — positional flag handling regressed"
fi

# --- TC7: INDEX.md must contain a d1043-template- entry (Cadence Rule 1 atomic) ---
TESTS=$((TESTS + 1))
if grep -qE 'd1043-template-' "$INDEX_MD"; then
  record_pass "TC7" "INDEX.md contains d1043-template- entry (Cadence Rule 1 atomic)"
else
  record_fail "TC7" "INDEX.md contains d1043-template- entry (Cadence Rule 1 atomic)" \
    "FAIL: no d1043-template- entry found in INDEX.md — Cadence Rule 1 atomic (ADR-0055 §1) violated"
fi

echo
echo "================================================="
if [ "$FAIL" -eq 0 ]; then
  printf "${GREEN}d1043-template-agent-watch-flags-parser-fix: %d/%d PASS${NC}\n" "$PASS" "$TESTS"
  exit 0
else
  printf "${RED}d1043-template-agent-watch-flags-parser-fix: %d/%d PASS (%d FAIL)${NC}\n" "$PASS" "$TESTS" "$FAIL"
  exit 1
fi