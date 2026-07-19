#!/usr/bin/env bash
# d166-claim-next-ready-retro024-filter.sh — RETRO-024 silent-skip filter regression test (5 TCs).
#
# Verifies that scripts/claim-next-ready.sh filters out RETRO-024
# work-done-elsewhere terminal-state items from the claim candidate set.
#
# RETRO-024 (Issue #1027) work-done-elsewhere terminal state per CLAUDE.md:
#   type:<*> + status:ready + cc:human + (NO agent:*)
# Predicate (AND-conjunction, NOT single-condition):
#   .labels has "cc:human" AND .labels has NO label starting with "agent:"
# Bug: single-condition `cc:human` filter would over-filter LEGITIMATE active
# candidates carrying cc:human merge gate (e.g., tester APPROVED + cc:human
# canonical pre-merge gate per ADR-0012). AND-conjunction is canonical.
#
# 5 TCs (per ADR-0049 >=5 baseline, RED-first per ADR-0044):
#   TC1: single work-done-elsewhere item -> exit 1, no claim (filter removes it)
#   TC2: work-done-elsewhere (older) + active candidate -> claim active (AND-conj preserved)
#   TC3: work-done-elsewhere P0 + active P2 -> claim active P2 (priority doesn't override terminal)
#   TC4: silent_skip log emission per TD-016/020 family (lens d observability)
#   TC5: multiple work-done-elsewhere + 1 active -> claim active, log count=2 silent-skips
#
# Sister-pattern:
#   d031-claim-next-ready.sh (calc + tmpl direct sister, same fake-gh factory)
#   d1081-claim-next-ready-retro024-silent-skip.sh (calc-side sister, source-of-truth impl test)
#   d116-claim-next-ready-retry-backoff.sh (tmpl sister, retry-pattern)
#   >=2 sister-pattern coverage per ADR-0049 sister-pattern met (d031 + d1081 + d116 = 3 members)
#
# RED-first baseline: tmpl scripts/claim-next-ready.sh (HEAD d96a2b7) is MISSING
# the WORK_DONE_ELSEWHERE filter block entirely (verified cycle ~#3637 -- 0 references
# to "WORK_DONE_ELSEWHERE" / "RETRO-024" / "work-done-elsewhere" in 516 LOC).
# All 5 TCs RED-fail on current tmpl state. GREEN post-impl with AND-conjunction predicate.
#
# Story: Issue #166 (tmpl repo, calc-side fix in PR #1165 MERGED 6d9779f).
# Run: bash scripts/tests/d166-claim-next-ready-retro024-filter.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAIM_SH="$REPO_ROOT/scripts/claim-next-ready.sh"

# --- test framework ---
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

PASS=0; FAIL=0
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; B=""; D=""
fi
pass() { printf "  ${G}PASS${D} -- %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}FAIL${D} -- %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

# --- fake gh factory (d031 sister-pattern, inline case-statement, no heredoc, no sed) ---
# Usage: make_fake_gh <gh_path> <wip_count> <ready_json> <log_path>
make_fake_gh() {
  local gh_path="$1"
  local wip_count="$2"
  local ready_json="$3"
  local log_path="$4"

  local ready_file="$gh_path.ready.json"
  if [ -n "$ready_json" ] && [ "$ready_json" != "EMPTY" ]; then
    printf '%s' "$ready_json" > "$ready_file"
  else
    : > "$ready_file"
  fi

  cat > "$gh_path" <<'FAKE_GH_EOF'
#!/usr/bin/env bash
echo "CALL $*" >> "${FAKE_LOG_PATH:-/tmp/fake-gh.log}"

case "$*" in
  *"repo view"*)
    echo '{"nameWithOwner":"test-owner/test-repo"}'
    ;;
  *"status:in-progress"*)
    case "${FAKE_WIP_COUNT:-0}" in
      0) echo '[]' ;;
      1) echo '[{"number":900}]' ;;
      2) echo '[{"number":900},{"number":901}]' ;;
      *) echo '[]' ;;
    esac
    ;;
  *"status:ready"*)
    if [ -s "${FAKE_READY_FILE:-/dev/null}" ]; then
      cat "${FAKE_READY_FILE}"
    else
      echo '[]'
    fi
    ;;
  *"issue view "*)
    # Return closed for any issue (no open deps to worry about in this d-test).
    echo "closed"
    ;;
  *"issue edit"*)
    echo "EDIT $*" >> "${FAKE_LOG_PATH:-/tmp/fake-gh.log}"
    ;;
  *"issue comment"*)
    echo "COMMENT $*" >> "${FAKE_LOG_PATH:-/tmp/fake-gh.log}"
    ;;
  *)
    echo '[]'
    ;;
esac
FAKE_GH_EOF
  chmod +x "$gh_path"
}

# --- run helper ---
# Usage: run_claim <role> <wip_count> <ready_json>
# Sets globals: CLAIM_OUT, CLAIM_RC, CLAIM_LOG
run_claim() {
  local role="$1"
  local wip_count="$2"
  local ready_json="$3"
  shift 3

  local fake_bin
  fake_bin="$(mktemp -d "$TEST_TMPDIR/fakebin-XXXXXX")"
  local gh_path="$fake_bin/gh"
  local log_path="$fake_bin/gh-log"
  make_fake_gh "$gh_path" "$wip_count" "$ready_json" "$log_path"

  CLAIM_LOG="$log_path"
  CLAIM_OUT="$(env \
    FAKE_WIP_COUNT="$wip_count" \
    FAKE_READY_FILE="$gh_path.ready.json" \
    FAKE_LOG_PATH="$log_path" \
    PATH="$fake_bin:$PATH" \
    GITHUB_REPO="test-owner/test-repo" \
    AUTO_CLAIM_LOG_DIR="$TEST_TMPDIR/logs" \
    bash "$CLAIM_SH" "$role" 2>&1)"
  CLAIM_RC=$?
}

# Pre-create audit log dir (RETRO-024 silent_skip writes here)
mkdir -p "$TEST_TMPDIR/logs"

# ============================================================================
section "TC1: single work-done-elsewhere item -> exit 1, no claim"
# RETRO-024 terminal state: type:<*> + status:ready + cc:human + (NO agent:*)
# Filter must remove this from candidate set, leaving 0 ready items -> exit 1.
ready='[
  {"number":900,"title":"work-done-elsewhere","createdAt":"2026-07-19T00:00:00Z",
   "labels":[{"name":"type:bug"},{"name":"priority:P1"},{"name":"status:ready"},{"name":"cc:human"}],
   "body":""}
]'
run_claim developer 0 "$ready"
if [ "$CLAIM_RC" = "1" ] && echo "$CLAIM_OUT" | grep -q "no ready items"; then
  if grep -q "EDIT .* 900" "$CLAIM_LOG" 2>/dev/null; then
    fail "script claimed work-done-elsewhere #900 (filter missing)" "should filter RETRO-024 terminal state"
  else
    pass "work-done-elsewhere item filtered out -> exit 1 (no false-positive claim)"
  fi
else
  fail "unexpected exit/output for work-done-elsewhere-only input" "rc=$CLAIM_RC out=$CLAIM_OUT"
fi

# ============================================================================
section "TC2: work-done-elsewhere (older) + active candidate -> claim active"
# Two ready items: #800 work-done-elsewhere (older), #801 active candidate (newer).
# Filter must remove #800, leaving #801 as sole candidate -> claim #801.
# AND-conjunction check: if impl uses single-condition `cc:human`, BOTH get filtered -> exit 1.
ready='[
  {"number":800,"title":"work-done-elsewhere (older)","createdAt":"2026-07-19T00:00:00Z",
   "labels":[{"name":"type:bug"},{"name":"priority:P1"},{"name":"status:ready"},{"name":"cc:human"}],
   "body":""},
  {"number":801,"title":"active candidate (newer)","createdAt":"2026-07-19T01:00:00Z",
   "labels":[{"name":"type:bug"},{"name":"priority:P1"},{"name":"status:ready"},{"name":"agent:developer"},{"name":"cc:human"},{"name":"needs-tester-signoff"}],
   "body":""}
]'
run_claim developer 0 "$ready"
if [ "$CLAIM_RC" = "0" ] && echo "$CLAIM_OUT" | grep -q "claimed #801"; then
  if grep -q "EDIT .* 800" "$CLAIM_LOG" 2>/dev/null; then
    fail "script claimed work-done-elsewhere #800 instead of active #801" "filter missing OR wrong predicate"
  else
    pass "work-done-elsewhere filtered, active candidate #801 claimed (AND-conjunction preserved)"
  fi
elif [ "$CLAIM_RC" = "1" ]; then
  fail "AND-conjunction broken: single-condition cc:human filter over-filtered active #801" \
       "expected: claim #801; got exit 1 (both filtered)"
else
  fail "unexpected exit/output" "rc=$CLAIM_RC out=$CLAIM_OUT"
fi

# ============================================================================
section "TC3: work-done-elsewhere P0 + active P2 -> claim active P2 (priority does not override terminal)"
# Priority sort says P0 wins, but RETRO-024 terminal state MUST be filtered first.
# #850 is P0 work-done-elsewhere, #851 is P2 active. Filter removes #850 -> claim #851.
ready='[
  {"number":850,"title":"P0 work-done-elsewhere","createdAt":"2026-07-19T00:00:00Z",
   "labels":[{"name":"type:bug"},{"name":"priority:P0"},{"name":"status:ready"},{"name":"cc:human"}],
   "body":""},
  {"number":851,"title":"P2 active candidate","createdAt":"2026-07-19T01:00:00Z",
   "labels":[{"name":"type:bug"},{"name":"priority:P2"},{"name":"status:ready"},{"name":"agent:developer"}],
   "body":""}
]'
run_claim developer 0 "$ready"
if [ "$CLAIM_RC" = "0" ] && echo "$CLAIM_OUT" | grep -q "claimed #851"; then
  if grep -q "EDIT .* 850" "$CLAIM_LOG" 2>/dev/null; then
    fail "script claimed P0 work-done-elsewhere #850 (priority override bug)" "terminal state must filter BEFORE priority sort"
  else
    pass "P0 work-done-elsewhere filtered despite higher priority, P2 active claimed"
  fi
else
  fail "unexpected exit/output" "rc=$CLAIM_RC out=$CLAIM_OUT"
fi

# ============================================================================
section "TC4: silent_skip log emission per TD-016/020 family (lens d observability)"
# RETRO-024 silent-skip emits `work-done-elsewhere-silent-skip count=N` line to
# AUTO_CLAIM_LOG_DIR/auto-claim.log. Without this log, observability gap -> TD-016/020.
ready='[
  {"number":900,"title":"work-done-elsewhere","createdAt":"2026-07-19T00:00:00Z",
   "labels":[{"name":"type:bug"},{"name":"priority:P1"},{"name":"status:ready"},{"name":"cc:human"}],
   "body":""}
]'
run_claim developer 0 "$ready"
audit_log="$TEST_TMPDIR/logs/auto-claim.log"
if [ -f "$audit_log" ] && grep -q "work-done-elsewhere-silent-skip" "$audit_log"; then
  pass "silent_skip log emitted (TD-016/020 observability) -- line: $(grep 'work-done-elsewhere-silent-skip' "$audit_log" | head -1)"
else
  fail "silent_skip log NOT emitted to $audit_log" \
       "expected line matching 'work-done-elsewhere-silent-skip count=N'; file=$(ls -la "$audit_log" 2>&1)"
fi

# ============================================================================
section "TC5: multiple work-done-elsewhere + 1 active -> claim active, log count=2"
# 2 work-done-elsewhere items + 1 active candidate. Filter removes 2, claims 1.
# silent_skip log should show count=2.
ready='[
  {"number":700,"title":"work-done-elsewhere A","createdAt":"2026-07-19T00:00:00Z",
   "labels":[{"name":"type:bug"},{"name":"priority:P0"},{"name":"status:ready"},{"name":"cc:human"}],
   "body":""},
  {"number":701,"title":"work-done-elsewhere B","createdAt":"2026-07-19T00:30:00Z",
   "labels":[{"name":"type:chore"},{"name":"priority:P1"},{"name":"status:ready"},{"name":"cc:human"}],
   "body":""},
  {"number":702,"title":"active candidate","createdAt":"2026-07-19T01:00:00Z",
   "labels":[{"name":"type:bug"},{"name":"priority:P2"},{"name":"status:ready"},{"name":"agent:developer"}],
   "body":""}
]'
run_claim developer 0 "$ready"
if [ "$CLAIM_RC" = "0" ] && echo "$CLAIM_OUT" | grep -q "claimed #702"; then
  audit_log="$TEST_TMPDIR/logs/auto-claim.log"
  if [ -f "$audit_log" ] && grep -q "work-done-elsewhere-silent-skip.*count=2" "$audit_log"; then
    pass "active #702 claimed, silent_skip log shows count=2"
  else
    fail "active #702 claimed but silent_skip count wrong" \
         "expected 'count=2'; got: $(grep 'work-done-elsewhere' "$audit_log" 2>/dev/null | head -2)"
  fi
elif [ "$CLAIM_RC" = "0" ] && echo "$CLAIM_OUT" | grep -q "claimed #700\|claimed #701"; then
  fail "script claimed work-done-elsewhere item instead of active #702" "filter missing"
else
  fail "unexpected exit/output" "rc=$CLAIM_RC out=$CLAIM_OUT"
fi

# ============================================================================
printf "\n${B}==== SUMMARY ====${D}\n"
printf "  ${G}PASS${D}: %d\n" "$PASS"
printf "  ${R}FAIL${D}: %d\n" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo
  echo "d166 REGRESSION FAILED -- claim-next-ready.sh RETRO-024 filter contract violated."
  echo "Fix: add WORK_DONE_ELSEWHERE_COUNT jq predicate block + silent_skip log emission per RETRO-024 (calc sister-pattern: scripts/claim-next-ready.sh lines 412-440 in calc after PR #1165 squash 6d9779f)."
  exit 1
fi
echo
echo "d166 REGRESSION PASS -- claim-next-ready.sh (RETRO-024 silent-skip filter) contract honored. 5/5 TCs green."
exit 0