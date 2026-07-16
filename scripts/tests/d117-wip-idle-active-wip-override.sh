#!/usr/bin/env bash
# d117-wip-idle-active-wip-override.sh
#
# d117 — tmpl Issue #117 BUG regression guard (sister of calc d1091 + Issue #1091):
#         wip-idle-detect.sh wip_count > 0 must override activity-signal check
#         (any active WIP = NOT idle). Self-referential false-positive:
#         claim via label flip doesn't count as "comment" signal; no PR yet;
#         no commits → all 3 signals missing → flagged idle within minutes of claim.
#
# Why this test exists
# --------------------
# tmpl scripts/wip-idle-detect.sh current logic (lines 138-180):
#   1. Filter roles to status:in-progress + agent:<role>
#   2. For each WIP issue, check 3 activity signals (comment/PR-draft/commit)
#   3. If all signals missing/old → mark idle (THIS IS THE BUG, sister-pattern
#      of calc Issue #1091 BUG)
#
# Defect shape (sister-pattern to calc Issue #1091 body):
#   - Claim via `gh issue edit --add-label status:in-progress --remove-label status:backlog`
#     does NOT count as a "comment" (signal 2 misses the label flip)
#   - Just-claimed issue has no linked PR yet (signal 1 = -1 missing)
#   - No commits on PR (signal 3 = -1 missing)
#   - All 3 signals missing → is_idle = true → flagged idle within 5min of claim
#
# Live instance (calc side, cycle ~#2272 orchestrator-captured):
#   - Dev claimed Issue #1091 at 04:58:55Z (status:in-progress flip)
#   - Orchestrator's agent-watch.sh called wip-idle-detect.sh at 05:12:36Z (~14min later)
#   - WIP count for developer = 1 (Issue #1091)
#   - Issue #1091: no comment, no PR, no commits → all signals missing
#   - Dev flagged as idle at 05:12:36Z, 0min age — SELF-REFERENTIAL FP
#     (the wip_idle BUG itself triggered wip_idle detection)
#
# Fix spec (sister-pattern to calc Issue #1091 body, points 1+2):
#   "scripts/wip-idle-detect.sh must:
#    1. Cross-check status:in-progress label on issues assigned to the role before flagging idle
#    2. If role has ≥1 issue with status:in-progress + agent:<role>, NOT flag idle"
#
# TC list (7 per ADR-0049 ≥5 baseline):
#   TC0 bash -n syntactic self-check (PASS pre/post hygiene)
#   TC1 happy path — 0 WIP for all roles → no roles flagged idle (no regression)
#   TC2 self-referential FP — 1 WIP for developer + no activity signals → NOT idle (RED pre, GREEN post)
#   TC3 mixed activity — 1 WIP for developer + recent comment → NOT idle (existing behavior preserved)
#   TC4 stale activity regression — 0 WIP for all roles → no roles flagged idle (regression anchor)
#   TC5 multi-role selectivity — developer has 1 WIP, other roles 0 WIP → empty idle list
#   TC6 Cadence Rule 1 atomic — INDEX.md has d117 row (ADR-0055 §1)
#
# Run: bash scripts/tests/d117-wip-idle-active-wip-override.sh
# Exit: 0 = all pass, 1 = at least one fail.
#
# Sister-pattern lineage (sister-fix from calc d1091):
#   - calc d1091 (Issue #1091 BUG regression guard, calc PR #1101 squash-READY cycle ~#2305)
#     Same impl, same TC list, same RED→GREEN surface; this d117 is the tmpl mirror.
#   - calc d1088 (Issue #1088 query_stale_verdict owner-gate exemption — same
#     agent-watch.sh heuristic-gap doctrinel class, same "heuristic misses state-change
#     primitive" pattern, same RETRO-024 silent-skip sister)
#   - calc d1081 (Issue #1081 RETRO-024 silent-skip — same claim predicate race
#     detection doctrinel class, sister at claim-next-ready.sh interface)
#   - calc d020a (Form C claim predicate race — original race detection pattern)
#   - tmpl d034 (proactive-wip-idle — main flow test for wip-idle-detect.sh,
#     d117 EXTENDS d034 with claim-freshness override specifically)
#   - tmpl d116 (Issue #116 retry-with-backoff — cluster partner, same Pattern A
#     single-PR atomic, same merge-day cluster-squash per ADR-0059)
#
# Refs: tmpl Issue #117 (P2 sprint:current template-gap-close — cycle ~#2308
#       owner-authorized parallel-to-squash claim per orchestrator directive),
#       calc Issue #1091 (origin), calc PR #1101 (calc impl, squash-READY cycle ~#2305),
#       ADR-0015 (atomic 4-flag hand-off — claim via `gh issue edit --add-label
#       status:in-progress` is the state-change primitive the heuristic missed),
#       ADR-0039 (WIP-idle watchdog — current broken surface, signals 1/2/3 miss
#       claim state-change),
#       ADR-0044 (RED-first TDD doctrinal home — TC2 RED pre-impl),
#       ADR-0049 (≥5 TCs baseline — d117 = 7 TCs met),
#       ADR-0055 §1 (Cadence Rule 1 atomic — d-test + INDEX.md row + impl same
#       PR cluster — Pattern A single-PR atomic),
#       ADR-0059 (cluster-squash — tmpl #117 PR cluster sister of tmpl #116 PR
#       cluster same merge-day per cycle ~#2308 owner directive option A),
#       Issue #113 (label-authority — d117 slot = issue-number sister of calc d1091).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WIP_SH="$REPO_ROOT/scripts/wip-idle-detect.sh"
INDEX_MD="$SCRIPT_DIR/INDEX.md"

# --- test framework ---
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

PASS=0; FAIL=0
declare -a FAILURES
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; B=""; D=""
fi
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); FAILURES+=("$1"); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

# --- preflight ---
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required for d117" >&2
  exit 127
fi
if [ ! -r "$WIP_SH" ]; then
  echo "ERROR: wip-idle-detect.sh not found at $WIP_SH" >&2
  exit 127
fi

# --- mock gh PATH shim ---
# MOCK_GH_MODE controls scenario:
#   happy        — 0 WIP for all roles → no idle output (TC1)
#   selfref      — 1 WIP for developer, no comments/PR/commits (TC2 RED pre, GREEN post)
#   mixedactive  — 1 WIP for developer + recent comment on that issue (TC3)
#   stale        — 0 WIP for all roles → no idle (TC4 stub)
#   multirole    — developer has 1 WIP (active), other roles 0 WIP (TC5)
MOCK_GH_CALL_LOG="$TEST_TMPDIR/gh-call.log"
: > "$MOCK_GH_CALL_LOG"

mock_gh_setup() {
  cat > "$TEST_TMPDIR/gh" <<'MOCK_EOF'
#!/usr/bin/env bash
LOG="$MOCK_GH_CALL_LOG"
echo "$@" >> "$LOG"
MODE="${MOCK_GH_MODE:-happy}"
ARGS="$*"

# Differentiate by full arg pattern (issue list vs issue view vs pr list vs api)
is_issue_list() { echo "$ARGS" | grep -q "issue list"; }
is_issue_view() { echo "$ARGS" | grep -q "issue view"; }

# Helper: 1 WIP issue for developer (just claimed)
wip_dev_issue() {
  NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '[{"number":117,"title":"BUG: wip-idle-detect self-referential FP","updatedAt":"%s"}]\n' "$NOW"
}

# Helper: 1 recent comment for issue 117
wip_dev_recent_comment() {
  NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"comments":[{"updatedAt":"%s"}]}\n' "$NOW"
}

case "$MODE" in
  happy)
    # 0 WIP for all roles
    echo '[]'
    ;;
  selfref)
    # 1 WIP for developer, no comments/PR/commits
    if is_issue_list && echo "$ARGS" | grep -q "agent:developer" && echo "$ARGS" | grep -q "status:in-progress"; then
      wip_dev_issue
    elif is_issue_view; then
      # Return post-jq ISO timestamp string (empty → signal 2 missing)
      echo ""
    else
      echo '[]'
    fi
    ;;
  mixedactive)
    # 1 WIP for developer + recent comment
    if is_issue_list && echo "$ARGS" | grep -q "agent:developer" && echo "$ARGS" | grep -q "status:in-progress"; then
      wip_dev_issue
    elif is_issue_view; then
      # Return post-jq recent ISO timestamp string (signal 2 fresh)
      NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "$NOW"
    else
      echo '[]'
    fi
    ;;
  stale)
    echo '[]'
    ;;
  multirole)
    # developer has 1 WIP, others 0
    if is_issue_list && echo "$ARGS" | grep -q "agent:developer" && echo "$ARGS" | grep -q "status:in-progress"; then
      wip_dev_issue
    elif is_issue_list; then
      echo '[]'
    elif is_issue_view; then
      echo '{"comments":[]}'
    else
      echo '[]'
    fi
    ;;
  *)
    echo '[]'
    ;;
esac
MOCK_EOF
  chmod +x "$TEST_TMPDIR/gh"
}

# Helper: run wip-idle-detect.sh with mock gh in PATH + mode env
run_wip_detect() {
  : > "$MOCK_GH_CALL_LOG"
  mock_gh_setup
  MOCK_GH_MODE="$1" \
  PATH="$TEST_TMPDIR:$PATH" \
  GITHUB_REPO="atilproject/dev-studio-template" \
    bash "$WIP_SH" \
    >"$TEST_TMPDIR/stdout.log" 2>"$TEST_TMPDIR/stderr.log"
  return $?
}

# Helper: extract role list from idle JSON output
extract_idle_roles() {
  jq -r '.[].role' "$TEST_TMPDIR/stdout.log" 2>/dev/null | sort
}

# ===========================================================================
# Test cases
# ===========================================================================

# TC0 — bash -n syntactic self-check (hygiene per ADR-0049 baseline).
section "TC0 — bash -n syntactic self-check"
if bash -n "$WIP_SH" 2>/dev/null; then
  pass "TC0 — bash -n syntactic check PASS (wip-idle-detect.sh syntactically valid)"
else
  fail "TC0 — bash -n syntactic check FAIL" "wip-idle-detect.sh has bash syntax error — RED pre-impl, must be fixed before any TCs run"
fi

# TC1 — happy path: 0 WIP for all roles → no idle output (regression anchor).
section "TC1 — happy path: 0 WIP for all roles"
run_wip_detect "happy"
TC1_RC=$?
TC1_IDLE_ROLES="$(extract_idle_roles)"
if [ "$TC1_RC" -eq 0 ] && [ -z "$TC1_IDLE_ROLES" ]; then
  pass "TC1 — happy path: rc=0 + no roles flagged idle (no regression)"
else
  fail "TC1 — happy path: rc=$TC1_RC, idle_roles='$TC1_IDLE_ROLES'" "expected rc=0 + empty idle list"
fi

# TC2 — self-referential FP: developer has 1 WIP + no activity signals.
# Pre-fix (BUG): developer IS flagged as idle.
# Post-fix: developer is NOT flagged as idle (any active WIP = NOT idle).
section "TC2 — self-referential FP fix: 1 WIP + no activity signals → NOT idle"
run_wip_detect "selfref"
TC2_RC=$?
TC2_IDLE_ROLES="$(extract_idle_roles)"
if [ "$TC2_RC" -eq 0 ] && ! echo "$TC2_IDLE_ROLES" | grep -q "^developer$"; then
  pass "TC2 — self-referential FP: developer (1 WIP + no signals) NOT flagged idle (fix applied)"
else
  fail "TC2 — self-referential FP: developer flagged idle despite 1 active WIP (BUG)" "rc=$TC2_RC, idle_roles='$TC2_IDLE_ROLES' | RED pre-impl (developer IS in idle list — bug present); GREEN post-impl (NOT in idle list — fix applied)"
fi

# TC3 — mixed activity: developer has 1 WIP + recent comment.
# Both pre/post-fix: NOT idle (existing behavior preserved — regression anchor).
section "TC3 — mixed activity: 1 WIP + recent comment → NOT idle (regression anchor)"
run_wip_detect "mixedactive"
TC3_RC=$?
TC3_IDLE_ROLES="$(extract_idle_roles)"
if [ "$TC3_RC" -eq 0 ] && ! echo "$TC3_IDLE_ROLES" | grep -q "^developer$"; then
  pass "TC3 — mixed activity: developer (1 WIP + recent comment) NOT flagged idle (regression preserved)"
else
  fail "TC3 — mixed activity: developer flagged idle despite recent activity (regression)" "rc=$TC3_RC, idle_roles='$TC3_IDLE_ROLES'"
fi

# TC4 — stale activity: 0 WIP for all roles → no idle (regression anchor).
# Verify the script still handles the simple case (no WIP anywhere).
section "TC4 — stale activity: 0 WIP, no activity (regression anchor)"
run_wip_detect "stale"
TC4_RC=$?
TC4_IDLE_ROLES="$(extract_idle_roles)"
if [ "$TC4_RC" -eq 0 ] && [ -z "$TC4_IDLE_ROLES" ]; then
  pass "TC4 — stale: 0 WIP, no roles flagged idle (heuristic still works for empty WIP)"
else
  fail "TC4 — stale: 0 WIP should not flag any role idle" "rc=$TC4_RC, idle_roles='$TC4_IDLE_ROLES'"
fi

# TC5 — multi-role selectivity: developer has 1 WIP, all other roles 0 WIP.
# After fix: developer NOT idle (1 WIP), other roles NOT idle (0 WIP).
# Verifies the fix doesn't break the selective logic across roles.
section "TC5 — multi-role selectivity: developer 1 WIP, others 0"
run_wip_detect "multirole"
TC5_RC=$?
TC5_IDLE_ROLES="$(extract_idle_roles)"
# Expectation: empty idle list (developer has WIP = NOT idle; others have no WIP = NOT idle)
if [ "$TC5_RC" -eq 0 ] && [ -z "$TC5_IDLE_ROLES" ]; then
  pass "TC5 — multi-role: developer (1 WIP) NOT idle + others (0 WIP) NOT idle (empty idle list)"
else
  fail "TC5 — multi-role: idle list='$TC5_IDLE_ROLES'" "expected empty idle list (fix preserves selective logic)"
fi

# TC6 — Cadence Rule 1 atomic (ADR-0055 §1): INDEX.md has d117 row.
section "TC6 — Cadence Rule 1 atomic (INDEX.md d117 row present)"
if grep -q "d117" "$INDEX_MD" 2>/dev/null; then
  pass "TC6 — scripts/tests/INDEX.md has d117 row (Cadence Rule 1 atomic honored)"
else
  fail "TC6 — scripts/tests/INDEX.md missing d117 row (Cadence Rule 1 atomic violation per ADR-0055 §1)" "Add d117 row to INDEX.md in this commit per sister-pattern d1091 TC6"
fi

# ===========================================================================
# Summary
# ===========================================================================
printf "\n${B}==== Summary ====${D}\n"
printf "PASS: %d / %d\n" "$PASS" "$((PASS + FAIL))"
printf "FAIL: %d / %d\n" "$FAIL" "$((PASS + FAIL))"
if [ "$FAIL" -gt 0 ]; then
  printf "\n${R}Failed tests:${D}\n"
  for f in "${FAILURES[@]}"; do
    printf "  ${R}✗${D} %s\n" "$f"
  done
fi
printf "\n"
[ "$FAIL" -eq 0 ] || exit 1
