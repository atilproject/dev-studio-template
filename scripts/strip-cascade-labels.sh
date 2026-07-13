#!/usr/bin/env bash
# strip-cascade-labels.sh — idempotent cascade-strip for PR/Issue labels
#
# Why this exists
# ---------------
# Codifies ADR-0056 §Layer 5 idempotency reconcile. When a "ghost" PR
# or PR cluster's DELETE 404s fire (e.g. PR #553 + PR #562 §32 LIVE
# INSTANCES #7 + #8), re-running the strip on an already-clean label
# set must exit 0, not error.
#
# Sister-pattern to d054 (Closes-anchor strict format), d058 (claim
# work-stream awareness), d060 (pre-push branch-base check).
#
# Doctrine anchors:
# - ADR-0056 §Layer 5 idempotency reconcile
# - ADR-0012 §cc:human preservation (owner merge gate)
# - ADR-0009 §D2.2 needs-tester-signoff + needs-architect-review preservation
# - §32 LIVE INSTANCES #7 + #8 (PR #553 + PR #562 DELETE 404 family)
# - RETRO-011 §32 LIVE INSTANCE #14 (closes-anchor prose gap, sister-pattern)
#
# Behavior:
# 1. If PR 404 (deleted/closed before strip) → exit 0 (silent-skip)
# 2. Re-running on already-stripped labels → exit 0 (idempotent)
# 3. NEVER strip cc:human, needs-tester-signoff, needs-architect-review
# 4. Transient gh errors → retry 3x with exponential backoff (1s/2s/4s)
# 5. Audit log entry per strip call (no duplicate on idempotent re-run)
#
# Usage:
#   strip-cascade-labels.sh <PR_NUMBER> <label1> [label2] ...
#
# Exit codes:
#   0 = success (including idempotent no-op + 404 silent-skip)
#   1 = genuine error (non-404, non-rate-limit, after retries exhausted)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AUDIT_LOG="${AUDIT_LOG:-/var/log/dev-studio/AtilCalculator/cascade-strip.log}"

# Preflight
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI required" >&2; exit 1; }

if [ $# -lt 2 ]; then
  echo "Usage: $0 <PR_NUMBER> <label1> [label2] ..." >&2
  exit 1
fi

PR_NUMBER="$1"
shift

# Labels that are NEVER stripped (preservation doctrine)
PROTECTED_LABELS=(
  "cc:human"
  "needs-tester-signoff"
  "needs-architect-review"
)

# Filter input labels against protected list
LABELS_TO_STRIP=()
for label in "$@"; do
  skip=0
  for protected in "${PROTECTED_LABELS[@]}"; do
    if [ "$label" = "$protected" ]; then
      skip=1
      break
    fi
  done
  if [ "$skip" -eq 0 ]; then
    LABELS_TO_STRIP+=("$label")
  fi
done

# Audit log helper (idempotent: same PR+labels in window → single entry)
audit() {
  local pr="$1"
  shift
  local labels="$*"
  local key="${pr}:${labels}"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # Idempotent: dedupe by key within same minute
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
  if [ -f "$AUDIT_LOG" ] && grep -q "^${key} " "$AUDIT_LOG" 2>/dev/null; then
    return 0
  fi
  echo "${key} ${now}" >> "$AUDIT_LOG" 2>/dev/null || true
}

# Check PR existence (404 detection)
pr_exists() {
  local pr="$1"
  gh pr view "$pr" --json state --jq '.state' >/dev/null 2>&1
}

# Retry helper (transient gh errors)
retry_gh() {
  local max_attempts=3
  local base_delay_ms=1000
  local attempt=1
  while [ "$attempt" -le "$max_attempts" ]; do
    if "$@"; then
      return 0
    fi
    local rc=$?
    if [ "$attempt" -lt "$max_attempts" ]; then
      local delay_ms=$((base_delay_ms * (1 << (attempt - 1))))
      sleep "$(echo "scale=3; $delay_ms / 1000" | bc 2>/dev/null || echo "1")"
      attempt=$((attempt + 1))
      continue
    fi
    return "$rc"
  done
}

# Main logic
# Step 1: Protection check FIRST (pure function, no I/O, ADR-0012 + ADR-0009)
# Testable in isolation without pr_exists dependency.
if [ "${#LABELS_TO_STRIP[@]}" -eq 0 ]; then
  # All labels were protected (nothing to strip) → idempotent no-op
  audit "$PR_NUMBER" "all-protected"
  exit 0
fi

# Step 2: PR existence check (404 silent-skip per ADR-0056)
if ! pr_exists "$PR_NUMBER"; then
  # 404 / deleted / not found → silent-skip per ADR-0056
  audit "$PR_NUMBER" "404-silent-skip"
  exit 0
fi

# Strip labels (idempotent: gh api tolerates missing labels)
LABELS_CSV=$(IFS=,; echo "${LABELS_TO_STRIP[*]}")
if retry_gh gh pr edit "$PR_NUMBER" --remove-label "$LABELS_CSV" 2>/dev/null; then
  audit "$PR_NUMBER" "$LABELS_CSV"
  exit 0
else
  exit 1
fi