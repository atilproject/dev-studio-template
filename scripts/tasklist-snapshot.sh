#!/usr/bin/env bash
# tasklist-snapshot.sh — Persist TodoWrite state to runtime file (VCS-excluded).
#
# Why this exists
# ----------------
# Per ADR-0072 §Layer 2 Task-list Persistence Protocol, agents must persist
# TodoWrite state to state/tasklists/${ROLE}.md so task context survives
# /clear operations (Issue #725 cycle #1638 RCA + co-discovered reprime-storm
# recovery gap). The snapshot file is RUNTIME (gitignored per .gitignore
# .gitignore.tmpl entry), atomic-written (write-to-temp + sync + mv per
# Issue #237 doctrine), and machine-readable (frontmatter + markdown checklist).
#
# Sister-pattern: scripts/atomic-write.sh helper. We use the same write-to-temp
# + mv pattern but inline (not source the helper, since the format spec
# is markdown checklist not JSON — different output shape).
#
# Usage
# -----
#   bash scripts/tasklist-snapshot.sh <ROLE> <JSON_TODO_STATE>
#
# Arguments
# ---------
#   ROLE            one of: orchestrator | product-manager | architect |
#                            developer | tester
#   JSON_TODO_STATE JSON array of {status, content} objects (TodoWrite format)
#                    e.g. '[{"status":"pending","content":"verify-impl"}]'
#
# Output
# ------
#   state/tasklists/${ROLE}.md
#     Format:
#       <!-- tasklist-snapshot role:${ROLE} ts:${ISO8601} -->
#       - [ ] task1
#       - [ ] task2
#       - [ ] task3
#
# Exit codes
# ----------
#   0 — snapshot written atomically
#   1 — bad usage, invalid ROLE, invalid JSON, or write failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="${TASKLIST_STATE_DIR:-$REPO_ROOT/state/tasklists}"

usage() {
  cat >&2 <<EOF
Usage: $0 <ROLE> <JSON_TODO_STATE>

  ROLE              orchestrator|product-manager|architect|developer|tester
  JSON_TODO_STATE   JSON array of {status, content} objects (TodoWrite format)

Examples:
  $0 developer '[{"status":"pending","content":"verify-impl"}]'
  TASKLIST_STATE_DIR=/tmp/snap $0 tester '[{"status":"in_progress","content":"run-d-test"}]'

Environment:
  TASKLIST_STATE_DIR   override output dir (default: \$REPO_ROOT/state/tasklists)
EOF
  exit 1
}

[ $# -eq 2 ] || usage
ROLE="$1"
JSON="$2"

# Validate ROLE (sister-pattern: reprime-agent.sh VALID_ROLES)
VALID_ROLES=(orchestrator product-manager architect developer tester)
ROLE_OK=0
for r in "${VALID_ROLES[@]}"; do
  if [ "$r" = "$ROLE" ]; then
    ROLE_OK=1
    break
  fi
done
if [ "$ROLE_OK" -eq 0 ]; then
  echo "ERROR: invalid ROLE '$ROLE' (must be one of: ${VALID_ROLES[*]})" >&2
  exit 1
fi

# Validate JSON via jq (sister-pattern: atomic-write.sh uses jq filter)
if ! echo "$JSON" | jq empty 2>/dev/null; then
  echo "ERROR: JSON_TODO_STATE is not valid JSON" >&2
  exit 1
fi

# Ensure state dir exists (writable). mkdir -p is idempotent.
if ! mkdir -p "$STATE_DIR" 2>/dev/null; then
  echo "ERROR: cannot create state dir: $STATE_DIR" >&2
  exit 1
fi

SNAPSHOT_FILE="$STATE_DIR/${ROLE}.md"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Atomic write-to-temp + sync + mv pattern per Issue #237 doctrine.
# Temp file in SAME directory as target (required for atomic mv on same FS).
TMP="$(mktemp "${SNAPSHOT_FILE}.atomic.XXXXXX")"
if ! {
  echo "<!-- tasklist-snapshot role:${ROLE} ts:${TS} -->"
  # Markdown checklist: one bullet per TodoWrite entry, content as text.
  # Status mapping per ADR-0072 §Format spec + docs/CONTEXT-HYGIENE.md §7.2:
  #   pending      → "- [ ] "  (unchecked)
  #   in_progress  → "- [ ] "  (unchecked — markdown has no in-progress marker)
  #   completed    → "- [x] "  (checked)
  # Any other status → "- [ ] "  (conservative default — unknown treated as pending)
  echo "$JSON" | jq -r '.[] | "- [" + (if .status == "completed" then "x" else " " end) + "] " + .content'
} > "$TMP" 2>/dev/null; then
  rm -f "$TMP"
  echo "ERROR: failed to write temp snapshot at $TMP" >&2
  exit 1
fi

# Fsync the temp file to ensure content is on disk before mv.
# (mv is atomic on POSIX, but the write may not be flushed yet.)
sync "$TMP" 2>/dev/null || true

# Atomic rename.
if ! mv -f "$TMP" "$SNAPSHOT_FILE"; then
  rm -f "$TMP" 2>/dev/null || true
  echo "ERROR: atomic mv failed: $TMP -> $SNAPSHOT_FILE" >&2
  exit 1
fi

echo "✓ Snapshot written: $SNAPSHOT_FILE (ts=${TS})"