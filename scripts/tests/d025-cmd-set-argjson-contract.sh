#!/usr/bin/env bash
# d025-cmd-set-argjson-contract.sh — regression for ADR-0034 cmd_set JSON contract.
#
# Why this test exists
# --------------------
# ADR-0034 (Issue #228 RCA + design) establishes that `scripts/agent-state.sh
# cmd_set` must accept JSON input and use `jq --argjson`. The previous contract
# used `jq --arg` which silently stringified arrays/objects — corrupting
# `processed_event_ids` (and any other array-typed field) on every write.
#
# d023 T10 currently DOCUMENTS the bug class (cmd_set + JSON array → string
# CONFIRMED). After the ADR-0034 fix lands, d023 T10 will be flipped from
# "CONFIRMED" to "FIXED" in the same PR. d025 is the post-fix LOCK-IN test
# for the corrected contract.
#
# Test cases (7, per ADR-0034 §d025 regression test contract):
#   T1: set role key '"hello"' (JSON-quoted) → stored as string "hello"
#   T2: set role key 'hello'    (plain)     → ERROR exit 2 + JSON hint
#   T3: set role key '42'                   → stored as number 42
#   T4: set role key '[1,2,3]'              → stored as array [1,2,3]
#   T5: set role key 'true'                 → stored as bool true
#   T6: set role key 'null'                 → stored as null
#   T7: migration script restores corrupted state (string → array)
#
# Exit code: 0 = all pass, 1 = at least one fail.
#
# Run standalone: bash scripts/tests/d025-cmd-set-argjson-contract.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_SH="$SCRIPT_DIR/../agent-state.sh"
REPAIR_SH="$SCRIPT_DIR/../agent-state-repair.sh"

# Colors (TTY-aware)
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; B=""; D=""; fi

PASS=0; FAIL=0
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required" >&2; exit 127
fi
if [ ! -r "$STATE_SH" ]; then
  echo "ERROR: agent-state.sh not found at $STATE_SH" >&2; exit 127
fi

# Test sandbox — point agent-state.sh at a tmp dir via AGENT_STATE_DIR override.
D025_TMP="$(mktemp -d -t d025-XXXXXX)"
trap 'rm -rf "$D025_TMP"' EXIT

# Per-role state files for type assertions.
write_state() {
  local role="$1"
  local file="$D025_TMP/${role}.json"
  jq -n --arg role "$role" '{
    role: $role,
    last_seen_utc: null,
    last_heartbeat_utc: null,
    processed_event_ids: [],
    poll_interval_sec: 60,
    burst_until_utc: null
  }' > "$file"
  echo "$file"
}

read_field() {
  local file="$1" key="$2"
  jq -r ".${key} // empty" "$file"
}

read_type() {
  local file="$1" key="$2"
  jq -r ".${key} | type" "$file"
}

# ============================================================================
# T1: JSON-quoted string stored as string
# ============================================================================
section "T1: set role key '\"hello\"' → stored as string \"hello\""
T1_STATE="$(write_state d025t1)"
AGENT_STATE_DIR="$D025_TMP" "$STATE_SH" set d025t1 greeting '"hello"' >/dev/null 2>&1
T1_T="$(read_type "$T1_STATE" greeting)"
T1_V="$(read_field "$T1_STATE" greeting)"
if [ "$T1_T" = "string" ] && [ "$T1_V" = "hello" ]; then
  pass "JSON-quoted string stored correctly (type=string, value=hello)"
else
  fail "T1 string round-trip" "expected type=string value=hello; got type=$T1_T value=$T1_V"
fi

# ============================================================================
# T2: plain string (NOT JSON-quoted) → ERROR exit 2 + JSON hint
# ============================================================================
section "T2: set role key 'hello' (plain) → ERROR exit 2 + JSON hint"
T2_STATE="$(write_state d025t2)"
T2_OUT="$(AGENT_STATE_DIR="$D025_TMP" "$STATE_SH" set d025t2 greeting hello 2>&1)"
T2_RC=$?
T2_T="$(read_type "$T2_STATE" greeting 2>/dev/null || echo missing)"
if [ "$T2_RC" -eq 2 ] && echo "$T2_OUT" | grep -qi 'json'; then
  pass "plain string rejected with exit 2 + JSON hint (rc=2, hint present)"
else
  fail "T2 plain-string rejection" "expected rc=2 + JSON hint; got rc=$T2_RC, type=$T2_T, stderr=$T2_OUT"
fi

# ============================================================================
# T3: number 42 stored as number (not string "42")
# ============================================================================
section "T3: set role key '42' → stored as number 42"
T3_STATE="$(write_state d025t3)"
AGENT_STATE_DIR="$D025_TMP" "$STATE_SH" set d025t3 count 42 >/dev/null 2>&1
T3_T="$(read_type "$T3_STATE" count)"
T3_V="$(read_field "$T3_STATE" count)"
if [ "$T3_T" = "number" ] && [ "$T3_V" = "42" ]; then
  pass "numeric stored as number (type=number, value=42)"
else
  fail "T3 number round-trip" "expected type=number value=42; got type=$T3_T value=$T3_V"
fi

# ============================================================================
# T4: JSON array [1,2,3] stored as array (NOT string "[1,2,3]")
# ============================================================================
section "T4: set role key '[1,2,3]' → stored as array [1,2,3]"
T4_STATE="$(write_state d025t4)"
AGENT_STATE_DIR="$D025_TMP" "$STATE_SH" set d025t4 evt_ids '[1,2,3]' >/dev/null 2>&1
T4_T="$(read_type "$T4_STATE" evt_ids)"
T4_LEN="$(jq -r '.evt_ids | length' "$T4_STATE")"
T4_V0="$(jq -r '.evt_ids[0]' "$T4_STATE")"
T4_V2="$(jq -r '.evt_ids[2]' "$T4_STATE")"
if [ "$T4_T" = "array" ] && [ "$T4_LEN" = "3" ] && [ "$T4_V0" = "1" ] && [ "$T4_V2" = "3" ]; then
  pass "JSON array stored as array (type=array, len=3, [0]=1, [2]=3)"
else
  fail "T4 array round-trip" "expected type=array len=3 [0]=1 [2]=3; got type=$T4_T len=$T4_LEN [0]=$T4_V0 [2]=$T4_V2"
fi

# ============================================================================
# T5: bool true stored as bool (not string "true")
# ============================================================================
section "T5: set role key 'true' → stored as bool true"
T5_STATE="$(write_state d025t5)"
AGENT_STATE_DIR="$D025_TMP" "$STATE_SH" set d025t5 flag true >/dev/null 2>&1
T5_T="$(read_type "$T5_STATE" flag)"
T5_V="$(read_field "$T5_STATE" flag)"
if [ "$T5_T" = "boolean" ] && [ "$T5_V" = "true" ]; then
  pass "JSON true stored as boolean (type=boolean, value=true)"
else
  fail "T5 boolean round-trip" "expected type=boolean value=true; got type=$T5_T value=$T5_V"
fi

# ============================================================================
# T6: null stored as null
# ============================================================================
section "T6: set role key 'null' → stored as null"
T6_STATE="$(write_state d025t6)"
AGENT_STATE_DIR="$D025_TMP" "$STATE_SH" set d025t6 nullable null >/dev/null 2>&1
T6_T="$(read_type "$T6_STATE" nullable)"
T6_V="$(read_field "$T6_STATE" nullable 2>/dev/null || echo missing)"
if [ "$T6_T" = "null" ]; then
  pass "JSON null stored as null (type=null)"
else
  fail "T6 null round-trip" "expected type=null; got type=$T6_T value=$T6_V"
fi

# ============================================================================
# T7: Migration script restores corrupted state (string → array)
# ============================================================================
section "T7: scripts/agent-state-repair.sh restores corrupted processed_event_ids"
if [ ! -r "$REPAIR_SH" ]; then
  fail "T7 pre-cond: repair script not found" "expected $REPAIR_SH (per ADR-0034 §Migration path)"
else
  # Use a canonical role name (developer) so the repair script's
  # 5-role iteration finds the file. Per ADR-0034 §Migration path,
  # the script only iterates: orchestrator product-manager architect
  # developer tester — non-canonical names are out of scope.
  T7_ROLE="developer"
  T7_STATE="$D025_TMP/${T7_ROLE}.json"
  # Simulate the corruption: processed_event_ids is a JSON-escaped string, not array.
  jq -n --arg role "$T7_ROLE" --arg s '["wake-nudge-d025t7-a", "wake-nudge-d025t7-b"]' \
    '{role:$role, processed_event_ids:$s, last_seen_utc:null, last_heartbeat_utc:null, poll_interval_sec:60, burst_until_utc:null}' \
    > "$T7_STATE"
  T7_BEFORE_T="$(jq -r '.processed_event_ids | type' "$T7_STATE")"
  # Run migration pointing AGENT_STATE_DIR at our sandbox.
  AGENT_STATE_DIR="$D025_TMP" "$REPAIR_SH" >/dev/null 2>&1
  T7_AFTER_T="$(jq -r '.processed_event_ids | type' "$T7_STATE")"
  T7_AFTER_LEN="$(jq -r '.processed_event_ids | length' "$T7_STATE")"
  if [ "$T7_BEFORE_T" = "string" ] && [ "$T7_AFTER_T" = "array" ] && [ "$T7_AFTER_LEN" = "2" ]; then
    pass "migration restored string→array (before=string, after=array, len=2)"
  else
    fail "T7 migration" "expected before=string after=array len=2; got before=$T7_BEFORE_T after=$T7_AFTER_T len=$T7_AFTER_LEN"
  fi
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
