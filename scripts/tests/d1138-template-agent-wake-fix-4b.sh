#!/usr/bin/env bash
# d1138-template-agent-wake-fix-4b.sh — Issue #123 / ADR-0066 Fix 4b
#   template forward-port regression guard (lenient capture-pane verify +
#   hierarchical exit code) for scripts/agent-wake.sh.
#
# Why this test exists
# --------------------
# Sister-pattern of AtilCalculator d1138 (scripts/tests/d1138-agent-wake-fix-4b-
# lenient-verify.sh, PR #1140 MERGED b0012d6 20:03:11Z). AtilCalculator Issue
# #1138 documents the same 6 cycles (2855, 2857, 2858×2, 2861) where
# scripts/agent-wake.sh's Fix 3 verify produced FALSE failures on the tmpl
# repo too (evidence: Issue #123 cycle ~#2912 KAPI-residual live evidence on
# `scripts/peer-poke.sh` capture-pane verify RC=1 mismatch).
#
# Fix 4b (ADR-0066) addresses this with three additive changes:
#   D1: `WAKE_VERIFY_TIMEOUT_SEC` env override (default 3s, was hardcoded 1s)
#   D2: `VERIFY_SENTINEL="🔔 INBOX (dual-c"` — 16-char literal, was dynamic MSG_PREFIX
#   D3: Hierarchical exit codes (verify OK = exit 0; verify FAIL = exit 0 + WARN;
#       send-keys FAIL = exit 1 + ERROR)
#   D4: WARN vs ERROR log discrimination (owner-greppable audit)
#
# Test framework: bash + grep + fake tmux in PATH (d862 sister-pattern).
# ADR-0044 RED-first TDD: pre-impl on tmpl main HEAD expected to FAIL on TC1-TC4.
# TC5 + TC6 are regression guards that PASS today and MUST continue to PASS
# post-Fix-4b (preserved behavior). Post-impl expected: all 6 TCs GREEN.
#
# Template-specific notes (vs AtilCalculator d1138):
# - Target file: scripts/agent-wake.sh (no .tmpl suffix in tmpl repo; root-level
#   *.tmpl is for rendered output, not shell scripts in scripts/)
# - Path resolution: $REPO_ROOT/scripts/agent-wake.sh
# - Fake tmux output format: same as calc (`%0 ${TMUX_PANE_INDEX_OVERRIDE:-0}`)
# - INDEX.md registration: tmpl-local per RETRO-008 §11 + d081/s29-005 pattern
#   (AtilCalculator has its own INDEX row, this is sister-side)
# - Cadence Rule 1 atomic per ADR-0055 §1: this file + INDEX.md row same commit
#
# Sister-pattern lineage:
#   - d1138 (AtilCalculator/scripts/tests/d1138-agent-wake-fix-4b-lenient-verify.sh
#     — DIRECT sister, byte-identical test design)
#   - d024-agent-wake.sh (tmpl/scripts/tests/d024-agent-wake.sh — pre-existing
#     ADR-0033 dual-channel wake regression test, 7 TCs, grep-assertion idiom)
#   - d862 (Issue #862 RCA fake-gh-in-PATH pattern)
#   - d068b (Issue #935 WAKE_KEYS_GAP_SEC env override naming convention)
#   - d058 (claim-next-ready fake-gh factory)
#
# Refs: Issue #123 (tmpl forward-port coord, Closes via PR merge), AtilCalculator
#       Issue #1138 (origin), ADR-0066 (Fix 4b doctrinal basis), ADR-0033
#       (dual-channel doctrine), ADR-0044 (RED-first TDD), ADR-0049 (d-test
#       framework ≥5 baseline), ADR-0055 §1 (Cadence Rule 1 atomic),
#       ADR-0057 (Closes anchor strict format), ADR-0059 (cluster-squash).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WAKE_SH="${REPO_ROOT}/scripts/agent-wake.sh"

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
skip() { printf "  ${Y}○ SKIP${D} — %s\n" "$1"; }

# Pre-flight
command -v bash >/dev/null 2>&1 || { echo "ERROR: bash required for d1138-tmpl" >&2; exit 127; }
command -v timeout >/dev/null 2>&1 || { echo "ERROR: GNU 'timeout' (coreutils) required for d1138-tmpl" >&2; exit 127; }
[ -f "$WAKE_SH" ] || { echo "ERROR: agent-wake.sh not found at $WAKE_SH" >&2; exit 127; }

# Sentinel per ADR-0066 §D2 (literal 16 chars / 19 bytes UTF-8; "🔔" = 4 bytes)
SENTINEL='🔔 INBOX (dual-c'

# Setup test workspace
TEST_TMPDIR="$(mktemp -d /tmp/d1138-tmpl-XXXXXX)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAKE_BIN="$TEST_TMPDIR/bin"
mkdir -p "$FAKE_BIN"

# ---------------------------------------------------------------------------
# Fake tmux — supports has-session, list-panes, send-keys, capture-pane.
# Logs every invocation (with relevant env state) to $TMUX_LOG_FILE so behavioral
# assertions (TC1) can verify which `timeout` value was passed to capture-pane.
# ---------------------------------------------------------------------------
cat > "$FAKE_BIN/tmux" <<'FAKE_TMUX_EOF'
#!/usr/bin/env bash
LOG="${TMUX_LOG_FILE:-/dev/null}"
printf 'tmux-invocation: %s (TMUX_SEND_FAIL=%s, VERIFY_RESULT=%s)\n' \
  "$*" "${TMUX_SEND_FAIL:-unset}" "${VERIFY_RESULT:-MATCH}" >> "$LOG"
case "$1" in
  has-session)
    # TC5 regression: signal "no tmux session" if requested
    [ -z "${TMUX_SESSION_MISSING:-}" ] && exit 0 || exit 1
    ;;
  list-panes)
    # Return pane with index controlled by TMUX_PANE_INDEX_OVERRIDE (default 0).
    # The d-test sets this to the role's expected pane_index (tester=4 per
    # scripts/dev-studio-start.sh layout: orchestrator=0, ... tester=4, human=5)
    # so the production script's `awk '$2 == idx { print $1; exit }'`
    # filter matches our fake pane.
    PANE_IDX="${TMUX_PANE_INDEX_OVERRIDE:-0}"
    echo "%0 $PANE_IDX"
    exit 0
    ;;
  send-keys)
    # capture subcommand sentinel: if msg starts with '-l ' OR has 'Enter' arg
    # we don't need it — just exit 0 unless TMUX_SEND_FAIL signals failure
    if [ -n "${TMUX_SEND_FAIL:-}" ]; then
      exit "$TMUX_SEND_FAIL"
    fi
    exit 0
    ;;
  capture-pane)
    # TC3/TC4: VERIFY_RESULT controls whether pane content matches sentinel
    if [ "${VERIFY_RESULT:-MATCH}" = "MATCH" ]; then
      printf '\033[1;33m%s test wake message d1138-tmpl\033[0m\n' "$VERIFY_SENTINEL_OVERRIDE:-🔔 INBOX (dual-c"
    else
      printf 'unrelated terminal content with no sentinel substring here at all\n'
    fi
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
FAKE_TMUX_EOF
chmod +x "$FAKE_BIN/tmux"

# Helper: invoke scripts/agent-wake.sh with the fake tmux + controlled env.
# Args: <verify_result> <tmux_send_fail> <msg>
run_wake_capture() {
  local verify_result="$1"
  local send_fail="$2"
  local msg="$3"
  local rc_file="$TEST_TMPDIR/last_rc"
  local stderr_file="$TEST_TMPDIR/last_stderr"
  local stdout_file="$TEST_TMPDIR/last_stdout"
  local tmux_log="$TEST_TMPDIR/last_tmux.log"
  rm -f "$rc_file" "$stderr_file" "$stdout_file" "$tmux_log"
  (
    export PATH="$FAKE_BIN:$PATH"
    export TMUX_LOG_FILE="$tmux_log"
    export VERIFY_RESULT="$verify_result"
    export TMUX_SEND_FAIL="$send_fail"
    # d1138-tmpl invokes script with role=tester; tmpl scripts/dev-studio-start.sh
    # layout has tester at pane_index=4. Without this override, fake tmux returns
    # pane_index=0 (default) which won't match `awk '$2 == 4'` filter and the
    # production script exits at the pane-lookup block with "pane lookup failed"
    # BEFORE reaching the verify block.
    export TMUX_PANE_INDEX_OVERRIDE=4
    "$WAKE_SH" tester "$msg" >"$stdout_file" 2>"$stderr_file"
    echo "$?" > "$rc_file"
  )
}

# ============================================================================
# TC1: WAKE_VERIFY_TIMEOUT_SEC env override honored (D1)
# ============================================================================
section "TC1: WAKE_VERIFY_TIMEOUT_SEC env override applied (sister-pattern d068b)"
# Set WAKE_VERIFY_TIMEOUT_SEC=99 (unambiguous non-default), invoke script, check
# that fake tmux's capture-pane invocation was called with `timeout 99`.
# Pre-Fix-4b: tmpl script hardcodes `timeout 1` → log shows `timeout 1` → FAIL (RED).
# Post-Fix-4b: env override honored → log shows `timeout 99` → PASS (GREEN).
TMUX_LOG="$TEST_TMPDIR/tc1_tmux.log"
rm -f "$TMUX_LOG"
(
  export PATH="$FAKE_BIN:$PATH"
  export TMUX_LOG_FILE="$TMUX_LOG"
  export VERIFY_RESULT=MATCH
  export TMUX_PANE_INDEX_OVERRIDE=4
  export WAKE_VERIFY_TIMEOUT_SEC=99
  "$WAKE_SH" tester "🔔 INBOX (dual-c TC1 env-override scenario d1138-tmpl cycle ~#2924" >/dev/null 2>&1
)
if [ ! -s "$TMUX_LOG" ]; then
  fail "TC1 — fake tmux log empty (test harness misconfigured)" \
    "expected: tmux invocations logged to $TMUX_LOG; current: empty (FAKE_BIN/tmux not invoked)"
elif grep -qE 'timeout 99' "$TMUX_LOG"; then
  pass "TC1 — WAKE_VERIFY_TIMEOUT_SEC=99 honored (capture-pane called with 'timeout 99')"
else
  TIMEOUT_SEEN=$(grep -oE 'timeout [0-9]+' "$TMUX_LOG" | head -1 || echo "(no timeout match)")
  fail "TC1 — WAKE_VERIFY_TIMEOUT_SEC env NOT honored (log shows '$TIMEOUT_SEEN')" \
    "expected: log shows 'timeout 99' (post-Fix-4b env override per ADR-0066 D1); current: '$TIMEOUT_SEEN' (RED — pre-Fix-4b hardcodes timeout 1)"
fi

# ============================================================================
# TC2: VERIFY_SENTINEL=16 chars literal present in script (D2, static-grep)
# ============================================================================
section "TC2: VERIFY_SENTINEL='🔔 INBOX (dual-c' literal in script (no MSG derivation)"
# ADR-0066 §D2 mandates a hardcoded 16-char sentinel. Static-grep on tmpl
# scripts/agent-wake.sh — the script MUST contain the literal sentinel as a
# constant, not derive it from MSG.
# Pre-Fix-4b: dynamic MSG_PREFIX derivation → no sentinel constant → FAIL (RED).
# Post-Fix-4b: VERIFY_SENTINEL="🔔 INBOX (dual-c" present → PASS (GREEN).
EXPECTED_LITERAL='VERIFY_SENTINEL="🔔 INBOX (dual-c"'
if grep -qF "$EXPECTED_LITERAL" "$WAKE_SH"; then
  pass "TC2 — VERIFY_SENTINEL literal '$SENTINEL' present in scripts/agent-wake.sh (D2 sentinel-based match)"
else
  fail "TC2 — VERIFY_SENTINEL literal '$SENTINEL' NOT in scripts/agent-wake.sh (uses dynamic MSG_PREFIX)" \
    "expected: literal '$EXPECTED_LITERAL' in scripts/agent-wake.sh (post-Fix-4b D2 sentinel); current: dynamic MSG_PREFIX derivation (RED — Fix 4b impl pending on tmpl)"
fi
# Sanity: the old dynamic MSG_PREFIX derivation block (Fix 3) must be REMOVED
# post-Fix-4b (D2 drops it). Pre-Fix-4b has the block; post-Fix-4b does not.
# This sub-check is RED-today and GREEN-post-impl (inverse of TC2 main).
# Use grep -qF (fixed-string) with the unambiguous substring `MSG_PREFIX="${MSG%%`
# — present only in Fix 3 dynamic derivation, absent after D2 sentinel switch.
if grep -qF 'MSG_PREFIX="${MSG%%' "$WAKE_SH"; then
  fail "TC2.old-prefix-removed — old Fix 3 MSG_PREFIX derivation block still present (must be removed post-Fix-4b)" \
    "expected: no MSG_PREFIX dynamic derivation (D2 replaces with sentinel); current: Fix 3 derivation still in tmpl script (RED — Fix 4b impl pending on tmpl)"
else
  pass "TC2.old-prefix-removed — old MSG_PREFIX derivation removed (D2 sentinel-only)"
fi

# ============================================================================
# TC3: send-keys OK + verify OK → exit 0 (preserved happy path)
# ============================================================================
section "TC3: send-keys OK + verify OK → exit 0 (happy-path preserved)"
# Setup: VERIFY_RESULT=MATCH → fake pane contains the sentinel → verify matches.
# Message is ~138 chars (MSG_PREFIX pre-Fix-4b = first 80 chars), pane content
# is ~35 chars. The 80-char MSG_PREFIX substring is NOT in the 35-char pane, but
# the 16-char sentinel IS. Pre-Fix-4b greps MSG_PREFIX → no match → exit 1
# (RED — false failure). Post-Fix-4b greps sentinel → match → exit 0 (GREEN).
TC3_MSG="🔔 INBOX (dual-c TC3 verify-OK scenario d1138-tmpl cycle ~#2924 this message is intentionally long so its first 80-char prefix differs from the 16-char sentinel — pre-Fix-4b fails, post-Fix-4b matches"
run_wake_capture "MATCH" "" "$TC3_MSG"
TC3_RC=$(cat "$TEST_TMPDIR/last_rc" 2>/dev/null || echo "99")
TC3_STDERR=$(cat "$TEST_TMPDIR/last_stderr" 2>/dev/null || echo "")
TC3_STDOUT=$(cat "$TEST_TMPDIR/last_stdout" 2>/dev/null || echo "")

if [ "$TC3_RC" = "0" ]; then
  pass "TC3 — send-keys OK + verify OK → exit 0 (happy-path preserved post-Fix-4b)"
else
  fail "TC3 — verify-OK path did NOT exit 0 (rc=$TC3_RC)" \
    "expected: rc=0 (sentinel matched, no false failure); current: rc=$TC3_RC (RED — pre-Fix-4b greps MSG_PREFIX which doesn't appear in fixture pane)"
fi
if ! printf '%s\n%s' "$TC3_STDOUT" "$TC3_STDERR" | grep -qE 'WARN:|ERROR:'; then
  pass "TC3.stderr — clean (no WARN/ERROR on verify-OK happy path)"
else
  fail "TC3.stderr — WARN/ERROR on verify-OK happy path (unexpected)" \
    "expected: clean stderr; current: $TC3_STDERR $TC3_STDOUT"
fi
if printf '%s' "$TC3_STDOUT" | grep -qE 'Wake verified:'; then
  pass "TC3.stdout — 'Wake verified' signature present (success log)"
else
  fail "TC3.stdout — missing 'Wake verified:' on verify-OK happy path" \
    "expected: stdout contains 'Wake verified: role=tester pane='; current: $TC3_STDOUT"
fi

# ============================================================================
# TC4: send-keys OK + verify FAIL → exit 0 + WARN (D3 hierarchical leniency)
# ============================================================================
section "TC4: send-keys OK + verify FAIL → exit 0 + WARN (hierarchical leniency, D3+D4)"
# Setup: VERIFY_RESULT=NOMATCH → pane has no sentinel → verify fails.
# Pre-Fix-4b: greps MSG_PREFIX, no match → exit 1 (RED — wrong exit code).
# Post-Fix-4b D3: verify-fail is LENIENT (exit 0 + WARN stderr), since send-keys
# succeeded and dual-channel GitHub artefact path (ADR-0033) is the primary wake.
TC4_MSG="🔔 INBOX (dual-c TC4 verify-FAIL scenario d1138-tmpl cycle ~#2924 verify should fail here because pane has no sentinel — pre-Fix-4b returns rc=1, post-Fix-4b returns rc=0+WARN"
run_wake_capture "NOMATCH" "" "$TC4_MSG"
TC4_RC=$(cat "$TEST_TMPDIR/last_rc" 2>/dev/null || echo "99")
TC4_STDERR=$(cat "$TEST_TMPDIR/last_stderr" 2>/dev/null || echo "")
TC4_STDOUT=$(cat "$TEST_TMPDIR/last_stdout" 2>/dev/null || echo "")

if [ "$TC4_RC" = "0" ]; then
  pass "TC4 — verify-FAIL path returns rc=0 (lenient, send-keys OK + verify uncertain → exit 0 per D3)"
else
  fail "TC4 — verify-FAIL did NOT return rc=0 (rc=$TC4_RC, D3 hierarchical leniency broken)" \
    "expected: rc=0 (lenient per ADR-0066 D3 hierarchical exit); current: rc=$TC4_RC (RED — pre-Fix-4b treats verify-fail as hard fail rc=1)"
fi
if printf '%s' "$TC4_STDERR" | grep -qE 'WARN: Wake injected but verify uncertain'; then
  pass "TC4.stderr — WARN signature present on verify-FAIL ('WARN: Wake injected but verify uncertain')"
else
  fail "TC4.stderr — WARN signature missing on verify-FAIL (D4 log discrimination broken)" \
    "expected: stderr contains 'WARN: Wake injected but verify uncertain'; current: $TC4_STDERR (RED — pre-Fix-4b has no WARN tier)"
fi
# Must NOT have a send-keys ERROR (that's reserved for D3 hard-fail path)
if ! printf '%s' "$TC4_STDERR" | grep -qE 'ERROR: send-keys returned'; then
  pass "TC4.no-error — no send-keys ERROR on verify-FAIL (D3 error tier preserved for hard-fail only)"
else
  fail "TC4.no-error — send-keys ERROR wrongly emitted on verify-FAIL path" \
    "expected: no send-keys ERROR (verify-fail ≠ send-keys-fail per D3); current: $TC4_STDERR (D3 tier discrimination broken)"
fi

# ============================================================================
# TC5: send-keys FAIL → exit 1 + ERROR (regression guard, D3 preserved)
# ============================================================================
section "TC5: send-keys FAIL → exit 1 + ERROR (regression guard, D3 hard-fail path)"
# Setup: TMUX_SEND_FAIL=1 → fake send-keys returns rc=1. Script's send-keys check
# catches the rc and exits 1 + ERROR.
# Both pre-Fix-4b and post-Fix-4b MUST return rc=1 + ERROR (preserved path).
# Pre-Fix-4b: PASSES today. Post-Fix-4b: MUST still PASS (D3 hard-fail preserved).
# This is a regression guard, not a RED-first test — it constrains the impl to
# preserve the existing send-keys FAIL semantics across the D1-D4 changes.
TC5_MSG="🔔 INBOX (dual-c TC5 send-keys-FAIL scenario d1138-tmpl cycle ~#2924"
run_wake_capture "MATCH" "1" "$TC5_MSG"
TC5_RC=$(cat "$TEST_TMPDIR/last_rc" 2>/dev/null || echo "99")
TC5_STDERR=$(cat "$TEST_TMPDIR/last_stderr" 2>/dev/null || echo "")

if [ "$TC5_RC" = "1" ]; then
  pass "TC5 — send-keys FAIL → exit 1 (D3 hard-fail path preserved)"
else
  fail "TC5 — send-keys FAIL did NOT exit 1 (rc=$TC5_RC, D3 hard-fail path broken)" \
    "expected: rc=1 (send-keys hard fail per D3); current: rc=$TC5_RC (REGRESSION — Fix 4b must preserve this path)"
fi
if printf '%s' "$TC5_STDERR" | grep -qE 'ERROR: send-keys returned'; then
  pass "TC5.stderr — ERROR signature present on send-keys FAIL ('ERROR: send-keys returned')"
else
  fail "TC5.stderr — ERROR signature missing on send-keys FAIL" \
    "expected: stderr contains 'ERROR: send-keys returned'; current: $TC5_STDERR"
fi
# Must NOT have a WARN (that's reserved for verify-uncertain path, not send-keys fail)
if ! printf '%s' "$TC5_STDERR" | grep -qE 'WARN: Wake injected but verify uncertain'; then
  pass "TC5.no-warn — no verify WARN on send-keys FAIL (D3+D4 tier separation preserved)"
else
  fail "TC5.no-warn — verify WARN wrongly emitted on send-keys FAIL path" \
    "expected: no verify WARN (D3 only emits WARN when send-keys OK); current: $TC5_STDERR"
fi

# ============================================================================
# TC6: bash -n syntactic validity + shellcheck baseline (ADR-0049 baseline)
# ============================================================================
section "TC6: bash -n syntactic validity (ADR-0049 baseline + shellcheck bonus)"
# Mandatory baseline per ADR-0049 ≥3 baseline check: script must parse cleanly.
# Both pre-Fix-4b and post-Fix-4b PASS (script syntax preserved across D1-D4).
# Optional bonus: shellcheck if installed.
if bash -n "$WAKE_SH" 2>/dev/null; then
  pass "TC6 — bash -n syntactic validity (script parses cleanly, syntax preserved across Fix 4b)"
else
  fail "TC6 — bash -n failed (script has syntax errors post-Fix-4b)" \
    "expected: bash -n exit 0 (Fix 4b impl must preserve script syntax); current: parse error"
fi
if command -v shellcheck >/dev/null 2>&1; then
  SHELLCHECK_OUTPUT="$(shellcheck "$WAKE_SH" 2>&1 || true)"
  if [ -z "$SHELLCHECK_OUTPUT" ]; then
    pass "TC6.shellcheck — shellcheck clean (bonus baseline, no warnings)"
  else
    # Non-blocking — shellcheck warnings are not failures, just diagnostics
    printf "  ${Y}⚠ WARN${D} — TC6.shellcheck reported issues (non-blocking diagnostics):\n"
    printf '%s\n' "$SHELLCHECK_OUTPUT" | sed 's/^/      /'
    printf "  ${Y}○ SKIP${D} — TC6.shellcheck (issues noted but not failing; baseline tc is bash -n only)\n"
  fi
else
  skip "TC6.shellcheck (shellcheck not installed, optional baseline)"
fi

# ============================================================================
# Summary
# ============================================================================
printf "\n${B}==== SUMMARY (d1138-tmpl — Issue #123 / ADR-0066 Fix 4b tmpl forward-port) ====${D}\n"
printf "  ${G}PASS${D}: %d\n" "$PASS"
printf "  ${R}FAIL${D}: %d\n" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf "  ${R}Failures${D}:\n"
  for f in "${FAILURES[@]}"; do
    printf "    - %s\n" "$f"
  done
  printf "\n${R}RED state confirmed${D} — Fix 4b tmpl impl in scripts/agent-wake.sh required (developer lane).\n"
  printf "  Action: developer opens tmpl impl PR per Cycle ~#2924 orchestrator directive (cluster ordering:\n"
  printf "    arch tmpl ADR-0066 sister PR → tester tmpl d1138-tmpl d-test sister PR [this PR] →\n"
  printf "    dev tmpl impl sister PR).\n"
  exit 1
fi
printf "\n${G}GREEN state confirmed${D} — Fix 4b lenient verify + hierarchical exit + sentinel all working.\n"
exit 0
