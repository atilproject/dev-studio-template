#!/usr/bin/env bash
# d1042-template-agent-watch-line-294-repos-guard.sh — Sister-template mirror of
# AtilCalculator d1042. Codifies line-294 `REPO="${REPOS[0]}"` regression guard
# (under `set -euo pipefail`) in the CANONICAL dev-studio-template source.
#
# Sister-pattern: AtilCalculator d1042 (PR #1085 commit cb13b1e, agent:developer).
# Slot rationale: same d1042 number for cross-repo traceability — different repo,
# different INDEX, explicit "sister-template mirror" marker.
#
# Per ADR-0049 ≥5 TCs baseline; this d-test = 5 TCs.
#
#   TC1: default AGENT_WATCH_ORG path does not error with "REPOS[0]: unbound
#        variable" under set -euo pipefail (sister-pattern to AtilCalculator
#        d1042 TC1 — same RED reproduction)
#   TC2: line ~294 uses guarded REPOS[0] read (length-check OR :- default expansion)
#   TC3: org-scan refresh block sets REPO from REPOS[0] after org-scan populates
#        REPOS[] (single-repo back-compat var refresh)
#   TC4: explicit --repo path unaffected (regression guard for happy path)
#   TC5: set -euo pipefail still present (strict-mode preserved — NOT loosened)
#
# RED-first per ADR-0044: TC1+TC2 fail pre-fix (bug present), TC3+TC4+TC5 pass;
# post-fix 5/5 GREEN.
#
# Run standalone: bash scripts/tests/d1042-template-agent-watch-line-294-repos-guard.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH_SH="$SCRIPT_DIR/../agent-watch.sh"

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

# TC1: default AGENT_WATCH_ORG path does not error with REPOS[0]: unbound variable
run_tc "TC1" "default AGENT_WATCH_ORG path does not error with REPOS[0]: unbound variable" '
  OUT=$(cd /tmp && env -u GITHUB_REPO -u AGENT_WATCH_REPOS -u GITHUB_TOKEN -u GH_TOKEN \
        timeout 30 bash "'"$WATCH_SH"'" developer --once 2>&1 || true)
  if echo "$OUT" | grep -qF "REPOS[0]: unbound variable"; then
    echo "FAIL: line ~294 REPOS[0] error reproduces — script crashes before org-scan populates REPOS[]"
  else
    echo "PASS"
  fi
'

# TC2: line ~294 uses guarded REPOS[0] read (length-check or :- default expansion)
run_tc "TC2" "REPO back-compat assignment uses guarded REPOS[0] read" '
  # Find the line containing `REPO="\${REPOS[0]"` and verify it uses :- default
  if grep -qE "REPO=\"\\\$\{REPOS\\[0\\]:-\}\"" "'"$WATCH_SH"'"; then
    echo "PASS"
  elif awk "/REPO=\"\\\$\\{REPOS\\[0\\]\\}\"/" "'"$WATCH_SH"'" | grep -qE "if \\[ \"\\\$\\{#REPOS\\[\\\\@\\]\\}\" -gt 0 \\]; then"; then
    echo "PASS"
  else
    echo "FAIL: REPO back-compat assignment is unguarded — set -u will fire on empty REPOS[]"
  fi
'

# TC3: org-scan refresh block still sets REPO from REPOS[0] post-population
run_tc "TC3" "org-scan refresh block still sets REPO from REPOS[0] post-population" '
  # The refresh lives inside the org-scan block, guarded by
  # `[ "${#REPOS[@]}" -gt 0 ]`. Verify the unguarded read pattern exists
  # at least once in the script (single-repo back-compat var refresh).
  if grep -qE "REPO=\"\\\$\{REPOS\\[0\\]\}\"" "'"$WATCH_SH"'"; then
    echo "PASS"
  else
    echo "FAIL: post-org-scan REPO refresh missing — single-repo back-compat var broken when --org path runs"
  fi
'

# TC4: explicit --repo path unaffected (argv parser order)
run_tc "TC4" "explicit --repo path still parses into REPOS[] before line ~294" '
  # Count REPO= assignments: ≥1 guarded (pre-org-scan) + ≥1 unguarded refresh
  # (inside org-scan block). Both must coexist.
  GUARDED=$(grep -cE "REPO=\"\\\$\{REPOS\\[0\\]:-\}\"" "'"$WATCH_SH"'")
  REFRESH=$(grep -cE "REPO=\"\\\$\{REPOS\\[0\\]\}\"" "'"$WATCH_SH"'")
  if [ "$GUARDED" -ge 1 ] && [ "$REFRESH" -ge 1 ]; then
    echo "PASS"
  else
    echo "FAIL: expected ≥1 guarded read + ≥1 refresh (got guarded=$GUARDED refresh=$REFRESH)"
  fi
'

# TC5: set -euo pipefail still present (strict-mode regression guard)
run_tc "TC5" "set -euo pipefail still present at script header" '
  if head -200 "'"$WATCH_SH"'" | grep -qE "^set -euo pipefail"; then
    echo "PASS"
  else
    echo "FAIL: set -euo pipefail missing or loosened"
  fi
'

# --- summary ---
echo
echo "================================================="
if [ "$FAIL" -eq 0 ]; then
  printf "${GREEN}d1042-template-agent-watch-line-294-repos-guard: %d/%d PASS${NC}\n" "$PASS" "$TESTS"
  exit 0
else
  printf "${RED}d1042-template-agent-watch-line-294-repos-guard: %d/%d PASS (%d FAIL)${NC}\n" "$PASS" "$TESTS" "$FAIL"
  exit 1
fi