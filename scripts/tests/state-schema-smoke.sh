#!/usr/bin/env bash
# state-schema-smoke.sh — agent-state.sh smoke tests
#
# Covers:
#   - Fresh init declares all 9 v3 fields (role, last_seen_utc,
#     last_heartbeat_utc, processed_event_ids, poll_interval_sec,
#     burst_until_utc, pr_merged_last_seen_utc, pr_labeled_last_seen_utc,
#     polled_at_utc).
#   - get/set roundtrip works.
#   - mark + seen + trim behave correctly.
#   - heartbeat bumps last_heartbeat_utc only (not last_seen_utc).
#   - stale exits 0 when fresh, 1 when stale.
#   - kick removes only matching dedup entries.
#   - BACKWARD-COMPAT: a hand-rolled v2 state file (missing the 3 v3 fields)
#     is backfilled on next `init` call without losing existing data.
#
# Exit code: 0 = all pass, 1 = at least one fail.
#
# Run standalone: bash scripts/tests/state-schema-smoke.sh
# Integrated:     called as T7 from e2e-pilot.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_SH="$SCRIPT_DIR/../agent-state.sh"

# Isolated state dir so we don't touch /var/log/dev-studio
WORK_DIR="$(mktemp -d -t state-schema-smoke.XXXXXX)"
export AGENT_STATE_DIR="$WORK_DIR"

# Counters / output helpers (mirror e2e-pilot.sh style)
PASS=0
FAIL=0
FAIL_NAMES=()
B='\033[1m'; G='\033[0;32m'; R='\033[0;31m'; D='\033[0m'

pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() {
  printf "  ${R}✗ FAIL${D} — %s\n" "$1"
  [ -n "${2:-}" ] && printf "    ${R}%s${D}\n" "$2"
  FAIL=$((FAIL+1))
  FAIL_NAMES+=("$1")
}

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

section() {
  printf "\n${B}==== %s ====${D}\n" "$1"
}

# --- Preflight ---
section "Preflight"
if [ -x "$STATE_SH" ] || [ -f "$STATE_SH" ]; then
  pass "agent-state.sh found at $STATE_SH"
else
  fail "agent-state.sh missing at $STATE_SH"
  echo "Cannot continue."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  fail "jq not installed — required by agent-state.sh"
  exit 1
else
  pass "jq present"
fi

ROLE="test-smoke"
STATE_FILE="$WORK_DIR/${ROLE}.json"

# --- T1: Fresh init declares all 9 v3 fields ---
section "T1 — Fresh init schema"
bash "$STATE_SH" init "$ROLE" >/dev/null
if [ -f "$STATE_FILE" ]; then
  pass "state file created"
else
  fail "state file not created at $STATE_FILE"
fi

# Required fields per v3 schema
REQUIRED_FIELDS=(
  role
  last_seen_utc
  last_heartbeat_utc
  processed_event_ids
  poll_interval_sec
  burst_until_utc
  pr_merged_last_seen_utc
  pr_labeled_last_seen_utc
  polled_at_utc
)
MISSING=()
for f in "${REQUIRED_FIELDS[@]}"; do
  if ! jq -e "has(\"$f\")" "$STATE_FILE" >/dev/null 2>&1; then
    MISSING+=("$f")
  fi
done
if [ "${#MISSING[@]}" -eq 0 ]; then
  pass "all 9 v3 fields present"
else
  fail "missing fields: ${MISSING[*]}"
fi

# Field defaults
[ "$(jq -r '.role' "$STATE_FILE")" = "$ROLE" ] \
  && pass "role default correct" \
  || fail "role default wrong (expected $ROLE)"
[ "$(jq -r '.processed_event_ids | length' "$STATE_FILE")" = "0" ] \
  && pass "processed_event_ids initialized empty" \
  || fail "processed_event_ids not empty on fresh init"
[ "$(jq -r '.pr_merged_last_seen_utc' "$STATE_FILE")" = "null" ] \
  && pass "pr_merged_last_seen_utc defaults to null" \
  || fail "pr_merged_last_seen_utc not null on fresh init"
[ "$(jq -r '.pr_labeled_last_seen_utc' "$STATE_FILE")" = "null" ] \
  && pass "pr_labeled_last_seen_utc defaults to null" \
  || fail "pr_labeled_last_seen_utc not null on fresh init"
[ "$(jq -r '.polled_at_utc' "$STATE_FILE")" = "null" ] \
  && pass "polled_at_utc defaults to null" \
  || fail "polled_at_utc not null on fresh init"

# --- T2: get/set roundtrip ---
section "T2 — get/set roundtrip"
bash "$STATE_SH" set "$ROLE" pr_merged_last_seen_utc "2026-06-13T10:00:00Z" >/dev/null
GOT="$(bash "$STATE_SH" get "$ROLE" pr_merged_last_seen_utc)"
[ "$GOT" = "2026-06-13T10:00:00Z" ] \
  && pass "set/get roundtrip pr_merged_last_seen_utc" \
  || fail "set/get roundtrip failed: got '$GOT'"

bash "$STATE_SH" set "$ROLE" polled_at_utc "2026-06-13T10:05:00Z" >/dev/null
GOT="$(bash "$STATE_SH" get "$ROLE" polled_at_utc)"
[ "$GOT" = "2026-06-13T10:05:00Z" ] \
  && pass "set/get roundtrip polled_at_utc" \
  || fail "set/get roundtrip polled_at_utc failed: got '$GOT'"

# --- T3: mark + seen + trim ---
section "T3 — event dedup"
bash "$STATE_SH" mark "$ROLE" "evt-001" >/dev/null
bash "$STATE_SH" mark "$ROLE" "evt-002" >/dev/null
bash "$STATE_SH" mark "$ROLE" "evt-001" >/dev/null  # idempotent (unique)

SEEN_001="$(bash "$STATE_SH" seen "$ROLE" "evt-001")"
SEEN_999="$(bash "$STATE_SH" seen "$ROLE" "evt-999")"
[ "$SEEN_001" = "true" ] && pass "seen returns true for marked event" || fail "seen returned '$SEEN_001' for marked event"
[ "$SEEN_999" = "false" ] && pass "seen returns false for unmarked event" || fail "seen returned '$SEEN_999' for unmarked event"

COUNT="$(jq '.processed_event_ids | length' "$STATE_FILE")"
[ "$COUNT" = "2" ] && pass "mark is idempotent (no duplicates)" || fail "expected 2 unique entries, got $COUNT"

# Add many to test trim
for i in $(seq 3 15); do
  bash "$STATE_SH" mark "$ROLE" "evt-$(printf '%03d' "$i")" >/dev/null
done
bash "$STATE_SH" trim "$ROLE" 5 >/dev/null
COUNT="$(jq '.processed_event_ids | length' "$STATE_FILE")"
[ "$COUNT" = "5" ] && pass "trim caps to N=5" || fail "trim expected 5, got $COUNT"

# Verify trim kept tail (FIFO)
LAST="$(jq -r '.processed_event_ids[-1]' "$STATE_FILE")"
[ "$LAST" = "evt-015" ] && pass "trim keeps tail (FIFO)" || fail "trim tail wrong: got '$LAST', expected evt-015"

# --- T4: heartbeat vs last_seen ---
section "T4 — heartbeat semantics"
BEFORE_HB="$(jq -r '.last_heartbeat_utc' "$STATE_FILE")"
BEFORE_LS="$(jq -r '.last_seen_utc' "$STATE_FILE")"
sleep 1
bash "$STATE_SH" heartbeat "$ROLE" >/dev/null
AFTER_HB="$(jq -r '.last_heartbeat_utc' "$STATE_FILE")"
AFTER_LS="$(jq -r '.last_seen_utc' "$STATE_FILE")"
[ "$BEFORE_HB" != "$AFTER_HB" ] && pass "heartbeat bumps last_heartbeat_utc" || fail "heartbeat did not bump last_heartbeat_utc"
[ "$BEFORE_LS" = "$AFTER_LS" ] && pass "heartbeat does NOT touch last_seen_utc" || fail "heartbeat unexpectedly changed last_seen_utc"

# --- T5: stale check ---
section "T5 — stale check"
bash "$STATE_SH" heartbeat "$ROLE" >/dev/null
if bash "$STATE_SH" stale "$ROLE" 300 >/dev/null 2>&1; then
  pass "stale returns 0 (fresh) when heartbeat recent"
else
  fail "stale returned non-zero on fresh heartbeat"
fi

# Force-set old heartbeat to test stale=1 path
jq --arg old "2020-01-01T00:00:00Z" '.last_heartbeat_utc = $old' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
if ! bash "$STATE_SH" stale "$ROLE" 60 >/dev/null 2>&1; then
  pass "stale returns 1 when heartbeat old (2020)"
else
  fail "stale returned 0 on 2020 heartbeat (expected 1)"
fi

# --- T6: kick ---
section "T6 — kick (pattern remove)"
# Reset processed_event_ids
jq '.processed_event_ids = ["pr-review-26-abc","pr-review-26-def","pr-review-27-ghi","other-99"]' \
  "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
bash "$STATE_SH" kick "$ROLE" "pr-review-26" >/dev/null
REMAINING="$(jq -r '.processed_event_ids | join(",")' "$STATE_FILE")"
EXPECTED="pr-review-27-ghi,other-99"
[ "$REMAINING" = "$EXPECTED" ] \
  && pass "kick removes only matching entries" \
  || fail "kick result wrong: '$REMAINING' (expected '$EXPECTED')"

# --- T7: BACKWARD-COMPAT — v2 file backfilled to v3 ---
section "T7 — backward-compat (v2 → v3 backfill)"
V2_ROLE="legacy-v2"
V2_FILE="$WORK_DIR/${V2_ROLE}.json"
# Hand-roll a minimal v2 state file (no v3 fields, no last_heartbeat_utc).
# This simulates a state file written by an older agent-state.sh version.
cat > "$V2_FILE" <<'EOF'
{
  "role": "legacy-v2",
  "last_seen_utc": "2026-05-01T12:00:00Z",
  "processed_event_ids": ["legacy-evt-1", "legacy-evt-2"],
  "poll_interval_sec": 60,
  "burst_until_utc": null
}
EOF

# Call init → should backfill missing fields, not touch existing ones
bash "$STATE_SH" init "$V2_ROLE" >/dev/null

# Existing data preserved?
[ "$(jq -r '.last_seen_utc' "$V2_FILE")" = "2026-05-01T12:00:00Z" ] \
  && pass "backfill preserves existing last_seen_utc" \
  || fail "backfill clobbered last_seen_utc"
[ "$(jq -r '.processed_event_ids | length' "$V2_FILE")" = "2" ] \
  && pass "backfill preserves processed_event_ids" \
  || fail "backfill clobbered processed_event_ids"
[ "$(jq -r '.processed_event_ids[0]' "$V2_FILE")" = "legacy-evt-1" ] \
  && pass "backfill preserves processed_event_ids content" \
  || fail "processed_event_ids content corrupted"

# New v3 fields added?
NEW_FIELDS=(last_heartbeat_utc pr_merged_last_seen_utc pr_labeled_last_seen_utc polled_at_utc)
ALL_ADDED=1
for f in "${NEW_FIELDS[@]}"; do
  if ! jq -e "has(\"$f\")" "$V2_FILE" >/dev/null 2>&1; then
    fail "backfill missing field: $f"
    ALL_ADDED=0
  fi
done
[ "$ALL_ADDED" = "1" ] && pass "backfill added all 4 v3 fields"

# Backfilled v3 *_last_seen / polled_at default to null
[ "$(jq -r '.pr_merged_last_seen_utc' "$V2_FILE")" = "null" ] \
  && pass "backfill: pr_merged_last_seen_utc → null" \
  || fail "backfill: pr_merged_last_seen_utc not null"
[ "$(jq -r '.pr_labeled_last_seen_utc' "$V2_FILE")" = "null" ] \
  && pass "backfill: pr_labeled_last_seen_utc → null" \
  || fail "backfill: pr_labeled_last_seen_utc not null"
[ "$(jq -r '.polled_at_utc' "$V2_FILE")" = "null" ] \
  && pass "backfill: polled_at_utc → null" \
  || fail "backfill: polled_at_utc not null"

# Idempotent: second init call should not change anything
SNAPSHOT="$(cat "$V2_FILE")"
bash "$STATE_SH" init "$V2_ROLE" >/dev/null
SECOND="$(cat "$V2_FILE")"
[ "$SNAPSHOT" = "$SECOND" ] \
  && pass "backfill is idempotent (no-op on second init)" \
  || fail "backfill mutated file on idempotent second call"

# --- Summary ---
section "Summary"
printf "  Total: %d\n" "$((PASS + FAIL))"
printf "  ${G}Pass:  %d${D}\n" "$PASS"
printf "  ${R}Fail:  %d${D}\n" "$FAIL"

if [ "$FAIL" -eq 0 ]; then
  printf "\n${G}✓ ALL TESTS PASSED${D}\n"
  exit 0
else
  printf "\n${R}Failed tests:${D}\n"
  for n in "${FAIL_NAMES[@]}"; do
    printf "  - %s\n" "$n"
  done
  exit 1
fi
