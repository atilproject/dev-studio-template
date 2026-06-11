#!/bin/bash
# Standalone unit test for D2.1.1 fanout helpers.
# Sources agent-watch.sh's helper section by extracting it.
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/agent-watch.sh"

# Pull out the helper block (between the v3.1 comment and "--- query builders")
awk '/^# v3\.1 \(ADR-0008\)/,/^# --- query builders/' "$SCRIPT" > /tmp/d211-helpers.sh
echo "Extracted $(wc -l < /tmp/d211-helpers.sh) helper lines"

# Source it
source /tmp/d211-helpers.sh

# Override env if needed
export PR_MERGED_FANOUT_DEFAULT="${PR_MERGED_FANOUT_DEFAULT:-orchestrator product-manager developer}"
export PR_MERGED_FANOUT_RULES_ENABLED="${PR_MERGED_FANOUT_RULES_ENABLED:-true}"

PASS=0; FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc — expected '$expected' got '$actual'"
    FAIL=$((FAIL+1))
  fi
}

call() {
  if "$@" >/dev/null 2>&1; then echo "wake"; else echo "skip"; fi
}

echo ""
echo "=== Test 1: default fanout membership ==="
check "orchestrator in default"     wake "$(call role_in_default_fanout orchestrator)"
check "product-manager in default"  wake "$(call role_in_default_fanout product-manager)"
check "developer in default"        wake "$(call role_in_default_fanout developer)"
check "architect NOT in default"    skip "$(call role_in_default_fanout architect)"
check "tester NOT in default"       skip "$(call role_in_default_fanout tester)"

echo ""
echo "=== Test 2: query gate (role_receives_pr_merged) — rules ENABLED ==="
check "orchestrator runs query"     wake "$(call role_receives_pr_merged orchestrator)"
check "architect runs query"        wake "$(call role_receives_pr_merged architect)"
check "tester runs query"           wake "$(call role_receives_pr_merged tester)"
check "developer runs query"        wake "$(call role_receives_pr_merged developer)"

echo ""
echo "=== Test 3: per-PR fanout — empty labels (default-only PR) ==="
check "orchestrator wakes (default)"  wake "$(call role_wakes_for_pr orchestrator '[]')"
check "developer wakes (default)"     wake "$(call role_wakes_for_pr developer '[]')"
check "architect SKIPS (no label)"    skip "$(call role_wakes_for_pr architect '[]')"
check "tester SKIPS (no label)"       skip "$(call role_wakes_for_pr tester '[]')"

echo ""
echo "=== Test 4: per-PR fanout — needs-architect-review ==="
LABELS='["needs-architect-review","type:feature"]'
check "orchestrator wakes (default)"  wake "$(call role_wakes_for_pr orchestrator "$LABELS")"
check "architect wakes (label)"       wake "$(call role_wakes_for_pr architect "$LABELS")"
check "tester SKIPS"                  skip "$(call role_wakes_for_pr tester "$LABELS")"

echo ""
echo "=== Test 5: per-PR fanout — agent:architect alias ==="
LABELS='["agent:architect"]'
check "architect wakes (agent: alias)"  wake "$(call role_wakes_for_pr architect "$LABELS")"
check "tester SKIPS"                    skip "$(call role_wakes_for_pr tester "$LABELS")"

echo ""
echo "=== Test 6: per-PR fanout — needs-tester-signoff ==="
LABELS='["needs-tester-signoff","type:bug","priority:P1"]'
check "tester wakes (label)"            wake "$(call role_wakes_for_pr tester "$LABELS")"
check "architect SKIPS"                 skip "$(call role_wakes_for_pr architect "$LABELS")"
check "PM wakes (default)"              wake "$(call role_wakes_for_pr product-manager "$LABELS")"

echo ""
echo "=== Test 7: per-PR fanout — agent:tester alias ==="
LABELS='["agent:tester","cc:developer"]'
check "tester wakes (agent: alias)"     wake "$(call role_wakes_for_pr tester "$LABELS")"

echo ""
echo "=== Test 8: per-PR fanout — BOTH architect & tester labels (5-role wake) ==="
LABELS='["needs-architect-review","needs-tester-signoff","type:feature"]'
check "orchestrator wakes"              wake "$(call role_wakes_for_pr orchestrator "$LABELS")"
check "PM wakes"                        wake "$(call role_wakes_for_pr product-manager "$LABELS")"
check "developer wakes"                 wake "$(call role_wakes_for_pr developer "$LABELS")"
check "architect wakes"                 wake "$(call role_wakes_for_pr architect "$LABELS")"
check "tester wakes"                    wake "$(call role_wakes_for_pr tester "$LABELS")"

echo ""
echo "=== Test 9: kill switch — rules DISABLED ==="
PR_MERGED_FANOUT_RULES_ENABLED=false
LABELS='["needs-architect-review","needs-tester-signoff"]'
check "default roles unaffected"        wake "$(call role_wakes_for_pr orchestrator "$LABELS")"
check "architect SKIPS (rules off)"     skip "$(call role_wakes_for_pr architect "$LABELS")"
check "tester SKIPS (rules off)"        skip "$(call role_wakes_for_pr tester "$LABELS")"
check "architect query gate CLOSED"     skip "$(call role_receives_pr_merged architect)"
PR_MERGED_FANOUT_RULES_ENABLED=true

echo ""
echo "=== Test 10: kill switch — DEFAULT empty (no one wakes by default) ==="
PR_MERGED_FANOUT_DEFAULT=""
LABELS='[]'
check "orchestrator SKIPS (empty default)" skip "$(call role_wakes_for_pr orchestrator "$LABELS")"
check "developer SKIPS (empty default)"    skip "$(call role_wakes_for_pr developer "$LABELS")"
LABELS='["needs-architect-review"]'
check "architect wakes (label-only)"       wake "$(call role_wakes_for_pr architect "$LABELS")"
check "orchestrator SKIPS (no label match)" skip "$(call role_wakes_for_pr orchestrator "$LABELS")"
PR_MERGED_FANOUT_DEFAULT="orchestrator product-manager developer"

echo ""
echo "======================================"
echo "PASS=$PASS  FAIL=$FAIL"
echo "======================================"
[ "$FAIL" -eq 0 ]
EOF
