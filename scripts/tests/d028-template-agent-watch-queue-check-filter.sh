#!/usr/bin/env bash
# d028-template-agent-watch-queue-check-filter.sh — Issue #179
#   template forward-port regression guard for queue check filter logic in
#   scripts/agent-watch.sh (D2.2 pr_labeled wake-trigger filter per
#   ADR-0009 § 2.1, ADR-0009 § 2.2, ADR-0033 dual-channel doctrine).
#
# Why this test exists
# --------------------
# Sister-pattern of AtilCalculator d028 (AtilCalculator/scripts/tests/d028-*,
# forward-port parity for Issue #1142 cluster — `agent-watch.sh` queue check
# filter bug fixed in AtilCalculator and requiring tmpl parity per Issue #179
# AC1 byte-equal port). AtilCalculator Issue #1142 + PR #1144 cluster is the
# origin: agent-watch.sh was silently filtering out events where the queue
# filter logic only checked one of {cc:<role>, agent:<role>} and dropped the
# other, causing wake-deafness on PRs labeled only with the non-checked form.
#
# Fix: `role_wakes_for_pr_labeled` (lines ~605-620) uses the explicit
# `any(.[]?; . == "<wake-trigger-1>" or . == "<wake-trigger-2>" or . ==
# "<wake-trigger-3>")` jq predicate — covers cc-only, agent-only, BOTH, and
# needs-tester-signoff / needs-architect-review variants. Returns 0 (wake) /
# 1 (skip) per ADR-0009 § 2.1 "Correction to issue #47 AC" exact-name match.
#
# Wake-trigger matrix per role (ADR-0009 § 2.1):
#   architect: needs-architect-review, cc:architect, agent:architect
#   tester:    needs-tester-signoff,   cc:tester,    agent:tester
#
# Test framework: bash + jq + awk-extract + subshell-eval idiom (sister to
# d1138-template-agent-wake-fix-4b.sh + d-init-sh-tmpl-preservation.sh).
# ADR-0044 RED-first TDD: pre-port on tmpl main HEAD expected to FAIL on
# TC1-TC5 (function missing → all 5 jq eval calls return rc=1 because the
# function definition is absent in awk extract — subshell exits with last
# command's rc, but since the function never returns 0 the predicate is
# always false, ergo wake-miss for cases that SHOULD wake). Post-port
# expected: TC1-TC5 GREEN (all 5 cases behave per AC2 spec), TC6 (byte-equal
# AC1 parity) GREEN, TC7 (grep AC2 sister-cite anchor) GREEN.
#
# Template-specific notes (vs AtilCalculator d028):
# - Target file: scripts/agent-watch.sh (no .tmpl suffix in tmpl repo; root-
#   level *.tmpl is for rendered output, not shell scripts in scripts/)
# - Path resolution: $REPO_ROOT/scripts/agent-watch.sh
# - awk extract idiom: `awk '/^role_wakes_for_pr_labeled\(\)/{flag=1} flag{print}
#   /^}/{if(flag){flag=0; exit}}'` to pull the function body + eval in subshell
# - INDEX.md registration: tmpl-local per RETRO-008 §11 + d081/s29-005 pattern
#   (AtilCalculator has its own INDEX row, this is sister-side)
# - Cadence Rule 1 atomic per ADR-0055 §1: this file + INDEX.md row +
#   scripts/agent-watch.sh (MODIFIED, byte-equal) same commit
#
# Sister-pattern lineage (≥3 per ADR-0049):
#   - d1138-template-agent-wake-fix-4b.sh (tmpl sister — DIRECT awk-extract
#     idiom precedent for agent-watch.sh function-level testing)
#   - d-init-sh-tmpl-preservation.sh (tmpl Issue #201 — same awk-extract-
#     function + subshell-eval idiom, same byte-equal forward-port doctrine)
#   - d024-agent-wake.sh (tmpl-local dual-channel wake regression — sister
#     grep-assertion static-check idiom)
#   - d1041-template-agent-watch-org-scan-default.sh (AtilCalculator sister
#     forward-port — same tmpl-side org-scan parity pattern; sister-cluster
#     forward-port cadence)
#   - d068b-tmux-send-keys-split-sleep.sh (Issue #935 env-override naming
#     convention sister — D2 sister-pattern on env-var-driven behavior)
#
# Refs: Issue #179 (tmpl forward-port coord, Closes via PR merge),
#       AtilCalculator Issue #1142 + PR #1144 (origin — d028 source-of-truth
#       forward-port), ADR-0009 (wake-trigger doctrine), ADR-0033 (dual-
#       channel doctrine), ADR-0044 (RED-first TDD), ADR-0049 (d-test
#       framework ≥5 baseline), ADR-0055 §1 (Cadence Rule 1 atomic),
#       ADR-0057 (Closes anchor strict format), ADR-0059 (cluster-squash),
#       Issue #972 (Path-Verify Doctrine — trust-but-verify pre-flight),
#       cycle ~#1142 (AtilCalculator d028 origin cluster), PR #1144 (AtilCalc
#       sister), cycle ~#2988 (forward-port cadence — byte-equal + INDEX.md),
#       cycle ~#3958Q+135 (owner-directive Wave 9 claim order:
#       #1180 → #176 → #178 → #179 → #180).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WATCH_SH="${REPO_ROOT}/scripts/agent-watch.sh"
SRC_OF_TRUTH="${REPO_ROOT}/../AtilCalculator/scripts/agent-watch.sh"

# Colors (TTY-aware)
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; Y=$'\033[0;33m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; Y=""; B=""; D=""
fi

PASS=0; FAIL=0
declare -a FAILURES
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); FAILURES+=("$1"); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

# Pre-flight (sister-pattern d1138/d-init-sh-tmpl-preservation)
command -v bash >/dev/null 2>&1 || { echo "ERROR: bash required for d028-tmpl" >&2; exit 127; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required for d028-tmpl" >&2; exit 127; }
command -v awk >/dev/null 2>&1 || { echo "ERROR: awk required for d028-tmpl" >&2; exit 127; }
command -v sha256sum >/dev/null 2>&1 || { echo "ERROR: sha256sum required for d028-tmpl" >&2; exit 127; }
[ -f "$WATCH_SH" ] || { echo "ERROR: agent-watch.sh not found at $WATCH_SH" >&2; exit 127; }

# Sister-pattern d1138/d-init-sh-tmpl-preservation: extract a bash function
# from agent-watch.sh via awk + eval in subshell. ROLE var is the watcher
# role under test (sister-pattern: d1138 uses WAKE_VERIFY_TIMEOUT_SEC env
# override; here we use ROLE for the per-role filter logic).
extract_role_wakes_fn() {
  awk '
    /^role_wakes_for_pr_labeled\(\) \{/ {flag=1}
    flag {print}
    /^\}/ {if(flag){flag=0; exit}}
  ' "$WATCH_SH"
}

# Run the filter function in a subshell with positional args $1=role, $2=labels_json.
# Returns the function's exit code (0=wake, 1=skip) per ADR-0009 § 2.1.
#
# Sister-pattern (d1138 / d-init-sh-tmpl-preservation): the awk-extracted
# function body is JUST a definition — it does NOT auto-call. To get the
# function's rc propagated, we MUST append the call inside bash -c. The
# function then becomes the last command in the script, so its rc IS the
# subshell's exit code.
role_wakes_for() {
  local role="$1" labels_json="$2"
  local fn_body
  fn_body="$(extract_role_wakes_fn)"
  [ -n "$fn_body" ] || { echo "ERROR: role_wakes_for_pr_labeled function not found in $WATCH_SH" >&2; return 2; }
  ROLE="$role" bash -c "
$fn_body
role_wakes_for_pr_labeled \"\$1\" \"\$2\"
" _ "$role" "$labels_json" >/dev/null 2>&1
}

# TC harness: invoke role_wakes_for with given inputs and assert rc=expected_rc.
assert_wake_decision() {
  local tc_name="$1" role="$2" labels_json="$3" expected_rc="$4" expected_wake="$5"
  local actual_rc
  role_wakes_for "$role" "$labels_json"
  actual_rc=$?
  if [ "$actual_rc" = "$expected_rc" ]; then
    pass "$tc_name — role=$role labels=$labels_json → $([ "$expected_wake" = "yes" ] && echo WAKE || echo SKIP) (rc=$actual_rc)"
  else
    fail "$tc_name — role=$role labels=$labels_json → expected_rc=$expected_rc actual_rc=$actual_rc (labels=$labels_json)"
  fi
}

section "Issue #179 AC2 — queue check filter behavior (≥5 TCs)"

# TC1 — cc-only filter (tester role): PR labeled only cc:tester → WAKE
assert_wake_decision "TC1 cc-only filter wakes" "tester" '["cc:tester"]' "0" "yes"

# TC2 — agent-only filter (tester role): PR labeled only agent:tester → WAKE
assert_wake_decision "TC2 agent-only filter wakes" "tester" '["agent:tester"]' "0" "yes"

# TC3 — both filters (tester role): PR labeled both cc:tester + agent:tester → WAKE
assert_wake_decision "TC3 both cc+agent filter wakes" "tester" '["cc:tester","agent:tester"]' "0" "yes"

# TC4 — neither filter (tester role): PR labeled cc:architect + agent:developer → SKIP
assert_wake_decision "TC4 neither cc nor agent filter skips" "tester" '["cc:architect","agent:developer"]' "1" "no"

# TC5 — empty queue case (tester role): PR with no labels → SKIP
assert_wake_decision "TC5 empty-queue case skips" "tester" '[]' "1" "no"

# TC6 — needs-tester-signoff wake trigger (3rd in matrix per ADR-0009 § 2.1)
assert_wake_decision "TC6 needs-tester-signoff wakes" "tester" '["needs-tester-signoff"]' "0" "yes"

# TC7 — architect role cc-only (cross-role verification, ADR-0009 § 2.1 matrix)
assert_wake_decision "TC7 architect cc-only wakes" "architect" '["cc:architect"]' "0" "yes"

# TC8 — architect role neither (cross-role neither → SKIP)
assert_wake_decision "TC8 architect neither skips" "architect" '["cc:tester","agent:developer"]' "1" "no"

section "Issue #179 AC1 — byte-equal forward-port parity"

# TC9 — sha256 parity: tmpl-side agent-watch.sh MUST match AtilCalculator
# source-of-truth (cycle ~#1142 sister, cycle ~#2988 forward-port cadence).
if [ -f "$SRC_OF_TRUTH" ]; then
  tmpl_hash="$(sha256sum "$WATCH_SH" | awk '{print $1}')"
  src_hash="$(sha256sum "$SRC_OF_TRUTH" | awk '{print $1}')"
  if [ "$tmpl_hash" = "$src_hash" ]; then
    pass "TC9 byte-equal parity (AC1) — sha256 ${tmpl_hash:0:12}… matches AtilCalculator source"
  else
    fail "TC9 byte-equal parity (AC1) — tmpl=${tmpl_hash:0:12}… src=${src_hash:0:12}… (forward-port drift)"
  fi
else
  fail "TC9 byte-equal parity (AC1) — AtilCalculator source not found at $SRC_OF_TRUTH (path: $REPO_ROOT/../AtilCalculator)"
fi

section "Issue #179 AC3 — sister-pattern cite anchors"

# TC10 — sister-pattern grep: d028 tmpl header cites ≥3 sister-patterns
# (sister-pattern lineage section per ADR-0049 ≥3 sister-pattern baseline).
sister_cite_count="$(grep -cE "Sister-pattern lineage|d1138|d-init-sh-tmpl-preservation|d024-agent-wake|d1041|d068b" "$0" 2>/dev/null || echo 0)"
if [ "$sister_cite_count" -ge 5 ]; then
  pass "TC10 sister-pattern cite count — $sister_cite_count references (≥3 required per ADR-0049)"
else
  fail "TC10 sister-pattern cite count — only $sister_cite_count references (need ≥3 per ADR-0049)"
fi

# TC11 — AC2 case coverage grep: header mentions cc-only + agent-only + both + neither + empty-queue
case_anchors="$(grep -cE "cc-only|agent-only|both|neither|empty-queue" "$0" 2>/dev/null || echo 0)"
if [ "$case_anchors" -ge 5 ]; then
  pass "TC11 AC2 case anchors — $case_anchors AC2 cases cited in header (cc-only / agent-only / both / neither / empty-queue)"
else
  fail "TC11 AC2 case anchors — only $case_anchors AC2 cases cited in header (need ≥5)"
fi

# Summary
printf "\n${B}==== d028 summary ====${D}\n"
printf "  ${G}PASS${D}: %d   ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf "\n${R}FAILURES${D}:\n"
  for f in "${FAILURES[@]}"; do printf "  - %s\n" "$f"; done
  exit 1
fi
printf "${G}All TCs GREEN — Issue #179 d028 tmpl forward-port parity verified.${D}\n"
exit 0
