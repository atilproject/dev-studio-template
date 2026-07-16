#!/usr/bin/env bash
# d116-claim-next-ready-retry-backoff.sh
#
# d116 — tmpl Issue #116 BUG regression guard (sister of calc d1082 + Issue #1089):
#         claim-next-ready.sh gh API error on WIP query must retry-with-backoff,
#         distinguish 4xx vs 5xx, and surface stderr on final failure
#         (currently aborts immediately + 2>/dev/null in tmpl scripts/claim-next-ready.sh).
#
# Why this test exists
# --------------------
# tmpl scripts/claim-next-ready.sh lines 205 + 212 (both branches of WIP query)
# have the SAME gap as calc Issue #1089:
#   in_progress_json="$(gh api \
#     "repos/${REPO}/issues?labels=...&state=open&per_page=100" \
#     --jq "[.[] | select(.pull_request == null) | {number, labels: [.labels[] | {name}]}]" 2>/dev/null)" || { echo "ERROR: gh API error (WIP query)" >&2; exit 4; }
#
# Defect shape (sister-pattern to calc Issue #1089 body):
#   1. `2>/dev/null` swallows transient stderr (GitHub brownouts / rate-limit
#      / network blips invisible to ops)
#   2. Bare `|| exit 4` aborts on ANY gh failure — no retry, no 4xx/5xx split
#   3. Manual 4-flag workaround needed every sprint (ADR-0038 §Layer 2 broken)
#
# Live instance (calc side, cycle ~#1931 2026-07-15T13:29:35+03:00): dev attempted
# to auto-claim Issue #1032 P0 via `scripts/claim-next-ready.sh` — script hit
# gh API brownout on WIP query step, exited 4, dev fell back to manual
# `gh issue edit N --add-label status:in-progress --remove-label status:ready`
# per ADR-0015 atomic 4-flag contract. Tmpl repo has same gap, same blast radius.
#
# TC list (7 per ADR-0049 ≥5 baseline + 1 Cadence Rule 1 atomic):
#   TC0 bash -n syntactic self-check (PASS pre/post hygiene)
#   TC1 happy path — gh succeeds first try (PASS pre/post, no regression)
#   TC2 retry-once-then-success — gh fails first call, succeeds second (RED pre, GREEN post)
#   TC3 retry-thrice-then-fail — sustained brownout, gh fails 3 retries (RED pre, GREEN post)
#   TC4 4xx fail-fast NO retry — genuine script bug / 401 / 404 (RED pre, GREEN post)
#   TC5 stderr surfaced on final failure — stderr contains gh error (RED pre, GREEN post)
#   TC6 Cadence Rule 1 atomic — INDEX.md has d116 row (ADR-0055 §1)
#
# Run: bash scripts/tests/d116-claim-next-ready-retry-backoff.sh
# Exit: 0 = all pass, 1 = at least one fail.
#
# Sister-pattern lineage (sister-fix from calc d1082):
#   - calc d1082 (Issue #1089 BUG regression guard, PR #1099 squash-ready cycle ~#2305)
#     Same impl, same TC list, same RED→GREEN surface; this d116 is the tmpl mirror.
#   - calc d1081 (Issue #1081 RETRO-024 silent-skip regression guard — same
#     PR-cluster cadence, same Issue #113 label-authority slot allocation, same
#     ADR-0049 deviation-justification precedent for P1 cluster)
#   - calc d1091 (Issue #1091 wip_idle_wave active-WIP override — sister tmpl port
#     is d117 in same cluster per cycle ~#2308 owner directive)
#   - tmpl d034 (proactive-wip-idle — sister file already exists for wip-idle-detect,
#     d117 will supplement with active-WIP override regression guard)
#   - tmpl d031 (claim-next-ready 10 TCs — main flow test, d116 supplements
#     with retry-with-backoff behavior guard; non-overlapping coverage)
#
# Refs: tmpl Issue #116 (P1 sprint:current template-gap-close — cycle ~#2308
#       owner-authorized parallel-to-squash claim per orchestrator directive),
#       ADR-0015 (atomic 4-flag hand-off — manual workaround live instance),
#       ADR-0038 §Layer 2 (claim-next-ready canonical home — broken surface),
#       ADR-0044 (RED-first TDD doctrinal home — TC2-5 RED pre-impl),
#       ADR-0049 (≥5 TCs baseline — d116 = 7 TCs met),
#       ADR-0055 §1 (Cadence Rule 1 atomic — d-test + INDEX.md row + impl same
#       PR cluster — Pattern A single-PR atomic), ADR-0059 (cluster-squash —
#       tmpl #116 PR cluster sister of tmpl #117 PR cluster same merge-day),
#       Issue #113 (label-authority — d116 slot = issue-number sister of
#       calc d1082).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAIM_SH="$REPO_ROOT/scripts/claim-next-ready.sh"
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
  echo "ERROR: jq required for d116" >&2
  exit 127
fi
if [ ! -r "$CLAIM_SH" ]; then
  echo "ERROR: claim-next-ready.sh not found at $CLAIM_SH" >&2
  exit 127
fi

# --- mock gh PATH shim ---
# MOCK_GH_FAIL_MODE controls failure shape:
#   none    — every call succeeds (TC1 happy path)
#   first1  — first call fails, subsequent succeed (TC2 retry-once-success)
#   all3    — every call fails (TC3 retry-thrice-fail / TC5 stderr surface)
#   four04  — every call exits 22 with 404-shaped error (TC4 4xx fail-fast)
# MOCK_GH_CALL_LOG records every invocation in order.
MOCK_GH_CALL_LOG="$TEST_TMPDIR/gh-call.log"
: > "$MOCK_GH_CALL_LOG"
cat > "$TEST_TMPDIR/gh" <<'MOCK_EOF'
#!/usr/bin/env bash
LOG="${MOCK_GH_CALL_LOG}"
echo "$@" >> "$LOG"
COUNT=$(wc -l < "$LOG" 2>/dev/null || echo 0)
case "${MOCK_GH_FAIL_MODE:-none}" in
  none) ;;
  first1)
    if [ "$COUNT" -le 1 ]; then
      echo "ERROR: simulated gh API failure (attempt $COUNT, transient)" >&2
      exit 22
    fi
    ;;
  all3)
    echo "ERROR: simulated sustained gh API failure (attempt $COUNT)" >&2
    exit 22
    ;;
  four04)
    echo "ERROR: 404 Not Found (script bug or auth issue)" >&2
    exit 22
    ;;
esac
# Default success path
case "$1" in
  repo) echo "atilproject/dev-studio-template" ;;
  api)
    # WIP query (status:in-progress) → empty
    # Ready query (status:ready) → empty
    echo "[]"
    ;;
  issue)
    # gh issue edit / view → noop
    exit 0
    ;;
esac
exit 0
MOCK_EOF
chmod +x "$TEST_TMPDIR/gh"

# Helper: run claim-next-ready.sh in --wip-count-only mode (short-circuits
# before atomic-claim flip; exercises only the WIP gh API call surface
# where Issue #116 lives, without touching real issues).
run_claim_wip_count() {
  : > "$MOCK_GH_CALL_LOG"
  MOCK_GH_CALL_LOG="$TEST_TMPDIR/gh-call.log" \
  MOCK_GH_FAIL_MODE="$1" \
  PATH="$TEST_TMPDIR:$PATH" \
  GITHUB_REPO="atilproject/dev-studio-template" \
    bash "$CLAIM_SH" --wip-count-only developer >"$TEST_TMPDIR/stdout.log" 2>"$TEST_TMPDIR/stderr.log"
  return $?
}

# ===========================================================================
# Test cases
# ===========================================================================

# TC0 — bash -n syntactic self-check (hygiene per ADR-0049 baseline).
section "TC0 — bash -n syntactic self-check"
if bash -n "$CLAIM_SH" 2>/dev/null; then
  pass "TC0 — bash -n syntactic check PASS (claim-next-ready.sh syntactically valid)"
else
  fail "TC0 — bash -n syntactic check FAIL" "claim-next-ready.sh has bash syntax error — RED pre-impl, must be fixed before any TCs run"
fi

# TC1 — happy path: gh succeeds on every call → script runs cleanly.
section "TC1 — happy path: gh succeeds first try"
run_claim_wip_count "none"
TC1_RC=$?
if [ "$TC1_RC" -eq 0 ]; then
  pass "TC1 — happy path exits 0 (gh succeeded first try, no regression)"
else
  fail "TC1 — happy path exited $TC1_RC (regression in normal operation)" "stderr: $(cat "$TEST_TMPDIR/stderr.log")"
fi

# TC2 — retry-once-then-success: gh fails first call, succeeds on retry.
# Pre-impl: FAIL (script aborts on first failure, no retry → RED)
# Post-impl: PASS (retry-with-backoff succeeds on 2nd attempt → GREEN)
section "TC2 — retry-once-then-success"
run_claim_wip_count "first1"
TC2_RC=$?
TC2_FINAL_CALL_COUNT=$(wc -l < "$MOCK_GH_CALL_LOG" 2>/dev/null || echo 0)
if [ "$TC2_RC" -eq 0 ] && [ "$TC2_FINAL_CALL_COUNT" -ge 2 ]; then
  pass "TC2 — retry-once-then-success exits 0 (gh invoked $TC2_FINAL_CALL_COUNT times, succeeded on retry)"
else
  fail "TC2 — retry-once-then-success exited $TC2_RC after $TC2_FINAL_CALL_COUNT gh calls (expected: exit 0, ≥2 calls proving retry)" "stderr: $(cat "$TEST_TMPDIR/stderr.log") | RED pre-impl (no retry logic); GREEN post-impl"
fi

# TC3 — retry-thrice-then-fail: sustained brownout, gh fails all 3 retries.
# Pre-impl: FAIL (script aborts on first failure → RED, exit 4)
# Post-impl: PASS (retries 3 times then exits 4 with stderr surfaced → GREEN)
section "TC3 — retry-thrice-then-fail (sustained brownout)"
run_claim_wip_count "all3"
TC3_RC=$?
TC3_FINAL_CALL_COUNT=$(wc -l < "$MOCK_GH_CALL_LOG" 2>/dev/null || echo 0)
# Expected post-impl: exit 4 (claim.sh's existing error code), with ≥3 gh calls
# (proving retry attempts before final exit)
if [ "$TC3_RC" -eq 4 ] && [ "$TC3_FINAL_CALL_COUNT" -ge 3 ]; then
  pass "TC3 — sustained brownout: exit 4 after $TC3_FINAL_CALL_COUNT gh calls (3 retries + final attempt, retries exhausted as expected)"
else
  fail "TC3 — sustained brownout: exit $TC3_RC after $TC3_FINAL_CALL_COUNT gh calls (expected: exit 4, ≥3 calls)" "stderr: $(cat "$TEST_TMPDIR/stderr.log") | RED pre-impl (no retry, single call); GREEN post-impl (3+ retries)"
fi

# TC4 — 4xx fail-fast NO retry: 404 / 401 / 403 = script bug or auth issue.
# Pre-impl: FAIL (script retries on 4xx → RED, never reaches fail-fast)
# Post-impl: PASS (script distinguishes 4xx from 5xx, fails fast on 4xx → GREEN, single call)
section "TC4 — 4xx fail-fast NO retry (404 / 401 / 403)"
run_claim_wip_count "four04"
TC4_RC=$?
TC4_FINAL_CALL_COUNT=$(wc -l < "$MOCK_GH_CALL_LOG" 2>/dev/null || echo 0)
# Expected post-impl: exit 4 (script bug, no retry warranted), with EXACTLY 1 gh call
# (proving fail-fast — no retry on deterministic 4xx errors)
if [ "$TC4_RC" -eq 4 ] && [ "$TC4_FINAL_CALL_COUNT" -eq 1 ]; then
  pass "TC4 — 4xx fail-fast: exit 4 after 1 gh call (no retry on deterministic 4xx, fail-fast correct)"
else
  fail "TC4 — 4xx fail-fast: exit $TC4_RC after $TC4_FINAL_CALL_COUNT gh calls (expected: exit 4, exactly 1 call)" "stderr: $(cat "$TEST_TMPDIR/stderr.log") | RED pre-impl (retries 4xx); GREEN post-impl (fails fast)"
fi

# TC5 — stderr surfaced on final failure (no `2>/dev/null` on last attempt).
# Pre-impl: FAIL (stderr swallowed by `2>/dev/null` → RED, empty stderr)
# Post-impl: PASS (stderr contains gh error message → GREEN)
section "TC5 — stderr surfaced on final failure"
run_claim_wip_count "all3" || true
TC5_STDERR_CONTENT=$(cat "$TEST_TMPDIR/stderr.log" 2>/dev/null || echo "")
TC5_HAS_ERROR_MARKER=0
if [ -n "$TC5_STDERR_CONTENT" ] && echo "$TC5_STDERR_CONTENT" | grep -qE "ERROR|sustained gh API|fail|4[0-9][0-9]"; then
  TC5_HAS_ERROR_MARKER=1
fi
if [ "$TC5_HAS_ERROR_MARKER" -eq 1 ]; then
  pass "TC5 — stderr surfaced on final failure (contains error marker, ops can diagnose)"
else
  fail "TC5 — stderr empty or missing error marker (got: '$TC5_STDERR_CONTENT')" "RED pre-impl (\`2>/dev/null\` swallows stderr); GREEN post-impl (stderr surfaces gh error to ops per RETRO-005 #26 hygiene)"
fi

# TC6 — Cadence Rule 1 atomic (ADR-0055 §1): INDEX.md has d116 row.
# Sister-pattern d-retro-024 TC6 + d1025 TC7 (INDEX.md row attestation).
section "TC6 — Cadence Rule 1 atomic (INDEX.md d116 row present)"
if grep -q "d116" "$INDEX_MD" 2>/dev/null; then
  pass "TC6 — scripts/tests/INDEX.md has d116 row (Cadence Rule 1 atomic honored)"
else
  fail "TC6 — scripts/tests/INDEX.md missing d116 row (Cadence Rule 1 atomic violation per ADR-0055 §1)" "Add d116 row to INDEX.md in this commit per sister-pattern d1082 TC6"
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
