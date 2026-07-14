#!/usr/bin/env bash
# d1025-s29-template-agent-wake-hotfix-port.sh — Phase A RED-first d-test on dev-studio-template
#
# Why this test exists
# --------------------
# Sister-template mirror of `atilcan65/AtilCalculator/scripts/tests/d1025-s29-agent-wake-hotfix.sh`
# (PR #1064, Closes #1062). Per ADR-0059 cluster-squash + Issue #93 §Sister-cluster ref,
# this d-test ensures the template-side `scripts/agent-wake.sh` (currently identical broken
# copy from upstream) gets the same 3 fixes applied on the same merge-day, so downstream
# projects bootstrapped from this template don't re-introduce the silent-delivery class
# of bugs that Fix 1/2/3 address.
#
# 3 fixes (Issue #1063 Phase B scope, mirrored on template):
#   Fix 1 — log honesty: replace `|| exit 0` on send-keys with explicit rc
#           check + error log `role=<R> pane=<P> rc=<N>` + exit 1 on failure
#   Fix 2 — pane_id lookup: replace title-match (fragile on descriptive pane
#           titles) with deterministic pane_index lookup via
#           `tmux list-panes -F '#{pane_id} #{pane_index}'` + documented
#           role→index map (orchestrator=0, pm=1, architect=2,
#           developer=3, tester=4, human=5)
#   Fix 3 — capture-pane verify: post-send capture-pane + grep against wake
#           text prefix within 1s timeout; exit 1 on mismatch
#
# TC list (7 per ADR-0049 ≥5 baseline + 1 hygiene + Cadence Rule 1 atomic):
#   TC0 bash -n syntactic self-check (PASS pre/post hygiene)
#   TC1 Fix 1: exit 1 when tmux send-keys fails (mock tmux via PATH shim)
#   TC2 Fix 1: error log line contains role=/pane=/rc= context
#   TC3 Fix 2: orchestrator resolves to dev-studio:0.0 (NOT :main.0)
#   TC4 Fix 2: deterministic 6-role map (incl. human=5)
#   TC5 Fix 3: post-send tmux capture-pane invoked within 1s timeout
#   TC6 Fix 3: capture-pane grep mismatch → exit 1 (verification failure surfaced)
#   TC7 Cadence Rule 1 atomic — template INDEX.md has d1025 row (ADR-0055 §1)
#
# Run: bash scripts/tests/d1025-s29-template-agent-wake-hotfix-port.sh
# Exit: 0 = all pass, 1 = at least one fail.
#
# Sister-pattern: d1025 AtilCalculator side (PR #1064) + d024 + d1024 + d-retro-024 TC6.
# Lane: template-side Phase A d-test. PR base: tester/s29-template-agent-wake-hotfix-port.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAKE_SH="$SCRIPT_DIR/../agent-wake.sh"
INDEX_MD="$SCRIPT_DIR/INDEX.md"

if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; B=""; D=""
fi

PASS=0; FAIL=0
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

# ---------------------------------------------------------------------------
# Mock tmux via PATH shim (single source for all runtime TCs)
# ---------------------------------------------------------------------------
TMPDIR=$(mktemp -d)
MOCK_LOG="$TMPDIR/mock.log"
: > "$MOCK_LOG"

# Unquoted heredoc — ${MOCK_LOG} and ${TMPDIR} expand at write-time (so the
# mock has the absolute log path baked in). \$@ and \$1 stay literal (runtime
# placeholders).
cat > "$TMPDIR/tmux" <<MOCK_EOF
#!/usr/bin/env bash
# Mock tmux for d1025 RED-first testing (template side)
echo "\$@" >> "${MOCK_LOG}"
case "\$1" in
  has-session) exit 0 ;;
  list-panes)
    # Output: pane_id pane_index pane_title (matches Fix 2 expected format)
    echo "dev-studio:0.0 0 orchestrator-pane"
    echo "dev-studio:0.1 1 product-manager-pane"
    echo "dev-studio:0.2 2 architect-pane"
    echo "dev-studio:0.3 3 developer-pane"
    echo "dev-studio:0.4 4 tester-pane"
    echo "dev-studio:0.5 5 human-pane"
    ;;
  send-keys)
    if [ "${MOCK_TMUX_SENDKEYS_FAIL:-0}" = "1" ]; then
      echo "tmux: send-keys failed (mock)" >&2
      exit 1
    fi
    exit 0
    ;;
  capture-pane)
    # -p flag prints to stdout; we capture grep match against wake prefix
    if [ "${MOCK_TMUX_CAPTURE_MATCH:-1}" = "1" ]; then
      echo "🔔 INBOX (dual-channel wake from orchestrator)"
    else
      echo "garbage unrelated output"
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac
MOCK_EOF
chmod +x "$TMPDIR/tmux"

ORIG_PATH="$PATH"
restore_path() { PATH="$ORIG_PATH"; rm -rf "$TMPDIR"; }
trap restore_path EXIT

# ============================================================================
# TC0: bash -n syntactic self-check (PASS pre/post hygiene)
# ============================================================================
section "TC0: agent-wake.sh syntactic self-check (bash -n)"
if ! [ -f "$WAKE_SH" ]; then
  fail "agent-wake.sh missing" "expected $WAKE_SH (refs Issue #93 + Issue #1062)"
elif bash -n "$WAKE_SH" 2>/dev/null; then
  pass "bash -n OK (syntactic self-check)"
else
  fail "bash -n failed" "expected $WAKE_SH to parse without syntax errors"
fi

# ============================================================================
# TC1: Fix 1 — exit 1 when tmux send-keys returns non-zero (log honesty)
# ============================================================================
section "TC1: Fix 1 — send-keys failure → exit 1 (log honesty)"
PATH="$TMPDIR:$ORIG_PATH"
export TMUX_SESSION="dev-studio"
export MOCK_TMUX_SENDKEYS_FAIL=1
export MOCK_TMUX_CAPTURE_MATCH=1
: > "$MOCK_LOG"
set +e
"$WAKE_SH" orchestrator "test message" >"$TMPDIR/stdout" 2>"$TMPDIR/stderr"
rc=$?
set -e
if [ "$rc" = "1" ]; then
  pass "send-keys failure → exit 1 (log honest)"
else
  fail "send-keys failure masked" "expected exit 1 (Fix 1), got exit $rc — current \`|| exit 0\` masks the rc"
fi

# ============================================================================
# TC2: Fix 1 — error log line contains role=/pane=/rc= context
# ============================================================================
section "TC2: Fix 1 — error log contains role=/pane=/rc= context"
stderr_content=$(cat "$TMPDIR/stderr" 2>/dev/null)
if echo "$stderr_content" | grep -qE 'role=' && \
   echo "$stderr_content" | grep -qE 'pane=' && \
   echo "$stderr_content" | grep -qE 'rc='; then
  pass "error log has role=/pane=/rc= context (log honest)"
else
  fail "error log missing context fields" "expected 'role=<R> pane=<P> rc=<N>' in stderr, got: $stderr_content"
fi

# ============================================================================
# TC3: Fix 2 — orchestrator resolves to `dev-studio:0.0` (pane_index, NOT title match)
# ============================================================================
section "TC3: Fix 2 — orchestrator resolves to dev-studio:0.0"
export MOCK_TMUX_SENDKEYS_FAIL=0
: > "$MOCK_LOG"
"$WAKE_SH" orchestrator "test" >/dev/null 2>&1
if grep -qE 'send-keys.*-t.*dev-studio:0\.0\b' "$MOCK_LOG"; then
  pass "orchestrator → dev-studio:0.0 (pane_index 0)"
else
  fail "orchestrator not resolved to dev-studio:0.0" "expected 'send-keys -t dev-studio:0.0' in mock log; got: $(cat "$MOCK_LOG")"
fi

# ============================================================================
# TC4: Fix 2 — deterministic 6-role map (orch=0, pm=1, arch=2, dev=3, test=4, human=5)
# ============================================================================
section "TC4: Fix 2 — deterministic 6-role map (including human=5)"
for role_pair in "orchestrator:0.0" "product-manager:0.1" "architect:0.2" "developer:0.3" "tester:0.4" "human:0.5"; do
  role="${role_pair%:*}"
  expected="${role_pair#*:}"
  : > "$MOCK_LOG"
  "$WAKE_SH" "$role" "test" >/dev/null 2>&1 || true
  if grep -qE "send-keys.*-t.*dev-studio:${expected}\b" "$MOCK_LOG"; then
    pass "$role → dev-studio:$expected"
  else
    fail "$role resolution wrong" "expected dev-studio:$expected in mock log; got: $(cat "$MOCK_LOG")"
  fi
done

# ============================================================================
# TC5: Fix 3 — post-send tmux capture-pane invoked within 1s timeout
# ============================================================================
section "TC5: Fix 3 — post-send tmux capture-pane invoked"
: > "$MOCK_LOG"
start_ns=$(date +%s%N)
"$WAKE_SH" orchestrator "test message" >/dev/null 2>&1 || true
end_ns=$(date +%s%N)
elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
if grep -qE 'capture-pane' "$MOCK_LOG"; then
  pass "capture-pane invoked (elapsed=${elapsed_ms}ms)"
else
  fail "capture-pane NOT invoked" "expected 'capture-pane' in mock log after send-keys; got: $(cat "$MOCK_LOG")"
fi

# ============================================================================
# TC6: Fix 3 — capture-pane grep mismatch → exit 1 (verification failure surfaced)
# ============================================================================
section "TC6: Fix 3 — capture-pane grep mismatch → exit 1"
export MOCK_TMUX_CAPTURE_MATCH=0
: > "$MOCK_LOG"
set +e
"$WAKE_SH" orchestrator "test message" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" = "1" ]; then
  pass "capture-pane mismatch → exit 1 (verification failure surfaced)"
else
  fail "capture-pane mismatch masked" "expected exit 1 on grep mismatch, got exit $rc — current code never calls capture-pane (Fix 3 missing)"
fi

# ============================================================================
# TC7: Cadence Rule 1 atomic — template INDEX.md has d1025 row (ADR-0055 §1)
# ============================================================================
section "TC7: Cadence Rule 1 atomic — template INDEX.md has d1025 row (ADR-0055 §1)"
if grep -qE 'd1025.*-s29-template-agent-wake-hotfix|d1025.*template-agent-wake-hotfix' "$INDEX_MD"; then
  pass "template INDEX.md has d1025 row (Cadence Rule 1 atomic)"
else
  fail "template INDEX.md missing d1025 row" "expected 'd1025' row in template $INDEX_MD per ADR-0055 §1 — file + INDEX.md row must land same commit"
fi

# ============================================================================
# Summary
# ============================================================================
printf "\n${B}==== SUMMARY ====${D}\n"
printf "  ${G}PASS${D}: %d\n" "$PASS"
printf "  ${R}FAIL${D}: %d\n" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
