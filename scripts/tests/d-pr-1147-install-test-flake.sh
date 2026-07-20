#!/usr/bin/env bash
# d-pr-1147-install-test-flake.sh — Issue #1150 regression test (3+ TCs).
#
# Why this test exists
# --------------------
# Issue #1150 (P1 bug) — `tests/docs/test_readme.py::test_install_command_executes`
# hits github-hosted runner OOM killer (returncode -9 = SIGKILL) during
# `python -m venv` with 60s hard-coded timeout. Blocks PR #1147 (Sprint 32 plan)
# owner-merge gate. Cluster-squash (PR #1147 + #129 + #131) on hold until fix lands.
#
# Sister-pattern: d058 (claim-next-ready work-stream awareness) + d1142 (queue
# hygiene 4-cycle threshold) — all bash + grep/awk file-content verifiers, no
# real pytest invocation needed (the d-test verifies that the FIX is present in
# the source, which is the contract; full pytest validation runs in CI).
#
# 4 TCs (3 required per AC5 + 1 pytest-execution regression guard):
#   TC1: timeout relaxation present (tests/docs/test_readme.py:venv creation line)
#   TC2: session-scoped shared_venv fixture exists + yields venv path
#   TC3: test_install_command_executes wired to use shared_venv parameter
#   TC4: pytest passes locally (execution regression guard; >0s but <120s)
#
# Usage:
#   bash scripts/tests/d-pr-1147-install-test-flake.sh --self-test     # run inline fixture
#
# Doctrinal refs
# --------------
# - Issue #1150 (P1 bug, blocker for PR #1147 cluster-squash)
# - ADR-0044 (RED-first TDD — d-test written before fix lands)
# - ADR-0049 (d-test framework sister-pattern, ≥5 TCs target; 3 acceptable for hygiene)
# - ADR-0055 §1 Cadence Rule 1 atomic (d-test + INDEX.md row in same commit)

set -euo pipefail

# Locate repo root from script location (sister-pattern to d058/d031)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_FILE="$REPO_ROOT/tests/docs/test_readme.py"

# -- TCs ----------------------------------------------------------------------
# TC1: timeout=180 present in test_readme.py venv creation call
# TC2: @pytest.fixture(scope="session") + def shared_venv fixture exists
# TC3: test_install_command_executes references shared_venv parameter
# TC4: pytest tests/docs/test_readme.py passes locally (regression guard)
# ---------------------------------------------------------------------------

if [[ "${1:-}" == "--self-test" ]]; then
    _fails=0
    _passes=0

    # TC1: timeout relaxation (60 -> 180 on venv creation call)
    if grep -B4 "timeout=180" "$TEST_FILE" | grep -q "venv" && grep -qE "timeout=180" "$TEST_FILE"; then
        echo "TC1 ✅ timeout=180 present in venv-creation call"
        _passes=$((_passes + 1))
    else
        echo "TC1 ❌ FAIL: timeout=180 missing or not in venv-creation context"
        _fails=$((_fails + 1))
    fi

    # TC2: session-scoped shared_venv fixture exists
    if grep -qE "@pytest\.fixture\(scope=\"session\"\)" "$TEST_FILE" && grep -qE "def shared_venv\(" "$TEST_FILE"; then
        echo "TC2 ✅ session-scoped shared_venv fixture exists"
        _passes=$((_passes + 1))
    else
        echo "TC2 ❌ FAIL: shared_venv session-scoped fixture missing"
        _fails=$((_fails + 1))
    fi

    # TC3: test_install_command_executes wired to shared_venv parameter
    if grep -qE "def test_install_command_executes\(self, shared_venv\)" "$TEST_FILE"; then
        echo "TC3 ✅ test_install_command_executes wired to shared_venv"
        _passes=$((_passes + 1))
    else
        echo "TC3 ❌ FAIL: test_install_command_executes not wired to shared_venv"
        _fails=$((_fails + 1))
    fi

    # TC4: pytest passes locally (regression guard; allow ≤120s)
    if command -v pytest >/dev/null 2>&1; then
        if timeout 120 pytest -q "$TEST_FILE" >/tmp/d-pr-1147-pytest.log 2>&1; then
            echo "TC4 ✅ pytest passes locally (regression guard)"
            _passes=$((_passes + 1))
        else
            echo "TC4 ❌ FAIL: pytest fails locally — see /tmp/d-pr-1147-pytest.log"
            tail -5 /tmp/d-pr-1147-pytest.log | sed 's/^/    /'
            _fails=$((_fails + 1))
        fi
    else
        echo "TC4 ⚠️  SKIP: pytest not on PATH (env issue, not fix issue)"
    fi

    echo "---"
    echo "d-pr-1147-install-test-flake: $_passes passed, $_fails failed"
    if [[ $_fails -gt 0 ]]; then
        exit 1
    fi
    exit 0
fi

# Default: print usage
cat <<'EOF'
d-pr-1147-install-test-flake.sh — Issue #1150 regression test

Usage:
  bash d-pr-1147-install-test-flake.sh --self-test     # run 4 TCs inline
EOF
