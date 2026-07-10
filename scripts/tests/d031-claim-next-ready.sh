#!/usr/bin/env bash
# d031-claim-next-ready.sh — ADR-0038 §Layer 2 regression test (10 TCs).
#
# Replaces scripts/tests/d031-claim-next-ready-stub.sh (Issue #276 STUB coverage,
# retired per Issue #537 Sprint 15 P2 drift remediation — arch verdict Option B).
# Tests the full impl of scripts/claim-next-ready.sh (Issue #271) via a fake
# `gh` binary that returns canned JSON for list/view calls and records
# edit/comment calls to a log the test can inspect.
#
# 10 TCs (per docs/backlog/STORY-019.md, Issue #520 AC4 + ADR-0044 RED-first TDD):
#   TC1: 3 ready items P0/P1/P2 → claim P0 first (priority sort, issue-level)
#   TC2: 2 ready items same priority, different ages → claim oldest (age tie-break, issue-level)
#   TC3: ready item with open dep → skip; another without dep → claim (dep parser, issue-level)
#   TC4: 2 in-progress + 1 ready → exit 3, no claim (WIP cap, issue-level)
#   TC5: NEW priority/age work-stream tie-break (sister-pattern to d058 TC2)
#   TC6: NEW ready=0 work-stream negative (sister-pattern to d058 TC6)
#   TC7: NEW dep work-stream filter (sister-pattern to d058 TC9)
#   TC8: usage error (no role arg) → exit 2
#   TC9: invalid role → exit 2
#   TC10: audit log written on claim
#
# Sister-pattern to d058-claim-wip-workstream.sh (9 TCs, post-PR #511).
# Work-stream awareness per ADR-0038 §Work-Stream Awareness amendment (PR #504 squash).
# Fake-gh pattern: inline case-statement (NO heredoc, NO sed — d058-style env-var heredoc
# avoided for portability across macOS BSD sed vs GNU sed).
#
# Run: bash scripts/tests/d031-claim-next-ready.sh

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
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

# --- fake gh factory ---
# Usage: make_fake_gh <gh_path> <wip_count> <ready_json_or_empty> <dep_open_issue_n> <log_path> [pr_clusters_json]
# Writes the ready JSON + cluster JSON to files next to the fake gh, so the fake gh can
# cat them directly. Env vars (FAKE_WIP_FILE, FAKE_READY_FILE, FAKE_CLUSTERS_FILE,
# FAKE_DEP_OPEN_N, FAKE_LOG_PATH) are passed at runtime — no heredoc variable-expansion pitfalls,
# no sed extraction (BSD/GNU portability).
make_fake_gh() {
  local gh_path="$1"
  local wip_count="$2"
  local ready_json="$3"
  local dep_open_n="$4"
  local log_path="$5"
  local pr_clusters="${6:-}"

  local ready_file="$gh_path.ready.json"
  if [ -n "$ready_json" ] && [ "$ready_json" != "EMPTY" ]; then
    printf '%s' "$ready_json" > "$ready_file"
  else
    : > "$ready_file"
  fi

  local clusters_file="$gh_path.clusters.json"
  if [ -n "$pr_clusters" ]; then
    printf '%s' "$pr_clusters" > "$clusters_file"
  else
    printf '{}' > "$clusters_file"
  fi

  # Inline case-statement (d031 pattern, NO heredoc, NO sed).
  cat > "$gh_path" <<'EOF'
#!/usr/bin/env bash
echo "CALL $*" >> "${FAKE_LOG_PATH:-/tmp/fake-gh.log}"

# Dispatch on command surface (case-statement pattern, d031-native, no sed extraction).
case "$*" in
  *"repo view"*)
    echo '{"nameWithOwner":"test-owner/test-repo"}'
    ;;
  *"status:in-progress"*)
    # Return JSON array (matches `gh issue list --json number` output).
    case "${FAKE_WIP_COUNT:-0}" in
      0) echo '[]' ;;
      1) echo '[{"number":900}]' ;;
      2) echo '[{"number":900},{"number":901}]' ;;
      3) echo '[{"number":900},{"number":901},{"number":902}]' ;;
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
    # Return just the state value (matches what the script's `gh -q .state` would extract).
    n=$(echo "$*" | awk '{for(i=1;i<=NF;i++) if($i=="view") {print $(i+1); exit}}')
    if [ "$n" = "${FAKE_DEP_OPEN_N:-}" ]; then
      echo "open"
    else
      echo "closed"
    fi
    ;;
  *"pr list"*"Closes"*)
    # Return PR cluster info for work-stream awareness testing.
    # Extract the issue number from the --search arg via awk (NOT sed — portability).
    search_n=$(echo "$*" | awk '{for(i=1;i<=NF;i++) if($i ~ /^#/) {gsub(/^#/,"",$i); print $i; exit}}')
    if [ -n "$search_n" ] && [ -n "${FAKE_CLUSTERS_FILE:-}" ] && [ -f "${FAKE_CLUSTERS_FILE}" ]; then
      body_for=$(awk -v k="$search_n" 'BEGIN{FS=":"} $1 ~ ("^\""k"\"") {sub(/^"[^"]+":"/,""); sub(/"$/,""); print; exit}' "${FAKE_CLUSTERS_FILE}")
      if [ -n "$body_for" ]; then
        printf '[{"number":900,"body":"%s"}]' "$body_for"
      else
        echo '[]'
      fi
    else
      echo '[]'
    fi
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
EOF
  chmod +x "$gh_path"
}

# --- run helper: invoke claim script with fake gh on PATH ---
# Usage: run_claim <role> <wip_count> <ready_json> <dep_open_n> [pr_clusters_json] [extra_env...]
# Sets globals: CLAIM_OUT, CLAIM_RC, CLAIM_LOG
run_claim() {
  local role="$1"
  local wip_count="$2"
  local ready_json="$3"
  local dep_open_n="$4"
  local pr_clusters="${5:-}"
  shift 5

  # Each test gets a fresh temp dir with a `gh` binary at the top of PATH.
  local fake_bin
  fake_bin="$(mktemp -d "$TEST_TMPDIR/fakebin-XXXXXX")"
  local gh_path="$fake_bin/gh"
  local log_path="$fake_bin/gh-log"
  make_fake_gh "$gh_path" "$wip_count" "$ready_json" "$dep_open_n" "$log_path" "$pr_clusters"

  CLAIM_LOG="$log_path"
  # Use `env` explicitly to pass all required env vars to the subshell.
  # (Plain `VAR=val cmd` assignments don't survive `$(...)` command substitution
  # reliably with line continuations; `env` makes this explicit and correct.)
  CLAIM_OUT="$(env \
    FAKE_WIP_COUNT="$wip_count" \
    FAKE_READY_FILE="$gh_path.ready.json" \
    FAKE_CLUSTERS_FILE="$gh_path.clusters.json" \
    FAKE_DEP_OPEN_N="$dep_open_n" \
    FAKE_LOG_PATH="$log_path" \
    PATH="$fake_bin:$PATH" \
    GITHUB_REPO="test-owner/test-repo" \
    AUTO_CLAIM_LOG_DIR="$TEST_TMPDIR/logs" \
    bash "$CLAIM_SH" "$role" 2>&1)"
  CLAIM_RC=$?
}

# Pre-create audit log dir
mkdir -p "$TEST_TMPDIR/logs"

# ============================================================================
section "TC1: 3 ready items P0/P1/P2 → claim P0 first (priority sort)"
# 233 = P0 (newest), 260 = P1, 263 = P2 (oldest). Priority should override age.
ready='[
  {"number":263,"title":"P2 oldest","createdAt":"2026-06-22T08:00:00Z","labels":[{"name":"priority:P2"},{"name":"status:ready"},{"name":"agent:developer"}],"body":""},
  {"number":260,"title":"P1 mid","createdAt":"2026-06-22T09:00:00Z","labels":[{"name":"priority:P1"},{"name":"status:ready"},{"name":"agent:developer"}],"body":""},
  {"number":233,"title":"P0 newest","createdAt":"2026-06-22T10:00:00Z","labels":[{"name":"priority:P0"},{"name":"status:ready"},{"name":"agent:developer"}],"body":""}
]'
run_claim developer 0 "$ready" ""
if [ "$CLAIM_RC" = "0" ] && echo "$CLAIM_OUT" | grep -q "claimed #233"; then
  pass "P0 (#233) claimed first despite being newest (priority > age)"
elif [ "$CLAIM_RC" = "0" ] && echo "$CLAIM_OUT" | grep -q "claimed #260"; then
  fail "P1 claimed before P0" "got: $CLAIM_OUT"
elif [ "$CLAIM_RC" = "0" ] && echo "$CLAIM_OUT" | grep -q "claimed #263"; then
  fail "P2 claimed before P0/P1" "got: $CLAIM_OUT"
else
  fail "unexpected exit/output" "rc=$CLAIM_RC out=$CLAIM_OUT"
fi

# ============================================================================
section "TC2: 2 ready items same priority P1, different ages → claim oldest"
# 100 = older, 101 = newer. Both P1. Age tie-break → #100 first.
ready='[
  {"number":101,"title":"P1 newer","createdAt":"2026-06-22T10:00:00Z","labels":[{"name":"priority:P1"},{"name":"status:ready"},{"name":"agent:developer"}],"body":""},
  {"number":100,"title":"P1 older","createdAt":"2026-06-22T08:00:00Z","labels":[{"name":"priority:P1"},{"name":"status:ready"},{"name":"agent:developer"}],"body":""}
]'
run_claim developer 0 "$ready" ""
if [ "$CLAIM_RC" = "0" ] && echo "$CLAIM_OUT" | grep -q "claimed #100"; then
  pass "older P1 (#100) claimed first (age tie-break)"
elif [ "$CLAIM_RC" = "0" ] && echo "$CLAIM_OUT" | grep -q "claimed #101"; then
  fail "newer P1 claimed first" "age tie-break should prefer older; got: $CLAIM_OUT"
else
  fail "unexpected exit/output" "rc=$CLAIM_RC out=$CLAIM_OUT"
fi

# ============================================================================
section "TC3: ready item with open dep → skip; another without dep → claim"
# 50 has 'depends on #225' (open). 51 has no dep. #51 should be claimed.
ready='[
  {"number":50,"title":"with open dep","createdAt":"2026-06-22T08:00:00Z","labels":[{"name":"priority:P1"},{"name":"status:ready"},{"name":"agent:developer"}],"body":"## Problem\nDepends on #225 for the schema."},
  {"number":51,"title":"no dep","createdAt":"2026-06-22T09:00:00Z","labels":[{"name":"priority:P1"},{"name":"status:ready"},{"name":"agent:developer"}],"body":"## Problem\nNo external deps."}
]'
run_claim developer 0 "$ready" "225"
if [ "$CLAIM_RC" = "0" ] && echo "$CLAIM_OUT" | grep -q "claimed #51"; then
  if grep -q "EDIT .* 50" "$CLAIM_LOG" 2>/dev/null; then
    fail "script tried to claim #50 (should have skipped)" "open dep should trigger try-next"
  else
    pass "open-dep item (#50) skipped, dep-free item (#51) claimed (try-next worked)"
  fi
elif [ "$CLAIM_RC" = "0" ] && echo "$CLAIM_OUT" | grep -q "claimed #50"; then
  fail "claimed #50 despite open dep on #225" "dep parser missed"
else
  fail "unexpected exit/output" "rc=$CLAIM_RC out=$CLAIM_OUT"
fi

# ============================================================================
section "TC4: 2 in-progress + 1 ready → exit 3, no claim (WIP cap, issue-level)"
ready='[
  {"number":300,"title":"ready item","createdAt":"2026-06-22T10:00:00Z","labels":[{"name":"priority:P0"},{"name":"status:ready"},{"name":"agent:developer"}],"body":""}
]'
run_claim developer 2 "$ready" ""
if [ "$CLAIM_RC" = "3" ] && echo "$CLAIM_OUT" | grep -q "WIP limit reached"; then
  if grep -q "EDIT" "$CLAIM_LOG" 2>/dev/null; then
    fail "WIP cap hit but script still edited an issue" "should NOT edit when WIP >= limit"
  else
    pass "WIP cap honored (2/2, no edit, exit 3)"
  fi
else
  fail "WIP cap not honored" "expected exit 3 + 'WIP limit reached' message; got rc=$CLAIM_RC out=$CLAIM_OUT"
fi

# ============================================================================
section "TC5: priority/age work-stream tie-break (sister-pattern to d058 TC2)"
# 2 work-streams with same priority P1. Stream A (PR cluster closes #700+#701) is older.
# Stream B (PR cluster closes #710+#711) is newer. Claim oldest stream → #700.
ready='[
  {"number":710,"title":"newer work-stream B","createdAt":"2026-06-22T10:00:00Z","labels":[{"name":"priority:P1"},{"name":"status:ready"},{"name":"agent:developer"}],"body":""},
  {"number":700,"title":"older work-stream A","createdAt":"2026-06-22T08:00:00Z","labels":[{"name":"priority:P1"},{"name":"status:ready"},{"name":"agent:developer"}],"body":""}
]'
# PR clusters: 700+701 form stream A, 710+711 form stream B (both standalone clusters = 2 streams)
pr_clusters='{"700":"Closes #700 Closes #701","701":"Closes #700 Closes #701","710":"Closes #710 Closes #711","711":"Closes #710 Closes #711"}'
run_claim developer 0 "$ready" "" "$pr_clusters"
if [ "$CLAIM_RC" = "0" ] && echo "$CLAIM_OUT" | grep -q "claimed #700"; then
  pass "older work-stream (#700) claimed first (age tie-break, work-stream-aware)"
elif [ "$CLAIM_RC" = "0" ] && echo "$CLAIM_OUT" | grep -q "claimed #710"; then
  fail "newer work-stream (#710) claimed instead of older (#700)" "age tie-break broken at work-stream level"
else
  fail "unexpected exit/output" "rc=$CLAIM_RC out=$CLAIM_OUT"
fi

# ============================================================================
section "TC6: 0 work-streams with status:ready → exit 1, no claim (work-stream negative)"
# Sister-pattern to d058 TC6 + AC2. 0 ready items = exit 1 regardless of work-stream context.
run_claim developer 0 "EMPTY" ""
if [ "$CLAIM_RC" = "1" ] && echo "$CLAIM_OUT" | grep -q "no ready items"; then
  if grep -q "EDIT" "$CLAIM_LOG" 2>/dev/null; then
    fail "no ready items but script edited an issue" "should NOT edit on negative path"
  else
    pass "work-stream negative path (0 ready items, exit 1, no edit, informative message)"
  fi
else
  fail "work-stream negative path not honored" "expected exit 1 + 'no ready items'; got rc=$CLAIM_RC out=$CLAIM_OUT"
fi

# ============================================================================
section "TC7: work-stream with open dep → filtered out (sister-pattern to d058 TC9)"
# Work-stream A (#800+#801 cluster) has 'depends on #999' (open). Work-stream B (#810 standalone) is dep-free.
# Claim should skip stream A and pick stream B.
ready='[
  {"number":800,"title":"work-stream A with open dep","createdAt":"2026-06-22T08:00:00Z","labels":[{"name":"priority:P0"},{"name":"status:ready"},{"name":"agent:developer"}],"body":"## Problem\nDepends on #999 for upstream schema."},
  {"number":810,"title":"work-stream B dep-free","createdAt":"2026-06-22T09:00:00Z","labels":[{"name":"priority:P0"},{"name":"status:ready"},{"name":"agent:developer"}],"body":"## Problem\nNo external deps."}
]'
pr_clusters='{"800":"Closes #800 Closes #801","801":"Closes #800 Closes #801"}'
run_claim developer 0 "$ready" "999" "$pr_clusters"
if [ "$CLAIM_RC" = "0" ] && echo "$CLAIM_OUT" | grep -q "claimed #810"; then
  if grep -q "EDIT .* 800" "$CLAIM_LOG" 2>/dev/null; then
    fail "script tried to claim #800 (work-stream A, has open dep)" "dep filter missed at work-stream level"
  else
    pass "work-stream with open dep filtered out, dep-free work-stream claimed (try-next worked at WS level)"
  fi
elif [ "$CLAIM_RC" = "0" ] && echo "$CLAIM_OUT" | grep -q "claimed #800"; then
  fail "claimed #800 despite work-stream A having open dep on #999" "dep filter missed"
else
  fail "unexpected exit/output" "rc=$CLAIM_RC out=$CLAIM_OUT"
fi

# ============================================================================
section "TC8: usage error (no role arg) → exit 2"
CLAIM_OUT="$(bash "$CLAIM_SH" 2>&1)"
CLAIM_RC=$?
if [ "$CLAIM_RC" = "2" ] && echo "$CLAIM_OUT" | grep -q "usage:"; then
  pass "missing role → exit 2 + usage message"
else
  fail "usage error not handled" "expected exit 2 + 'usage:'; got rc=$CLAIM_RC out=$CLAIM_OUT"
fi

# ============================================================================
section "TC9: invalid role → exit 2"
run_claim invalid-role 0 "EMPTY" ""
if [ "$CLAIM_RC" = "2" ] && echo "$CLAIM_OUT" | grep -q "invalid role"; then
  pass "invalid role → exit 2 + 'invalid role' message"
else
  fail "invalid role not validated" "expected exit 2 + 'invalid role'; got rc=$CLAIM_RC out=$CLAIM_OUT"
fi

# ============================================================================
section "TC10: audit log written on claim (TC1 follow-up)"
# The script writes to $AUTO_CLAIM_LOG_DIR/auto-claim.log (not appended with
# repo name when AUTO_CLAIM_LOG_DIR is set, per impl §repo_name branch).
audit_log="$TEST_TMPDIR/logs/auto-claim.log"
if [ -f "$audit_log" ]; then
  if grep -q "developer claimed #233" "$audit_log"; then
    pass "audit log entry written (ISO-8601 + role + issue + WIP + priority)"
  else
    fail "audit log present but content wrong" "expected: 'developer claimed #233'; got: $(cat "$audit_log")"
  fi
else
  fail "audit log file not created" "expected: $audit_log"
fi

# ============================================================================
printf "\n${B}==== SUMMARY ====${D}\n"
printf "  ${G}PASS${D}: %d\n" "$PASS"
printf "  ${R}FAIL${D}: %d\n" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo
  echo "d031 REGRESSION FAILED — claim-next-ready.sh contract violated."
  echo "Fix: ensure claim script honors priority sort, age tie-break, dep parser, WIP cap, negative path, and work-stream awareness (TC5/6/7)."
  exit 1
fi
echo
echo "d031 REGRESSION PASS — claim-next-ready.sh (ADR-0038 §Layer 2) contract honored. 10/10 TCs green."
exit 0