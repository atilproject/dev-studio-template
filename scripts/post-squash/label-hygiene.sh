#!/usr/bin/env bash
# scripts/post-squash/label-hygiene.sh — RETRO-009 §3 post-squash label hygiene sweep
#
# Why this script exists
# ----------------------
# Sprint 14 P1 cluster observed 3 LIVE INSTANCES of dual-axis lag:
#   - Issue #507 closed with `status:in-progress` not flipped (Layer 5 race)
#   - Issue #508 closed with `status:ready` not flipped
#   - Issue #512 closed with NO status label (cascade-stripped pre-close)
# RETRO-009 §3 codification proposes a post-squash sweep script that
# auto-flips `status:*` → `status:done` on Closes-anchor squash events.
#
# Sister-pattern to scripts/pre-push/branch-base-check.sh (RETRO-009 §1):
# both are bash sweep scripts with explicit exit codes for the
# dispatch-discipline contract.
#
# Sister-pattern d-test: scripts/tests/d061-label-hygiene.sh (9 TCs regression)
#
# Contract
# --------
# Input (stdin): one issue number per line (from webhook Closes-anchor parse).
# Per issue:
#   1. Query current labels via `gh issue view N --json labels --jq '.labels[].name'`
#   2. Identify stale `status:*` labels (in-progress, ready, in-review, blocked)
#      — EXCLUDE status:backlog (pre-work state, preserved)
#      — EXCLUDE status:done (already terminal)
#   3. Remove stale status:*, add status:done
#   4. Preserve all non-status labels (type:*, agent:*, cc:*, priority:*, etc.)
#
# Exit codes (per ADR-0044 RED-first contract):
#   0 — clean, all issues processed
#   1 — runtime error (gh failure mid-batch, partial state may result)
#   2 — config error (no gh, no input, invalid args)
#
# Trigger: invoked by .github/workflows/post-squash-label-hygiene.yml on
# pull_request closed+merged webhook (owner-implementable territory per
# file ownership matrix).
#
# Out of scope (sister-pattern sister):
#   - Closes-anchor parsing (workflow's job)
#   - Webhook signature verification (workflow's job)
#   - Pre-squash label hygiene (orthogonal, future)
#
# Run standalone:
#   echo "507" | bash scripts/post-squash/label-hygiene.sh
#   printf '%s\n' 507 508 512 | bash scripts/post-squash/label-hygiene.sh

set -uo pipefail

# --- preflight: gh required ---
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI required" >&2; exit 2; }

# --- preflight: input must be non-empty ---
# Use a temp file to capture stdin (avoids cat | while subshell pitfall).
stdin_file="$(mktemp)"
trap 'rm -f "$stdin_file"' EXIT
cat > "$stdin_file"

if [ ! -s "$stdin_file" ]; then
  echo "ERROR: no input (expected issue numbers on stdin, one per line)" >&2
  exit 2
fi

# --- status labels to remove (stale, non-terminal, non-prework) ---
# status:backlog — pre-work state, preserved (sweep should never touch)
# status:done    — terminal state, no-op if already present
# All other status:* (in-progress, ready, in-review, blocked) are stale.
STALE_STATUSES_REGEX='^status:(in-progress|ready|in-review|blocked)$'

# --- process each issue ---
processed=0
failed=0
while IFS= read -r issue_num; do
  # Skip blank lines
  [ -z "$issue_num" ] && continue

  # Validate: issue number must be numeric
  if ! [[ "$issue_num" =~ ^[0-9]+$ ]]; then
    echo "ERROR: invalid issue number: '$issue_num' (expected numeric)" >&2
    failed=$((failed + 1))
    continue
  fi

  # Query current labels
  current_labels="$(gh issue view "$issue_num" --json labels --jq '.labels[].name' 2>/dev/null)"
  gh_rc=$?
  if [ "$gh_rc" -ne 0 ]; then
    echo "ERROR: gh issue view #$issue_num failed (rc=$gh_rc)" >&2
    failed=$((failed + 1))
    continue
  fi

  # Identify stale status:* to remove (filter to STALE_STATUSES_REGEX)
  stale_to_remove="$(printf '%s\n' "$current_labels" | grep -E "$STALE_STATUSES_REGEX" || true)"

  # Build gh issue edit args
  edit_args=(--add-label "status:done")
  for label in $stale_to_remove; do
    [ -z "$label" ] && continue
    edit_args+=(--remove-label "$label")
  done

  # Apply
  if ! gh issue edit "$issue_num" "${edit_args[@]}" 2>/dev/null; then
    echo "ERROR: gh issue edit #$issue_num failed" >&2
    failed=$((failed + 1))
    continue
  fi

  processed=$((processed + 1))
done < "$stdin_file"

# --- summary ---
echo "post-squash label hygiene: processed=$processed failed=$failed" >&2

if [ "$failed" -gt 0 ]; then
  exit 1
fi

exit 0
