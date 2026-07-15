#!/usr/bin/env bash
# d1041-template-agent-watch-org-scan-default.sh — Sister-template mirror of
# AtilCalculator d1041 (PR #1085). Codifies org-scan default + 180s poll cadence
# in the CANONICAL dev-studio-template source so future clones inherit both
# behaviors on init (RETRO-023 cross-repo sister-pattern codifier).
#
# Sister-pattern: AtilCalculator d1041 (PR #1085 commit f43d24f, agent:developer).
# Slot rationale: same d1041 number for cross-repo traceability — the
# dev-studio-template INDEX row explicitly marks it as "sister-template mirror"
# so it does not collide with the calc-side d1041 (different repo, different INDEX).
#
# Per ADR-0049 ≥5 TCs baseline; this d-test = 5 TCs.
#
#   TC1: --help lists --org flag + AGENT_WATCH_ORG env var (sister-pattern to
#        AtilCalculator d1041 TC1)
#   TC2: AGENT_WATCH_ORG defaults to "atilproject" (default codification)
#   TC3: Empty AGENT_WATCH_ORG disables org-scan (back-compat shim for non-org
#        projects — `[ -n "$ORG_FLAG" ] || [ -n "${AGENT_WATCH_ORG:-}" ]`
#        guard wraps org-scan block)
#   TC4: --org flag overrides AGENT_WATCH_ORG env var (precedence chain)
#   TC5: agent-watch.sh POLL_INTERVAL default = 180s (owner directive)
#        + agent-state.sh DEFAULT_POLL default = 180s (sister change)
#
# RED-first per ADR-0044: pre-impl all 5 TCs FAIL on main HEAD, post-impl 5/5 GREEN.
#
# Run standalone: bash scripts/tests/d1041-template-agent-watch-org-scan-default.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH_SH="$SCRIPT_DIR/../agent-watch.sh"
STATE_SH="$SCRIPT_DIR/../agent-state.sh"

# Colors (TTY-aware)
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
else
  GREEN=''; RED=''; YELLOW=''; NC=''
fi

PASS=0
FAIL=0
TESTS=0

run_tc() {
  local tc_id="$1"; local desc="$2"; local body="$3"
  TESTS=$((TESTS + 1))
  local result
  if result="$(eval "$body" 2>&1)"; then
    if [ "$result" = "PASS" ]; then
      PASS=$((PASS + 1))
      printf "${GREEN}✅ %s${NC} %s\n" "$tc_id" "$desc"
    else
      FAIL=$((FAIL + 1))
      printf "${RED}❌ %s${NC} %s\n  result: %s\n" "$tc_id" "$desc" "$result"
    fi
  else
    FAIL=$((FAIL + 1))
    printf "${RED}❌ %s${NC} %s\n  error: %s\n" "$tc_id" "$desc" "$result"
  fi
}

# --- preflight ---
[ -x "$WATCH_SH" ] || { echo "ERROR: $WATCH_SH not executable" >&2; exit 2; }
[ -x "$STATE_SH" ] || { echo "ERROR: $STATE_SH not executable" >&2; exit 2; }

# TC1: --help lists --org flag and AGENT_WATCH_ORG env var
run_tc "TC1" "--help lists --org flag + AGENT_WATCH_ORG env var" '
  HELP_OUT="$(bash "'"$WATCH_SH"'" --help 2>&1)"
  if echo "$HELP_OUT" | grep -q "\-\-org <name>" && echo "$HELP_OUT" | grep -q "AGENT_WATCH_ORG"; then
    echo "PASS"
  else
    echo "FAIL: --org or AGENT_WATCH_ORG not in --help output"
  fi
'

# TC2: AGENT_WATCH_ORG defaults to "atilproject"
run_tc "TC2" "AGENT_WATCH_ORG defaults to \"atilproject\"" '
  if grep -qE "^AGENT_WATCH_ORG=\"\\\$\{AGENT_WATCH_ORG:-atilproject\}\"" "'"$WATCH_SH"'"; then
    echo "PASS"
  else
    echo "FAIL: AGENT_WATCH_ORG default = atilproject not found in script"
  fi
'

# TC3: Empty AGENT_WATCH_ORG disables org-scan — guard wraps the org-scan block
run_tc "TC3" "Empty AGENT_WATCH_ORG disables org-scan (guard pattern)" '
  if grep -qE "if \[ -n \"\\\$ORG_FLAG\" \] \|\| \[ -n \"\\\$\{AGENT_WATCH_ORG:-\}\" \]; then" "'"$WATCH_SH"'"; then
    echo "PASS"
  else
    echo "FAIL: org-scan guard condition not found"
  fi
'

# TC4: --org flag overrides AGENT_WATCH_ORG env var — argv parser has --org case
run_tc "TC4" "--org flag overrides AGENT_WATCH_ORG env var" '
  if grep -qE "\\-\\-org\\)" "'"$WATCH_SH"'" && grep -qE "ORG_FLAG=\"\\\$\{arg#\\-\\-org=\}\"" "'"$WATCH_SH"'"; then
    echo "PASS"
  else
    echo "FAIL: --org flag precedence not found in script"
  fi
'

# TC5: agent-watch.sh POLL_INTERVAL default = 180s + agent-state.sh DEFAULT_POLL = 180s
run_tc "TC5" "POLL_INTERVAL=180 in agent-watch.sh + DEFAULT_POLL=180 in agent-state.sh" '
  if grep -qE "POLL_INTERVAL=\"\\\$\{POLL_INTERVAL:-180\}\"" "'"$WATCH_SH"'" \
     && grep -qE "DEFAULT_POLL=\"\\\$\{AGENT_POLL_INTERVAL_SEC:-180\}\"" "'"$STATE_SH"'"; then
    echo "PASS"
  else
    echo "FAIL: 180s defaults not found in both scripts"
  fi
'

# --- summary ---
echo
echo "================================================="
if [ "$FAIL" -eq 0 ]; then
  printf "${GREEN}d1041-template-agent-watch-org-scan-default: %d/%d PASS${NC}\n" "$PASS" "$TESTS"
  exit 0
else
  printf "${RED}d1041-template-agent-watch-org-scan-default: %d/%d PASS (%d FAIL)${NC}\n" "$PASS" "$TESTS" "$FAIL"
  exit 1
fi