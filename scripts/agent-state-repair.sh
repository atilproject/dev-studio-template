#!/usr/bin/env bash
# agent-state-repair.sh — one-shot migration for the cmd_set --arg bug class
# (ADR-0034, Issue #228 RCA).
#
# What this fixes
# ---------------
# Before ADR-0034, `scripts/agent-state.sh cmd_set` used `jq --arg` to write
# values. `--arg` stores the value as a JSON-escaped STRING, not as the
# parsed JSON value. When callers passed JSON arrays (e.g. the comma-joined
# list of event IDs to `processed_event_ids`), the array got stored as a
# JSON-escaped string. Downstream `cmd_seen` uses `index()` which silently
# breaks on stringified arrays → dedup loop is broken (every event looks new).
#
# This migration restores any agent state file whose `processed_event_ids`
# field is a STRING (the corruption symptom) back to a proper JSON ARRAY.
# After running this once + deploying the ADR-0034 cmd_set fix, the corruption
# cannot recur.
#
# Usage:
#   bash scripts/agent-state-repair.sh         # repair all 5 agent states
#   bash scripts/agent-state-repair.sh --dry-run   # report only, no writes
#
# Env:
#   AGENT_STATE_DIR — override default /var/log/dev-studio/<project>/agent-state
#
# Safety:
#   - Backs up each corrupted file to <file>.bak.<epoch> before editing
#   - Idempotent: already-repaired (array) files are skipped
#   - Refuses to write if JSON parse fails (no data loss)
#
# Exit codes:
#   0 — all files OK (nothing to repair, or repair succeeded)
#   1 — at least one file could not be repaired (manual intervention needed)

set -uo pipefail

# Per-project default (ADR-0010)
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PROJECT_DEFAULT="$(basename "$(cd "$_SCRIPT_DIR/.." && pwd)")"
STATE_DIR="${AGENT_STATE_DIR:-/var/log/dev-studio/$_PROJECT_DEFAULT/agent-state}"

ROLES=(orchestrator product-manager architect developer tester)

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=true ;;
    -h|--help)
      echo "Usage: $0 [--dry-run]"
      echo "  Repairs agent-state <role>.json files where processed_event_ids"
      echo "  was corrupted by the cmd_set --arg stringification bug."
      exit 0
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 127
fi
if [ ! -d "$STATE_DIR" ]; then
  echo "ERROR: STATE_DIR does not exist: $STATE_DIR" >&2
  echo "  (set AGENT_STATE_DIR to override)" >&2
  exit 1
fi

REPAIRED=0
SKIPPED=0
FAILED=0
NOW="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

for role in "${ROLES[@]}"; do
  file="$STATE_DIR/${role}.json"
  if [ ! -f "$file" ]; then
    echo "[skip] $role: no state file at $file"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Detect corruption: processed_event_ids is a string (not an array).
  cur_type="$(jq -r '.processed_event_ids | type // "missing"' "$file" 2>/dev/null)"
  if [ "$cur_type" != "string" ]; then
    echo "[ok]   $role: processed_event_ids is $cur_type (no repair needed)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Corruption detected. Try to parse the string as JSON.
  raw="$(jq -r '.processed_event_ids' "$file")"
  if [ -z "$raw" ] || [ "$raw" = "null" ]; then
    # Empty string or explicit null — reset to empty array.
    new_value='[]'
    parsed_ok=false
  elif echo "$raw" | jq -e . >/dev/null 2>&1; then
    # String IS parseable JSON — restore as parsed value.
    new_value="$raw"
    parsed_ok=true
  else
    # Unparseable — bail to manual.
    echo "[FAIL] $role: processed_event_ids is a string but NOT parseable JSON" >&2
    echo "       raw value: $raw" >&2
    FAILED=$((FAILED + 1))
    continue
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "[dry]  $role: would repair (string → $(echo "$new_value" | jq -c 'type')) — parsed_ok=$parsed_ok"
    REPAIRED=$((REPAIRED + 1))
    continue
  fi

  # Backup + atomic edit
  bak="$file.bak.$(date -u +%s)"
  cp -p "$file" "$bak" || { echo "[FAIL] $role: backup failed" >&2; FAILED=$((FAILED + 1)); continue; }
  if jq --argjson v "$new_value" '.processed_event_ids = $v' "$file" > "$file.tmp" \
       && mv "$file.tmp" "$file"; then
    after_type="$(jq -r '.processed_event_ids | type' "$file")"
    echo "[done] $role: repaired (string → $after_type) — backup at $bak"
    REPAIRED=$((REPAIRED + 1))
  else
    # Restore from backup on failure (data integrity)
    mv "$bak" "$file" 2>/dev/null || true
    echo "[FAIL] $role: jq edit failed; restored from backup" >&2
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "Migration summary ($NOW):"
echo "  repaired: $REPAIRED"
echo "  skipped:  $SKIPPED"
echo "  failed:   $FAILED"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
