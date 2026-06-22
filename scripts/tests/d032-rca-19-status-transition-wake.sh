#!/usr/bin/env bash
# d032-rca-19-status-transition-wake.sh — regression for #233
# (RCA-19 status-transition wake fix per ADR-0036, ported to template)
#
# Why this test exists
# --------------------
# Issue #233 (Sprint 4 P0): port RCA-19 status-transition wake fix from
# atilcan65/AtilCalculator (PR #270) to atilcan65/dev-studio-template so
# all future bootstrapped repos get the fix for free.
#
# Per ADR-0036 Part A+C fix:
#   Part A: extend `query_board_changes()` in scripts/agent-watch.sh to be
#           role-aware (return label changes on issues with agent:<role>
#           for non-orchestrator roles)
#   Part C: new `scripts/orchestrator-status-flip.sh` helper that atomically
#           flips status + emits wake signal (notify.sh fallback path —
#           template notify.sh does not yet have -w flag, see follow-up)
#
# Sister test: AtilCalculator scripts/tests/d032-rca-19-status-transition-wake.sh
#
# Template-specific adaptions vs AtilCalculator version:
#   - Template notify.sh has only -l flag (no -w dual-channel yet), so T6
#     asserts on -l fallback path. Future work: port notify.sh -w flag from
#     AtilCalculator (separate issue, see N1 in PR body).
#   - Test numbering d032 matches AtilCalculator for cross-repo traceability.
#
# Test cases (per ADR-0036 §d025 spec, 10 TCs):
#   T1:  scripts/orchestrator-status-flip.sh exists + executable
#   T2:  Helper has role guard (requires ROLE=orchestrator, exits 3 otherwise)
#   T3:  Helper has input validation (status enum, exits 2 on invalid)
#   T4:  Helper has idempotency check (current == new → exit 0, no flip, no wake)
#   T5:  Helper has atomic flip pattern (single `gh issue edit --remove-label "status:*" --add-label "status:X"`)
#   T6:  Helper has wake signal via notify.sh (template uses -l fallback only)
#   T7:  Helper has audit log path (/var/log/dev-studio/<project>/status-flips.log)
#   T8:  Helper has closed-state guard (exits 4 on closed issue)
#   T9:  Helper has usage error path (missing args → exit 2)
#   T10: agent-watch.sh query_board_changes is role-aware (branches on ROLE
#        for non-orchestrator returns label changes only on agent:<role> issues;
#        for orchestrator returns all label changes — back-compat)
#
# Exit code: 0 = all pass, 1 = at least one fail.
#
# Run standalone: bash scripts/tests/d032-rca-19-status-transition-wake.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER_SH="$REPO_ROOT/scripts/orchestrator-status-flip.sh"
WATCH_SH="$REPO_ROOT/scripts/agent-watch.sh"
NOTIFY_SH="$REPO_ROOT/scripts/notify.sh"

# Colors (TTY-aware)
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; B=""; D=""
fi

PASS=0; FAIL=0
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

# ============================================================================
# Part C — Helper script tests
# ============================================================================

section "T1: scripts/orchestrator-status-flip.sh exists + executable"
if [ -f "$HELPER_SH" ] && [ -x "$HELPER_SH" ]; then
  pass "helper exists and is executable"
else
  fail "helper missing or not executable" "expected: scripts/orchestrator-status-flip.sh (-x bit set) — ADR-0036 Part C"
fi

# ============================================================================
# T2: Role guard
# ============================================================================
section "T2: Helper has ROLE=orchestrator guard (exits 3 if not)"
if [ -f "$HELPER_SH" ] && grep -Eq 'ROLE.*orchestrator|orchestrator-only|exit 3' "$HELPER_SH"; then
  pass "helper has orchestrator role guard"
else
  fail "no role guard" "expected: ROLE check that exits 3 if not orchestrator (ADR-0036 §Part C property 1)"
fi

# ============================================================================
# T3: Input validation (status enum)
# ============================================================================
section "T3: Helper validates status enum (backlog|ready|in-progress|in-review|blocked|done)"
if [ -f "$HELPER_SH" ] && grep -Eq 'backlog\|ready\|in-progress\|in-review\|blocked\|done' "$HELPER_SH"; then
  pass "helper validates status enum"
else
  fail "no status enum validation" "expected: case \"\$NEW_STATUS\" in backlog|ready|in-progress|in-review|blocked|done) ... esac"
fi

# ============================================================================
# T4: Idempotency check
# ============================================================================
section "T4: Helper has idempotency check (current == new → no-op)"
if [ -f "$HELPER_SH" ] && grep -Eq 'already|noop|no-op|idempotent' "$HELPER_SH"; then
  pass "helper has idempotency check"
else
  fail "no idempotency check" "expected: if [ \"\$CURRENT\" = \"status:\$NEW_STATUS\" ]; then exit 0; fi (ADR-0036 §Part C property 3)"
fi

# ============================================================================
# T5: Atomic flip pattern
# ============================================================================
section "T5: Helper uses atomic flip pattern (single gh issue edit --remove-label --add-label)"
if [ -f "$HELPER_SH" ] && grep -Eq 'gh issue edit.*--remove-label.*status:\*.*--add-label.*status:' "$HELPER_SH"; then
  pass "helper uses atomic flip (single gh issue edit)"
else
  fail "no atomic flip" "expected: gh issue edit \$ISSUE --remove-label 'status:*' --add-label 'status:\$NEW_STATUS' (ADR-0036 §Part C property 4)"
fi

# ============================================================================
# T6: Wake signal — template uses notify.sh -l fallback (notify.sh -w is
#       separate follow-up; see PR body N1)
# ============================================================================
section "T6: Helper calls notify.sh for wake signal (template: -l fallback path)"
if [ -f "$HELPER_SH" ] && grep -Eq 'notify\.sh.*-l' "$HELPER_SH"; then
  pass "helper emits wake signal via notify.sh -l fallback"
else
  fail "no wake signal" "expected: notify.sh -l \$NEXT_ROLE \"\$WAKE_MSG\" (template uses -l only; -w dual-channel deferred, PR body N1)"
fi

# ============================================================================
# T7: Audit log path
# ============================================================================
section "T7: Helper writes audit log to /var/log/dev-studio/<project>/status-flips.log"
if [ -f "$HELPER_SH" ] && grep -Eq 'status-flips\.log|/var/log/dev-studio' "$HELPER_SH"; then
  pass "helper has audit log path"
else
  fail "no audit log path" "expected: /var/log/dev-studio/\$PROJECT/status-flips.log (ADR-0036 §Part C property 6)"
fi

# ============================================================================
# T8: Closed-state guard
# ============================================================================
section "T8: Helper has closed-state guard (exits 4 on closed issue)"
if [ -f "$HELPER_SH" ] && grep -Eq 'closed.*exit 4|exit 4.*closed|state.*closed' "$HELPER_SH"; then
  pass "helper has closed-state guard"
else
  fail "no closed-state guard" "expected: if issue is state:closed, exit 4 (ADR-0036 §Part C property 7)"
fi

# ============================================================================
# T9: Usage error path
# ============================================================================
section "T9: Helper has usage error path (missing args → exit 2)"
if [ -f "$HELPER_SH" ] && grep -Eq 'usage:|exit 2' "$HELPER_SH"; then
  pass "helper has usage error path"
else
  fail "no usage error path" "expected: missing args → 'usage: orchestrator-status-flip.sh ...' + exit 2"
fi

# ============================================================================
# Part A — agent-watch.sh role-aware query_board_changes
# ============================================================================

section "T10: agent-watch.sh query_board_changes is role-aware (Part A)"
# Per ADR-0036 §Part A: extend query_board_changes() to be role-aware.
# For non-orchestrator roles, return label changes ONLY on issues with
# agent:<role> label. For orchestrator, unchanged (back-compat).
#
# Structural checks:
#   (a) Function references ROLE variable
#   (b) Has branch on ROLE: orchestrator vs other
#   (c) For other roles: filter on agent:<role> (select(.labels | map(.name) | contains(["agent:developer"])))
#   (d) Event ID is role-scoped: "board-${role}-..."

if [ -f "$WATCH_SH" ]; then
  has_role_branch=false
  has_agent_filter=false
  has_role_scoped_id=false

  # Check (a) + (b): ROLE variable used inside query_board_changes
  if awk '/^query_board_changes\(\)/,/^}/' "$WATCH_SH" | grep -Eq '\$ROLE|"\$\{?ROLE\}?"'; then
    has_role_branch=true
  fi

  # Check (c): filter for non-orchestrator roles on agent:<role>
  if awk '/^query_board_changes\(\)/,/^}/' "$WATCH_SH" | grep -Eq 'agent:\$\{?ROLE\}?|select.*agent.*ROLE'; then
    has_agent_filter=true
  fi

  # Check (d): role-scoped event ID (jq syntax: "board-$ROLE-" + .number + ...)
  if grep -Eq 'board-\$\{?ROLE\}?|board-\$ROLE-' "$WATCH_SH"; then
    has_role_scoped_id=true
  fi

  if $has_role_branch && $has_agent_filter && $has_role_scoped_id; then
    pass "query_board_changes is role-aware (ROLE branch + agent:<role> filter + role-scoped event ID)"
  else
    fail_lines=""
    $has_role_branch || fail_lines+="missing: ROLE branch in query_board_changes"$'\n'
    $has_agent_filter || fail_lines+="missing: agent:<role> filter for non-orchestrator roles"$'\n'
    $has_role_scoped_id || fail_lines+="missing: role-scoped event ID (board-\$role-\$number-...)"$'\n'
    fail "query_board_changes not role-aware" "ADR-0036 §Part A fix incomplete — $fail_lines"
  fi
else
  fail "agent-watch.sh missing — T10 cannot run" "expected: scripts/agent-watch.sh with role-aware query_board_changes"
fi

# ============================================================================
# Summary
# ============================================================================
printf "\n${B}==== SUMMARY ====${D}\n"
printf "  ${G}PASS${D}: %d\n" "$PASS"
printf "  ${R}FAIL${D}: %d\n" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo
  echo "Issue #233 REGRESSION FAILED — RCA-19 status-transition wake template port incomplete."
  echo "Fix: implement Part A (role-aware query_board_changes in agent-watch.sh)"
  echo "     + Part C (scripts/orchestrator-status-flip.sh) per ADR-0036."
  exit 1
fi
echo
echo "Issue #233 REGRESSION PASS — RCA-19 status-transition wake template port complete."
exit 0