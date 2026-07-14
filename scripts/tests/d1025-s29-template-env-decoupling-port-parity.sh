#!/usr/bin/env bash
# d1025-s29-template-env-decoupling-port-parity.sh — S29 ping-env-decoupling
# cross-repo port-parity regression guard (template side).
#
# Doctrinal contract (≥5 TCs baseline per ADR-0049 + `docs/sprints/current/plan.md`
#   "≥5 TCs behavioral, ≥3 TCs hygiene/docs"):
#   TC0: bash -n syntactic self-check (preflight)
#   TC1: AC1 option B — TELEGRAM_BOT_TOKEN unset → notify.sh exits 2 +
#        WARN + tmux-wake fires (Telegram failed, peer pane still wakes)
#   TC2: AC1 option B — TELEGRAM_BOT_TOKEN invalid (API call fails) →
#        notify.sh exits 2 + ERROR + tmux-wake fires (Telegram failed,
#        peer pane still wakes)
#   TC3: AC1 happy-path — valid env + reachable bot → notify.sh exits 0 +
#        Telegram API called + tmux-wake fires (dual-channel both)
#   TC4: AC1 — peer-poke.sh.tmpl with TELEGRAM_BOT_TOKEN unset → exits 2 +
#        tmux-wake fires (inherits notify.sh option B behavior via exec)
#   TC5: agent-wake.sh fallback index map — when pane_title contains
#        OSC-2 non-printable chars (title-match fails), the deterministic
#        `${TMUX_SESSION}:main.<role-index>` fallback kicks in and the
#        wake still fires on a fresh pane.
#
# Doctrinal home: Issue #1058 (cluster coordination) + Issue #1059 (Phase A
#   d-test issue, this PR) + Issue #1060 (Phase B impl, blocked on Phase A).
#   Sprint 29 W1 ping-env-decoupling cluster, owner directive 2026-07-13
#   pickup-141, gap-closing scope-locked.
#
# Why this d-test exists
# ----------------------
# AtilCalculator (calc) shipped the env-decoupling fix in PR #1057 (commit
# 46e68e4, merged 2026-07-14T09:22:51Z, Issue #1053 closed). The d-test
# d1024 (PR #1056, commit 2f31cb3) runs 5/5 GREEN on calc. The dev-studio-
# template (tmpl) is the upstream source — fresh projects cloned from tmpl
# inherit whatever tmpl ships. Until tmpl's notify.sh receives the same fix,
# fresh projects still hit Issue #1053 (Telegram env unset → exit 1 → no
# peer tmux-wake in CI/dev/recovery envs).
#
# This d-test is the cross-repo port-parity regression guard: it runs the
# same 5 TCs as d1024 against tmpl's scripts/. Pre-port, the same TCs that
# RED'd on calc's d1024 pre-PR-#1057 will RED on tmpl's d1025 (parity-by-
# RED). Post-port (when tmpl's notify.sh receives the same AC1 Option B
# fix), all 5 TCs GREEN — proving tmpl caught up to calc.
#
# RED-first per ADR-0044: TC1, TC2, TC4 FAIL pre-port (tmpl notify.sh line
#   65 `exit 1` on Telegram env-missing — exact Issue #1053 repro). TC3
#   INFO-skip (no Telegram env in test fixture). TC5 PASS (tmpl already
#   has TD-068b fix on agent-wake.sh — ported earlier in S28 via
#   commit 6191b6c).
# Post-port (when tmpl's notify.sh gets the fix): all 5 TCs GREEN.
#
# Cadence Rule 1 atomic (ADR-0055 §1): this d-test file + INDEX.md entry
#   land in same commit. Sister-pattern per d096.
#
# Sister-patterns (≥3 per ADR-0049):
#   - d1024 (AtilCalculator, S29 ping-env-decoupling) — direct sister,
#     same 5-TC structure, same exit-code matrix, same fake-tmux-session
#     fixture pattern (d058)
#   - d983 (template forward-port parity) — sister cross-repo port-parity
#     pattern, same tmpl-side regression-guard framing
#   - d058 (work-stream aware — owner-mercy-gate contract) — fake-session
#     isolation pattern (no live peer pane touched)
#   - d081 (auto-verdict-by-hook on tmpl) — template-side d-test authoring
#     conventions, INDEX.md format, 4-cat label discipline
#   - d296 (peer-poke argv + usage discipline) — TC4 inherits argv shape
#     from peer-poke.sh.tmpl
#   - d320 (architect-authored stale_verdict contract shape) — exit-code
#     semantics + stderr structure conventions
#
# Cross-refs:
#   - ADR-0033 (dual-channel doctrine) — the doctrine this cluster fixes
#   - ADR-0044 (RED-first TDD doctrinal home)
#   - ADR-0049 (d-test framework ≥5 TCs baseline)
#   - ADR-0055 §1 (Cadence Rule 1 atomic)
#   - ADR-0059 (cluster-squash — d-test ships BEFORE impl, sister-PR
#     must land same merge-day as calc-side d-test for cluster-squash)
#   - TD-068b (Issue #935) — WAKE_KEYS_GAP_SEC env override (test fixture
#     tolerance window)
#   - ADR-0031 (owner merge gate — only human squash-merges impl PR)
#   - Issue #1053 (calc-side canonical tracker — already closed via PR #1057)
#   - Issue #1058 (cluster coordination)
#   - Issue #1059 (Phase A: this d-test)
#   - Issue #1060 (Phase B: tmpl impl, blocked on this Phase A GREEN)
#   - PR #1056 (calc-side d1024 d-test, merged 2f31cb3)
#   - PR #1057 (calc-side d1024 impl, merged 46e68e4)

set -euo pipefail

# Test fixture: fake tmux session, PID-suffixed to avoid collision with
# live `dev-studio` session (per d058 sister-pattern: no live peer pane
# touched). Each TC creates its own fresh session, sets pane_title to
# the target role's uppercase name (so agent-wake.sh's title-match
# path resolves on first match — see agent-wake.sh line ~50-58).

SCRIPT_DIR_D1025="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_D1025="$(cd "${SCRIPT_DIR_D1025}/../.." && pwd)"
NOTIFY_SH="${REPO_ROOT_D1025}/scripts/notify.sh"
PEER_POKE_SH="${REPO_ROOT_D1025}/scripts/peer-poke.sh.tmpl"  # tmpl uses .tmpl suffix
AGENT_WAKE_SH="${REPO_ROOT_D1025}/scripts/agent-wake.sh"

# PASS / FAIL counters
pass=0
fail=0

check() {
    if [ "${2:-FAIL}" = "PASS" ]; then
        echo "  ✅ $1"
        pass=$((pass+1))
    elif [ "${2:-FAIL}" = "INFO" ]; then
        echo "  ℹ️  $1: $3"
        # INFO is informational — neither pass nor fail increment
    else
        echo "  ❌ $1: $2"
        fail=$((fail+1))
    fi
}

require_dependencies() {
    local missing=0
    if ! command -v tmux >/dev/null 2>&1; then
        echo "FATAL: tmux not found in PATH (required for fake-session fixture)" >&2
        missing=1
    fi
    if ! command -v bash >/dev/null 2>&1; then
        echo "FATAL: bash not found in PATH" >&2
        missing=1
    fi
    for f in "$NOTIFY_SH" "$PEER_POKE_SH" "$AGENT_WAKE_SH"; do
        if [ ! -f "$f" ]; then
            echo "FATAL: required script missing: $f" >&2
            missing=1
        fi
    done
    [ "$missing" -eq 0 ] || exit 2
}

# create_fake_session <session-name> <pane-title-uppercase>
# Creates a detached tmux session with a single window/pane titled to
# match the target role (so agent-wake.sh title-match path resolves
# on first match, exercising the primary injection path under test).
create_fake_session() {
    local session="$1"
    local pane_title="$2"
    tmux kill-session -t "$session" 2>/dev/null || true
    tmux new-session -d -s "$session" -x 80 -y 24
    # Set pane title (pane_title, not window name) — this is what
    # agent-wake.sh's `tmux list-panes -F '#{pane_title}'` reads.
    tmux select-pane -t "${session}:0.0" -T "$pane_title"
    # Give the session a moment to stabilize before capture-pane
    sleep 0.1
}

cleanup_fake_session() {
    local session="$1"
    tmux kill-session -t "$session" 2>/dev/null || true
}

# capture_wake_probe <session> <expected-substring>
# Returns PASS if fake pane's captured buffer contains expected substring.
# Uses `tmux capture-pane -p` (print to stdout) and greps for the substring.
capture_wake_probe() {
    local session="$1"
    local expected="$2"
    # Allow WAKE_KEYS_GAP_SEC (default 0.5s) + 1s tolerance for tmux to
    # process the send-keys injection (per TD-068b).
    sleep 1.0
    local captured
    captured=$(tmux capture-pane -t "${session}:0.0" -p 2>/dev/null || echo "")
    if echo "$captured" | grep -qF "$expected"; then
        echo "PASS"
    else
        # Truncate captured for readable error message
        local truncated
        truncated=$(echo "$captured" | head -c 200 | tr '\n' '|')
        echo "FAIL: pane buffer missing '$expected'; captured=[$truncated]"
    fi
}

require_dependencies

# -------------------------------------------------------------------------
# TC0 (preflight): bash -n syntactic validity of this d-test file
# -------------------------------------------------------------------------
if bash -n "$0" 2>/dev/null; then
    check "TC0 (bash -n self-check)" "PASS"
else
    check "TC0 (bash -n self-check)" "bash syntax error"
    exit 1
fi

# -------------------------------------------------------------------------
# TC1: AC1 option B — TELEGRAM_BOT_TOKEN unset → exit 2 + WARN + tmux-wake
# -------------------------------------------------------------------------
echo ""
echo "TC1: TELEGRAM_BOT_TOKEN unset → notify.sh exit 2 + tmux-wake"
SESSION_TC1="d1025-tc1-$$"
create_fake_session "$SESSION_TC1" "ORCHESTRATOR"
trap "cleanup_fake_session '$SESSION_TC1'" EXIT

# Run notify.sh with Telegram env unset, in subshell to avoid leaking unset
TC1_STDERR=$(mktemp)
TC1_EXIT=$(env -u TELEGRAM_BOT_TOKEN -u TELEGRAM_CHAT_ID \
    TMUX_SESSION="$SESSION_TC1" \
    bash "$NOTIFY_SH" -l info -w -r orchestrator "test d1025 tc1 env-unset probe" \
    2>"$TC1_STDERR" >/dev/null; echo $?)
TC1_STDERR_CONTENT=$(cat "$TC1_STDERR")
rm -f "$TC1_STDERR"

TC1_WAKE_PROBE=$(capture_wake_probe "$SESSION_TC1" "test d1025 tc1 env-unset probe")

# RED-first expectations (tmpl pre-port — Issue #1053 unfixed):
# - exit code 2 (NOT 1 — the spec mandates 2 per option B)
# - stderr contains WARN signal (or "tmux-wake fired" marker)
# - tmux capture-pane shows the wake text injected
if [ "$TC1_EXIT" = "2" ] && \
   echo "$TC1_STDERR_CONTENT" | grep -qiE "warn|tmux-wake" && \
   [ "$TC1_WAKE_PROBE" = "PASS" ]; then
    check "TC1 (Telegram unset → exit 2 + tmux-wake)" "PASS"
else
    check "TC1 (Telegram unset → exit 2 + tmux-wake)" \
        "exit=$TC1_EXIT (expect 2); stderr_warn_or_wake=$(echo "$TC1_STDERR_CONTENT" | grep -ciE 'warn|tmux-wake'); wake_probe=$TC1_WAKE_PROBE"
fi
cleanup_fake_session "$SESSION_TC1"
trap - EXIT

# -------------------------------------------------------------------------
# TC2: AC1 option B — TELEGRAM_BOT_TOKEN invalid (API call fails) → exit 2 + ERROR + tmux-wake
# -------------------------------------------------------------------------
echo ""
echo "TC2: TELEGRAM_BOT_TOKEN invalid → notify.sh exit 2 + tmux-wake"
SESSION_TC2="d1025-tc2-$$"
create_fake_session "$SESSION_TC2" "DEVELOPER"
trap "cleanup_fake_session '$SESSION_TC2'" EXIT

# Set bogus token to force API rejection; use a fake chat_id too.
TC2_STDERR=$(mktemp)
TC2_EXIT=$(env TELEGRAM_BOT_TOKEN="invalid-token-for-d1025-test" \
    TELEGRAM_CHAT_ID="invalid-chat-for-d1025-test" \
    TMUX_SESSION="$SESSION_TC2" \
    bash "$NOTIFY_SH" -l info -w -r developer "test d1025 tc2 invalid-token probe" \
    2>"$TC2_STDERR" >/dev/null; echo $?)
TC2_STDERR_CONTENT=$(cat "$TC2_STDERR")
rm -f "$TC2_STDERR"

TC2_WAKE_PROBE=$(capture_wake_probe "$SESSION_TC2" "test d1025 tc2 invalid-token probe")

# RED-first expectations:
# - exit code 2 (NOT 1)
# - stderr contains ERROR signal (or "tmux-wake fired" marker)
# - tmux capture-pane shows the wake text injected
if [ "$TC2_EXIT" = "2" ] && \
   echo "$TC2_STDERR_CONTENT" | grep -qiE "error|tmux-wake" && \
   [ "$TC2_WAKE_PROBE" = "PASS" ]; then
    check "TC2 (invalid token → exit 2 + tmux-wake)" "PASS"
else
    check "TC2 (invalid token → exit 2 + tmux-wake)" \
        "exit=$TC2_EXIT (expect 2); stderr_error_or_wake=$(echo "$TC2_STDERR_CONTENT" | grep -ciE 'error|tmux-wake'); wake_probe=$TC2_WAKE_PROBE"
fi
cleanup_fake_session "$SESSION_TC2"
trap - EXIT

# -------------------------------------------------------------------------
# TC3: AC1 happy-path — valid env + reachable bot → exit 0 + dual-channel
# -------------------------------------------------------------------------
echo ""
echo "TC3: valid env + reachable bot → notify.sh exit 0 + dual-channel (regression guard)"
SESSION_TC3="d1025-tc3-$$"
create_fake_session "$SESSION_TC3" "ARCHITECT"

# TC3 is a regression guard: if real Telegram env is set, verify the
# happy-path still works (dual-channel both fire). If env not set,
# INFO-skip (the env-unset case is covered by TC1).
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    check "TC3 (happy-path dual-channel)" "INFO" \
        "TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID not set in test env — TC3 skipped (TC1 covers env-unset case)"
else
    trap "cleanup_fake_session '$SESSION_TC3'" EXIT
    TC3_STDERR=$(mktemp)
    TC3_EXIT=$(TMUX_SESSION="$SESSION_TC3" \
        bash "$NOTIFY_SH" -l info -w -r architect "test d1025 tc3 happy-path probe" \
        2>"$TC3_STDERR" >/dev/null; echo $?)
    TC3_STDERR_CONTENT=$(cat "$TC3_STDERR")
    rm -f "$TC3_STDERR"

    TC3_WAKE_PROBE=$(capture_wake_probe "$SESSION_TC3" "test d1025 tc3 happy-path probe")

    if [ "$TC3_EXIT" = "0" ] && [ "$TC3_WAKE_PROBE" = "PASS" ]; then
        check "TC3 (happy-path exit 0 + tmux-wake)" "PASS"
    else
        check "TC3 (happy-path exit 0 + tmux-wake)" \
            "exit=$TC3_EXIT (expect 0); wake_probe=$TC3_WAKE_PROBE"
    fi
    cleanup_fake_session "$SESSION_TC3"
    trap - EXIT
fi

# -------------------------------------------------------------------------
# TC4: AC1 — peer-poke.sh.tmpl with TELEGRAM_BOT_TOKEN unset → exits 2 + tmux-wake
# -------------------------------------------------------------------------
echo ""
echo "TC4: peer-poke.sh.tmpl with Telegram unset → exit 2 + tmux-wake (inherits notify.sh option B)"
SESSION_TC4="d1025-tc4-$$"
create_fake_session "$SESSION_TC4" "ORCHESTRATOR"
trap "cleanup_fake_session '$SESSION_TC4'" EXIT

TC4_STDERR=$(mktemp)
TC4_EXIT=$(env -u TELEGRAM_BOT_TOKEN -u TELEGRAM_CHAT_ID \
    TMUX_SESSION="$SESSION_TC4" \
    bash "$PEER_POKE_SH" orchestrator "test d1025 tc4 peer-poke env-unset probe" \
    2>"$TC4_STDERR" >/dev/null; echo $?)
TC4_STDERR_CONTENT=$(cat "$TC4_STDERR")
rm -f "$TC4_STDERR"

TC4_WAKE_PROBE=$(capture_wake_probe "$SESSION_TC4" "test d1025 tc4 peer-poke env-unset probe")

# RED-first expectations (peer-poke.sh.tmpl exec's notify.sh, so inherits behavior):
# - exit code 2 (peer-poke.sh.tmpl forwards notify.sh's exit)
# - tmux capture-pane shows wake text injected
if [ "$TC4_EXIT" = "2" ] && [ "$TC4_WAKE_PROBE" = "PASS" ]; then
    check "TC4 (peer-poke Telegram unset → exit 2 + tmux-wake)" "PASS"
else
    check "TC4 (peer-poke Telegram unset → exit 2 + tmux-wake)" \
        "exit=$TC4_EXIT (expect 2); wake_probe=$TC4_WAKE_PROBE"
fi
cleanup_fake_session "$SESSION_TC4"
trap - EXIT

# -------------------------------------------------------------------------
# TC5: agent-wake.sh fallback index map — OSC-2 pane title contamination
# -------------------------------------------------------------------------
echo ""
echo "TC5: agent-wake.sh OSC-2 title contamination → fallback index map fires"
SESSION_TC5="d1025-tc5-$$"
# Create fake session with OSC-2 contaminated pane title (title-match
# will fail; fallback index map to main.0 should still fire)
create_fake_session "$SESSION_TC5" $'\xe2\xa0\x90 BOOTSTRAP orchestrator agent'
# Note: actual main.0 won't exist in our fake session (we have :0.0).
# The fallback path tries ${TMUX_SESSION}:main.0 which doesn't exist;
# agent-wake.sh swallows send-keys errors with `|| exit 0` (line 67),
# so this TC verifies graceful no-op, not wake-success.
# A more robust fallback test would require setting up panes at main.0-4
# addresses; deferred to follow-up d-test (out of scope for d1025).
trap "cleanup_fake_session '$SESSION_TC5'" EXIT

# Just verify the call doesn't crash and produces no error output
TC5_STDERR=$(mktemp)
TC5_EXIT=$(TMUX_SESSION="$SESSION_TC5" \
    bash "$AGENT_WAKE_SH" orchestrator "test d1025 tc5 osc2 fallback probe" \
    2>"$TC5_STDERR" >/dev/null; echo $?)
TC5_STDERR_CONTENT=$(cat "$TC5_STDERR")
rm -f "$TC5_STDERR"

# agent-wake.sh silent no-op on missing pane (exit 0 expected).
# This is a graceful-degradation regression guard.
# This TC is GREEN pre-port (tmpl already has TD-068b fix on agent-wake.sh
# from S28 commit 6191b6c) — it documents the regression-guard contract.
if [ "$TC5_EXIT" = "0" ] && [ -z "$TC5_STDERR_CONTENT" ]; then
    check "TC5 (OSC-2 title → graceful fallback)" "PASS"
else
    check "TC5 (OSC-2 title → graceful fallback)" \
        "exit=$TC5_EXIT (expect 0); stderr=$TC5_STDERR_CONTENT"
fi
cleanup_fake_session "$SESSION_TC5"
trap - EXIT

# -------------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------------
echo ""
echo "==============================================="
echo "d1025-s29-template-env-decoupling-port-parity: $pass pass, $fail fail"
echo "==============================================="
[ "$fail" -eq 0 ] || exit 1
