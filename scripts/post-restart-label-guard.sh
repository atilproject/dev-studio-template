#!/usr/bin/env bash
# post-restart-label-guard.sh — Dev Studio label-guard (idempotent)
# After a watcher service restart, re-apply only labels in
# scripts/restart-stable.txt. All other labels are preserved as-is.
#
# Why this exists
# ---------------
# Sprint 4 P0 fix (AtilCalculator Issue #125 + RCA-15/16/17): after a watcher
# restart, `type:*` and `sprint:*` labels on agent:developer PRs were
# silently dropped (Mechanism A — owner manual drift at restart). The fix is
# a post-restart hook that re-applies only the allowlist labels and never
# touches anything else.
#
# Design refs:
#   AtilCalculator PR #211 (merged 2026-06-21T16:35:47Z)
#   ADR-0031 (owner-override doctrine)
#   Dev-studio-template Issue #261 (this port)
#
# Usage:
#   post-restart-label-guard.sh          # active mode (re-apply allowlist)
#   post-restart-label-guard.sh --dry-run # log-only, no gh writes (first deploy)
#
# Exit codes:
#   0   success (incl. dry-run completion + empty allowlist no-op)
#   1   invalid invocation
#   2   allowlist file missing or unreadable
#   3   gh CLI failure (rate limit, auth, network)
#   4   jq parse failure
#
# Safety posture (per design §Rollback):
#   Ship with --dry-run for the first deploy cycle. After observing one full
#   restart with no regression on the deploy path, owner flips the mode in a
#   follow-up commit. First deploy is zero-risk; rollback is "remove the
#   ExecStartPost= line from the unit file" alone.

set -uo pipefail

# ----- paths ----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOWLIST_FILE="$SCRIPT_DIR/restart-stable.txt"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/post-restart-label-guard.log"
STDERR_LOG="$LOG_DIR/post-restart-label-guard.stderr"

# ----- mode flag ------------------------------------------------------------
DRY_RUN=false
case "${1:-}" in
  --dry-run) DRY_RUN=true ;;
  "")        DRY_RUN=false ;;
  *)         echo "ERROR: unknown arg: $1 (use --dry-run or no args)" >&2; exit 1 ;;
esac

# ----- preflight ------------------------------------------------------------
if [ ! -r "$ALLOWLIST_FILE" ]; then
  echo "ERROR: allowlist not found or unreadable: $ALLOWLIST_FILE" >&2
  exit 2
fi

mkdir -p "$LOG_DIR"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Build allowlist as newline-separated glob patterns.
# Skip blank lines and lines starting with '#'.
ALLOWLIST_PATTERNS="$(grep -vE '^[[:space:]]*(#|$)' "$ALLOWLIST_FILE" || true)"

# ----- log helper -----------------------------------------------------------
log_json_line() {
  # Args: pr_number preserved_csv reapplied_count duration_ms
  local pr_number="$1" preserved_csv="$2" reapplied_count="$3" duration_ms="$4"
  printf '{"ts":"%s","pr":%s,"preserved":%s,"reapplied_count":%s,"duration_ms":%s,"dry_run":%s}\n' \
    "$TIMESTAMP" "$pr_number" "$preserved_csv" "$reapplied_count" "$duration_ms" "$DRY_RUN" \
    >> "$LOG_FILE"
}

# Empty-allowlist no-op (maximum safety, per design §API contract)
if [ -z "$ALLOWLIST_PATTERNS" ]; then
  log_json_line 'null' '[]' '0' '0'
  echo "OK: empty allowlist, all labels preserved (mode=$( [ "$DRY_RUN" = true ] && echo dry-run || echo active ))"
  exit 0
fi

# ----- fetch PRs (single-call pattern per design §API contract) ------------
if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not found in PATH" >&2
  exit 3
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not found in PATH" >&2
  exit 4
fi

PR_JSON="$(gh pr list --label agent:developer --state open --json number,labels --jq '.[] | {number, labels: [.labels[].name]}' 2>"$STDERR_LOG")"
GH_EXIT=$?
if [ $GH_EXIT -ne 0 ]; then
  echo "ERROR: gh pr list failed (exit $GH_EXIT), see $STDERR_LOG" >&2
  echo "[$TIMESTAMP] mode=error step=gh-pr-list exit=$GH_EXIT" >> "$LOG_FILE"
  exit 3
fi

if [ -z "$PR_JSON" ]; then
  echo "[$TIMESTAMP] mode=$( [ "$DRY_RUN" = true ] && echo dry-run || echo active ) step=no-prs" >> "$LOG_FILE"
  echo "OK: no open PRs with agent:developer label, nothing to do"
  exit 0
fi

# ----- label-in-allowlist predicate (shell glob via case) -------------------
# Each pattern is a shell glob (e.g. type:*, sprint:*). Match against full label.
label_in_allowlist() {
  local label="$1" pat
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    # shellcheck disable=SC2254
    case "$label" in
      $pat) return 0 ;;
    esac
  done <<< "$ALLOWLIST_PATTERNS"
  return 1
}

# ----- process each PR ------------------------------------------------------
TOTAL_PRS=0
TOTAL_REAPPLIED=0
TOTAL_PRESERVED=0

while IFS= read -r pr_line; do
  [ -z "$pr_line" ] && continue
  TOTAL_PRS=$((TOTAL_PRS + 1))
  T0=$(date +%s%3N)

  PR_NUMBER="$(echo "$pr_line" | jq -r '.number')"
  if [ -z "$PR_NUMBER" ] || [ "$PR_NUMBER" = "null" ]; then continue; fi

  # Build PRESERVED and REAPPLY arrays in one pass.
  REAPPLY_CSV=""
  PRESERVED_CSV=""
  while IFS= read -r lbl; do
    [ -z "$lbl" ] && continue
    if label_in_allowlist "$lbl"; then
      REAPPLY_CSV="${REAPPLY_CSV:+$REAPPLY_CSV,}$lbl"
    else
      PRESERVED_CSV="${PRESERVED_CSV:+$PRESERVED_CSV,}$lbl"
    fi
  done < <(echo "$pr_line" | jq -r '.labels[]')

  REAPPLY_COUNT=0
  if [ -n "$REAPPLY_CSV" ]; then
    REAPPLY_COUNT=$(echo "$REAPPLY_CSV" | tr ',' '\n' | wc -l | tr -d ' ')
  fi
  PRESERVED_JSON="[]"
  if [ -n "$PRESERVED_CSV" ]; then
    PRESERVED_JSON="[\"$(echo "$PRESERVED_CSV" | sed 's/,/","/g')\"]"
  fi

  if [ "$DRY_RUN" = true ]; then
    T1=$(date +%s%3N)
    DURATION=$((T1 - T0))
    log_json_line "$PR_NUMBER" "$PRESERVED_JSON" "$REAPPLY_COUNT" "$DURATION"
    echo "[$TIMESTAMP] pr=$PR_NUMBER mode=dry-run preserved=$PRESERVED_CSV reapplied=$REAPPLY_CSV"
  else
    if [ -n "$REAPPLY_CSV" ]; then
      # gh pr edit is idempotent for the same label set
      if gh pr edit "$PR_NUMBER" --add-label "$REAPPLY_CSV" >/dev/null 2>>"$STDERR_LOG"; then
        TOTAL_REAPPLIED=$((TOTAL_REAPPLIED + REAPPLY_COUNT))
      else
        echo "WARN: gh pr edit $PR_NUMBER failed (re-apply), continuing" >&2
      fi
    fi
    if [ -n "$PRESERVED_CSV" ]; then
      PRESERVED_COUNT=$(echo "$PRESERVED_CSV" | tr ',' '\n' | wc -l | tr -d ' ')
      TOTAL_PRESERVED=$((TOTAL_PRESERVED + PRESERVED_COUNT))
    fi
    T1=$(date +%s%3N)
    DURATION=$((T1 - T0))
    log_json_line "$PR_NUMBER" "$PRESERVED_JSON" "$REAPPLY_COUNT" "$DURATION"
    echo "[$TIMESTAMP] pr=$PR_NUMBER mode=active preserved=$PRESERVED_CSV reapplied=$REAPPLY_CSV"
  fi
done < <(echo "$PR_JSON" | jq -c '.')

echo "OK: mode=$( [ "$DRY_RUN" = true ] && echo dry-run || echo active ) prs=$TOTAL_PRS preserved=$TOTAL_PRESERVED reapplied=$TOTAL_REAPPLIED"
exit 0
