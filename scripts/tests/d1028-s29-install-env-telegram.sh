#!/usr/bin/env bash
# d1028-s29-install-env-telegram.sh — Sprint 29 W2 install-env-telegram helper
# RED-first d-test (Phase A, prior to impl per ADR-0044).
#
# Doctrinal contract (≥5 TCs baseline per ADR-0049 + Issue #100 AC2 spec):
#   TC0: bash -n syntactic self-check of scripts/install/dev-studio-install-env.sh
#   TC1: AC1 happy-path — CLI args → 6 env files written + both vars present
#   TC2: AC2 env-var fallback — env vars set + no CLI args → same outcome as TC1
#   TC3: AC5 idempotency — re-run with same args → no-op (mtime unchanged)
#   TC4: AC1 refusal — no args + no env vars → exit 2 + usage to stderr
#   TC5: AC1 chmod — file perms are 600 on all 6 env files (not 644/640)
#
# Doctrinal home: Issue #100 (this d-test tracker, agent:developer impl owner),
#   Issue #101 (cluster-blocked: docs/setup-Telegram.md operator recipe, gated
#   on this GREEN per Issue #100 §Cadence Phase C).
#
# RED-first per ADR-0044: ALL TCs FAIL pre-impl (scripts/install/dev-studio-
#   install-env.sh does not exist at commit time — file-not-found errors).
#   Post-impl (when developer writes the script per AC1 spec): all 6 TCs GREEN.
#
# Cadence Rule 1 atomic (ADR-0055 §1): this d-test file + INDEX.md entry
#   land in same commit. Sister-pattern per d096.
#
# Sister-patterns (≥3 per ADR-0049):
#   - d1026 (template env-decoupling port-parity, PR #91 merged) — direct
#     sister, same author lane (tester), same ≥5 TC structure, same
#     Cadence Rule 1 atomic discipline on INDEX.md, same fake-fixture pattern
#   - d1024 (calc-side env-decoupling source-of-truth, atilcan65/AtilCalculator
#     PR #1056 merged) — same 5-TC structure, same exit-code matrix, same
#     fake-session isolation pattern (per d058)
#   - d1027 (template pyproject-render, PR #104 merged) — sister
#     Sprint 29 W2 template-side d-test, same RED-first cadence, same
#     Issue #1075 cluster shape (Issue #100 mirrors Issue #1075 pattern)
#   - d058 (work-stream aware — fake-session isolation pattern, sister)
#   - d081 (auto-verdict-by-hook on tmpl) — template-side d-test authoring
#     conventions, INDEX.md format
#   - d296 (peer-poke argv + usage discipline) — TC4 inherits argv shape
#   - d096 (soul-files-template d-test) — Cadence Rule 1 atomic precedent
#
# Cross-refs:
#   - ADR-0033 (dual-channel doctrine) — the doctrine this cluster enables
#   - ADR-0031 (owner merge gate — only human squash-merges impl PR)
#   - ADR-0044 (RED-first TDD doctrinal home)
#   - ADR-0049 (d-test framework, ≥5 TCs baseline)
#   - ADR-0055 §1 (Cadence Rule 1 atomic)
#   - ADR-0057 (closes-anchor strict format — `Refs #100` for d-test PR, `Closes #100` reserved for impl PR per ADR-0057)
#   - ADR-0059 (cluster-squash — d-test ships BEFORE impl, sister-PR must
#     land same merge-day as calc-side d-test for cluster-squash)
#   - Issue #100 (this d-test tracker, Phase A)
#   - Issue #101 (cluster-blocked arch docs, Phase C)
#   - Issue #1058 (calc-side cluster coord sister, atilcan65/AtilCalculator)
#   - Issue #1060 (calc-side Phase B env-decoupling, in flight via tmpl PR #98)
#   - PR #91 (d1026 sister, MERGED 2026-07-14T16:57:49Z)
#   - PR #104 (d1027 sister, MERGED 2026-07-14T20:33:14Z — d-number collision)

set -euo pipefail

SCRIPT_DIR_D1028="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_D1028="$(cd "${SCRIPT_DIR_D1028}/../.." && pwd)"
INSTALL_SCRIPT="${REPO_ROOT_D1028}/scripts/install/dev-studio-install-env.sh"

pass=0
fail=0

check() {
    if [ "${2:-FAIL}" = "PASS" ]; then
        echo "  ✅ $1"
        pass=$((pass+1))
    elif [ "${2:-FAIL}" = "INFO" ]; then
        echo "  ℹ️  $1: ${3:-}"
        # INFO is informational — neither pass nor fail increment
    else
        echo "  ❌ $1: ${3:-}"
        fail=$((fail+1))
    fi
}

require_dependencies() {
    local missing=0
    if ! command -v bash >/dev/null 2>&1; then
        echo "FATAL: bash not found in PATH" >&2
        missing=1
    fi
    if ! command -v stat >/dev/null 2>&1; then
        echo "FATAL: stat not found in PATH (required for TC3 mtime + TC5 chmod 600 assertion)" >&2
        missing=1
    fi
    if ! command -v grep >/dev/null 2>&1; then
        echo "FATAL: grep not found in PATH" >&2
        missing=1
    fi
    if ! command -v mktemp >/dev/null 2>&1; then
        echo "FATAL: mktemp not found in PATH (required for fake-home fixture isolation)" >&2
        missing=1
    fi
    [ "$missing" -eq 0 ] || exit 2
}

# make_fake_home <project-name>
# Creates an isolated HOME with the 5 instance env files pre-created
# (per AC1 "Detects all 5 instance env files" contract — script must
# detect these files even if empty). Sister-pattern d1024 uses the
# same fake-fixture pattern (per d058 fake-session isolation). The
# real ~/.dev-studio-env is NEVER touched.
make_fake_home() {
    local project="$1"
    FAKE_HOME_D1028="$(mktemp -d -t d1028-fake-home.XXXXXX)"
    export HOME="$FAKE_HOME_D1028"
    mkdir -p "$HOME/.config/dev-studio/instances"
    local roles=(orchestrator product-manager architect developer tester)
    for r in "${roles[@]}"; do
        touch "$HOME/.config/dev-studio/instances/${project}--$r.env"
        chmod 600 "$HOME/.config/dev-studio/instances/${project}--$r.env"
    done
}

cleanup_fake_home() {
    if [ -n "${FAKE_HOME_D1028:-}" ] && [ -d "${FAKE_HOME_D1028:-}" ]; then
        rm -rf "$FAKE_HOME_D1028"
    fi
    unset HOME
}

trap cleanup_fake_home EXIT

require_dependencies

# -------------------------------------------------------------------------
# TC0 (preflight): bash -n syntactic self-check of dev-studio-install-env.sh
#   RED-first: FAIL pre-impl (file doesn't exist). GREEN post-impl.
# -------------------------------------------------------------------------
echo "TC0: bash -n syntactic self-check"
if [ ! -f "$INSTALL_SCRIPT" ]; then
    check "TC0 — file exists at canonical path scripts/install/dev-studio-install-env.sh" "FAIL" "file not found (RED — impl not yet landed)"
elif ! bash -n "$INSTALL_SCRIPT" 2>/dev/null; then
    check "TC0 — bash -n passes on scripts/install/dev-studio-install-env.sh" "FAIL" "bash -n exit non-zero (syntax error)"
else
    check "TC0 — bash -n syntactic self-check PASS" "PASS"
fi

# -------------------------------------------------------------------------
# TC1: AC1 happy-path — CLI args → 6 env files written, both vars present
# -------------------------------------------------------------------------
echo "TC1: happy-path (CLI args)"
make_fake_home "test-project-1"
if [ ! -f "$INSTALL_SCRIPT" ]; then
    check "TC1 — happy-path CLI args → 6 env files written" "FAIL" "script not found (RED — impl not yet landed)"
elif ! "$INSTALL_SCRIPT" --telegram-bot-token TC1_TEST_BOT --telegram-chat-id TC1_TEST_CHAT 2>/dev/null; then
    check "TC1 — install-env.sh exits 0 with CLI args" "FAIL" "exit non-zero"
else
    fail_tc1=""
    if [ ! -f "$HOME/.dev-studio-env" ]; then
        fail_tc1="main-env missing"
    elif ! grep -q 'export TELEGRAM_BOT_TOKEN="TC1_TEST_BOT"' "$HOME/.dev-studio-env"; then
        fail_tc1="main-env token missing"
    elif ! grep -q 'export TELEGRAM_CHAT_ID="TC1_TEST_CHAT"' "$HOME/.dev-studio-env"; then
        fail_tc1="main-env chat-id missing"
    else
        for r in orchestrator product-manager architect developer tester; do
            f="$HOME/.config/dev-studio/instances/test-project-1--$r.env"
            if [ ! -f "$f" ]; then
                fail_tc1="instance $r missing"
                break
            elif ! grep -q '^TELEGRAM_BOT_TOKEN="TC1_TEST_BOT"$' "$f"; then
                fail_tc1="instance $r token missing"
                break
            elif ! grep -q '^TELEGRAM_CHAT_ID="TC1_TEST_CHAT"$' "$f"; then
                fail_tc1="instance $r chat-id missing"
                break
            fi
        done
    fi
    if [ -z "$fail_tc1" ]; then
        check "TC1 — happy-path CLI args → 6 env files written, both vars present" "PASS"
    else
        check "TC1 — happy-path partial: $fail_tc1" "FAIL"
    fi
fi
cleanup_fake_home

# -------------------------------------------------------------------------
# TC2: AC2 env-var fallback — env vars set + no CLI args → same outcome
# -------------------------------------------------------------------------
echo "TC2: env-var fallback"
make_fake_home "test-project-2"
export TELEGRAM_BOT_TOKEN="TC2_TEST_BOT"
export TELEGRAM_CHAT_ID="TC2_TEST_CHAT"
if [ ! -f "$INSTALL_SCRIPT" ]; then
    check "TC2 — env-var fallback → 6 env files written" "FAIL" "script not found (RED — impl not yet landed)"
elif ! "$INSTALL_SCRIPT" 2>/dev/null; then
    check "TC2 — install-env.sh exits 0 with env-var fallback" "FAIL" "exit non-zero"
else
    fail_tc2=""
    if [ ! -f "$HOME/.dev-studio-env" ]; then
        fail_tc2="main-env missing"
    elif ! grep -q 'export TELEGRAM_BOT_TOKEN="TC2_TEST_BOT"' "$HOME/.dev-studio-env"; then
        fail_tc2="main-env token missing"
    elif ! grep -q 'export TELEGRAM_CHAT_ID="TC2_TEST_CHAT"' "$HOME/.dev-studio-env"; then
        fail_tc2="main-env chat-id missing"
    else
        for r in orchestrator product-manager architect developer tester; do
            f="$HOME/.config/dev-studio/instances/test-project-2--$r.env"
            if [ ! -f "$f" ]; then
                fail_tc2="instance $r missing"
                break
            elif ! grep -q '^TELEGRAM_BOT_TOKEN="TC2_TEST_BOT"$' "$f"; then
                fail_tc2="instance $r token missing"
                break
            elif ! grep -q '^TELEGRAM_CHAT_ID="TC2_TEST_CHAT"$' "$f"; then
                fail_tc2="instance $r chat-id missing"
                break
            fi
        done
    fi
    if [ -z "$fail_tc2" ]; then
        check "TC2 — env-var fallback → 6 env files written, both vars present" "PASS"
    else
        check "TC2 — env-var fallback partial: $fail_tc2" "FAIL"
    fi
fi
cleanup_fake_home
unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID

# -------------------------------------------------------------------------
# TC3: AC5 idempotency — re-run with same args → no-op (mtime unchanged)
# -------------------------------------------------------------------------
echo "TC3: idempotency"
make_fake_home "test-project-3"
if [ ! -f "$INSTALL_SCRIPT" ]; then
    check "TC3 — idempotency (re-run is no-op)" "FAIL" "script not found (RED)"
elif ! "$INSTALL_SCRIPT" --telegram-bot-token TC3_TEST_BOT --telegram-chat-id TC3_TEST_CHAT 2>/dev/null; then
    check "TC3 — first run exits 0" "FAIL" "exit non-zero"
else
    MTIME_FIRST=$(stat -c '%Y' "$HOME/.dev-studio-env")
    sleep 1.1
    if ! "$INSTALL_SCRIPT" --telegram-bot-token TC3_TEST_BOT --telegram-chat-id TC3_TEST_CHAT 2>/dev/null; then
        check "TC3 — second run exits 0" "FAIL" "exit non-zero"
    else
        MTIME_SECOND=$(stat -c '%Y' "$HOME/.dev-studio-env")
        if [ "$MTIME_FIRST" = "$MTIME_SECOND" ]; then
            check "TC3 — idempotent re-run no-op (mtime unchanged: $MTIME_FIRST)" "PASS"
        else
            check "TC3 — idempotency broken (mtime changed: $MTIME_FIRST → $MTIME_SECOND)" "FAIL"
        fi
    fi
fi
cleanup_fake_home

# -------------------------------------------------------------------------
# TC4: AC1 refusal — no args + no env vars → exit 2 + usage to stderr
# -------------------------------------------------------------------------
echo "TC4: refusal exit 2"
make_fake_home "test-project-4"
unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID 2>/dev/null || true
if [ ! -f "$INSTALL_SCRIPT" ]; then
    check "TC4 — refusal exit 2 + usage" "FAIL" "script not found (RED)"
else
    EXIT_CODE=0
    STDERR_OUT=$("$INSTALL_SCRIPT" 2>&1 >/dev/null) || EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq 2 ]; then
        if echo "$STDERR_OUT" | grep -qiE '(usage|Usage|--telegram-bot-token|--telegram-chat-id)'; then
            check "TC4 — refusal exit 2 + usage to stderr" "PASS"
        else
            check "TC4 — refused (exit 2) but no usage text on stderr" "FAIL"
        fi
    else
        check "TC4 — should exit 2 with no args + no env vars (got exit=$EXIT_CODE)" "FAIL"
    fi
fi
cleanup_fake_home

# -------------------------------------------------------------------------
# TC5: AC1 chmod — file perms are 600 on all 6 env files
# -------------------------------------------------------------------------
echo "TC5: chmod 600"
make_fake_home "test-project-5"
if [ ! -f "$INSTALL_SCRIPT" ]; then
    check "TC5 — chmod 600 verification" "FAIL" "script not found (RED)"
elif ! "$INSTALL_SCRIPT" --telegram-bot-token TC5_TEST_BOT --telegram-chat-id TC5_TEST_CHAT 2>/dev/null; then
    check "TC5 — install-env.sh exits 0" "FAIL" "exit non-zero"
else
    fail_tc5=""
    PERMS_MAIN=$(stat -c '%a' "$HOME/.dev-studio-env")
    if [ "$PERMS_MAIN" != "600" ]; then
        fail_tc5="main-env=$PERMS_MAIN"
    else
        for r in orchestrator product-manager architect developer tester; do
            f="$HOME/.config/dev-studio/instances/test-project-5--$r.env"
            if [ -f "$f" ]; then
                P=$(stat -c '%a' "$f")
                if [ "$P" != "600" ]; then
                    fail_tc5="instance $r=$P"
                    break
                fi
            fi
        done
    fi
    if [ -z "$fail_tc5" ]; then
        check "TC5 — chmod 600 on all 6 env files (main + 5 instances)" "PASS"
    else
        check "TC5 — chmod 600 partial: $fail_tc5" "FAIL"
    fi
fi
cleanup_fake_home

# -------------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------------
echo ""
echo "Summary: PASS=$pass FAIL=$fail"
if [ "$fail" -gt 0 ]; then
    exit 1
fi
exit 0
