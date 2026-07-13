#!/usr/bin/env bash
# scripts/post-squash/cluster-lag-detector.sh
#
# Detects cluster-squash events per ADR-0059 §1 (cluster-squash batch-lag detection doctrine).
# Sister-pattern to scripts/post-squash/label-hygiene.sh (RETRO-009 §3 post-squash label hygiene).
#
# Why this script exists
# ----------------------
# Cluster-squash events (≥3 PRs squashed in tight temporal windows) are increasingly common
# (RETRO-009 §14 codification). Manual timestamp correlation for cluster-vs-single squash
# reconstruction is error-prone. This script automates cluster detection + batch-lag metric
# + structured log emission for RETRO curator consumption.
#
# Detection criterion (per ADR-0059 §1 + d064 d-test fixtures):
#   - Window: [current_PR_mergedAt − 600s, current_PR_mergedAt] (10-min lookback, no lookahead)
#   - Threshold: cluster_size >= 3 (current PR + ≥2 sibling PRs in window)
#   - Rationale: TC2 fixture (4 PRs spanning 326s) requires lookback > 60s; ADR-0059 §1
#     "60s window" phrasing imprecise — actual window = 600s lookback per d064 TC2 fixture
#     codification. ADR amendment candidate tracked per ADR-0056 cheaper-fix pattern (Sprint 18+).
#
# API contract (per ADR-0059):
#   Input env vars: PR_NUMBER, MERGED_AT (ISO-8601 UTC), REPO, CLUSTER_ID, DETECTOR_VERSION,
#                   CLUSTER_LAG_LOG (path), FAKE_GH_MERGED (path to merged JSON array)
#   Output: append cluster_lag_detected OR silent_skip JSON event to CLUSTER_LAG_LOG
#   Exit codes:
#     0 — clean (cluster detected and logged, OR silent_skip)
#     2 — config error (missing env vars, FAKE_GH_MERGED unreadable)
#
# Usage (production, via workflow YAML):
#   PR_NUMBER=509 MERGED_AT=2026-06-27T22:00:00Z REPO=atilproject/dev-studio-template \
#   CLUSTER_ID=sprint-17-p1-3-cluster DETECTOR_VERSION=0.1.0 \
#   CLUSTER_LAG_LOG=/var/log/dev-studio/dev-studio-template/cluster-lag.log \
#   FAKE_GH_MERGED=<gh pr list output> \
#   bash scripts/post-squash/cluster-lag-detector.sh
#
# Usage (d-test, fake-gh factory):
#   FAKE_GH_MERGED=/tmp/merged.json \
#   PR_NUMBER=509 MERGED_AT=... CLUSTER_ID=... \
#   bash scripts/post-squash/cluster-lag-detector.sh
#
# d-test: scripts/tests/d064-cluster-lag.sh --self-test (5 TCs RED-first per ADR-0044)
#
# Cross-references:
#   - ADR-0059 §1-§3 (canonical doctrine)
#   - ADR-0044 RED-first TDD (d064 = 5 TCs)
#   - ADR-0048 lens d (silent_skip log emission on no-cluster)
#   - RETRO-009 §3 (label-hygiene.sh sister-pattern)
#   - RETRO-009 §14 (cluster-squash observation origin)
#   - Issue #508 (LIVE INSTANCE, 4-PR cluster @ 326s lag)

set -uo pipefail

# === Env contract ===
: "${PR_NUMBER:?ERROR: PR_NUMBER env var required (per ADR-0059 API contract)}"
: "${MERGED_AT:?ERROR: MERGED_AT env var required (ISO-8601 UTC)}"
: "${REPO:?ERROR: REPO env var required (owner/repo)}"
: "${CLUSTER_ID:?ERROR: CLUSTER_ID env var required (e.g., sprint-17-p1-3-cluster)}"
: "${DETECTOR_VERSION:?ERROR: DETECTOR_VERSION env var required (semver)}"
: "${CLUSTER_LAG_LOG:?ERROR: CLUSTER_LAG_LOG env var required (log file path)}"
: "${FAKE_GH_MERGED:?ERROR: FAKE_GH_MERGED env var required (path to merged JSON)}"

# === Constants per ADR-0059 §1 + d064 TC2/TC4 fixture codification ===
WINDOW_LOOKBACK_SEC=600   # 10 min lookback (d064 TC2 fixture: 4 PRs spanning 326s)
CLUSTER_SIZE_THRESHOLD=3  # ≥3 PRs in window = cluster detected

# === Preflight ===
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required for cluster_lag JSON parse" >&2; exit 2; }
command -v date >/dev/null 2>&1 || { echo "ERROR: date required for ISO-8601 parse" >&2; exit 2; }

# === Read merged PRs JSON ===
if [ ! -r "$FAKE_GH_MERGED" ]; then
  echo "ERROR: FAKE_GH_MERGED file not readable: $FAKE_GH_MERGED" >&2
  exit 2
fi

merged_json="$(cat "$FAKE_GH_MERGED")"
if [ -z "$merged_json" ]; then
  merged_json="[]"
fi

# === F3 fix per ADR-0056 silent_skip doctrine (Option X — explicit jq error check) ===
# Validate merged_json shape: must be JSON array of {number, mergedAt} objects.
# Without this check, malformed JSON silently degrades to silent_skip (cluster_size=1)
# which violates ADR-0056 explicit-logging doctrine. exit 2 on parse failure.
if ! echo "$merged_json" | jq -e 'type == "array" and all(.[]; type == "object" and has("number") and has("mergedAt"))' >/dev/null 2>&1; then
  echo "ERROR: malformed merged.json — must be JSON array of {number, mergedAt} objects (F3 explicit check per ADR-0056 Option X)" >&2
  exit 2
fi

# === Parse current PR timestamp (epoch seconds, UTC) ===
current_ts="$(date -u -d "$MERGED_AT" +%s 2>/dev/null)"
if [ -z "$current_ts" ] || [ "$current_ts" = "0" ]; then
  echo "ERROR: MERGED_AT parse failed: $MERGED_AT (expected ISO-8601 UTC)" >&2
  exit 2
fi

# === Filter PRs in window [current - WINDOW_LOOKBACK_SEC, current] ===
window_start=$((current_ts - WINDOW_LOOKBACK_SEC))

# Build cluster arrays (always include current PR)
pr_numbers_json="$(jq -n --argjson n "$PR_NUMBER" '[$n]')"
squash_ts_json="$(jq -n --arg t "$MERGED_AT" '[$t]')"
min_ts="$current_ts"
max_ts="$current_ts"

# Read sibling PRs from merged JSON
# Schema: [{"number": <int>, "mergedAt": "<ISO-8601 UTC>"}, ...]
while IFS=$'\t' read -r pr_num pr_ts pr_epoch; do
  [ -z "$pr_num" ] && continue
  [ -z "$pr_epoch" ] && continue
  # Skip self (current PR already counted)
  if [ "$pr_num" = "$PR_NUMBER" ]; then
    continue
  fi
  # Window check: [window_start, current_ts]
  if [ "$pr_epoch" -ge "$window_start" ] && [ "$pr_epoch" -le "$current_ts" ]; then
    pr_numbers_json="$(echo "$pr_numbers_json" | jq --argjson n "$pr_num" '. + [$n]')"
    squash_ts_json="$(echo "$squash_ts_json" | jq --arg t "$pr_ts" '. + [$t]')"
    if [ "$pr_epoch" -lt "$min_ts" ]; then min_ts="$pr_epoch"; fi
    if [ "$pr_epoch" -gt "$max_ts" ]; then max_ts="$pr_epoch"; fi
  fi
done < <(echo "$merged_json" | jq -r '.[] | [.number, .mergedAt, (.mergedAt | fromdateiso8601)] | @tsv' 2>/dev/null)

# === Sort pr_numbers numerically (d064 TC5 expects sorted ascending) ===
pr_numbers_json="$(echo "$pr_numbers_json" | jq 'sort')"

# === Decision: cluster_detected vs silent_skip ===
cluster_size="$(echo "$pr_numbers_json" | jq 'length')"
detected_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Ensure log file parent dir exists
mkdir -p "$(dirname "$CLUSTER_LAG_LOG")" 2>/dev/null || true

if [ "$cluster_size" -ge "$CLUSTER_SIZE_THRESHOLD" ]; then
  # === Cluster detected: emit cluster_lag_detected event ===
  cluster_lag_seconds=$((max_ts - min_ts))
  event="$(jq -nc \
    --arg event "cluster_lag_detected" \
    --arg cluster_id "$CLUSTER_ID" \
    --argjson cluster_size "$cluster_size" \
    --argjson cluster_lag_seconds "$cluster_lag_seconds" \
    --argjson pr_numbers "$pr_numbers_json" \
    --argjson squash_timestamps "$squash_ts_json" \
    --arg detected_at "$detected_at" \
    --arg detector_version "$DETECTOR_VERSION" \
    '{
      event: $event,
      cluster_id: $cluster_id,
      cluster_size: $cluster_size,
      cluster_lag_seconds: $cluster_lag_seconds,
      pr_numbers: $pr_numbers,
      squash_timestamps: $squash_timestamps,
      detected_at: $detected_at,
      detector_version: $detector_version
    }')"
  echo "$event" >> "$CLUSTER_LAG_LOG"
  exit 0
else
  # === silent_skip per ADR-0048 lens d (mandatory log emission on no-cluster) ===
  event="$(jq -nc \
    --arg event "silent_skip" \
    --arg reason "cluster_size < threshold (3) — single-PR squash or window exceeded" \
    --argjson pr_number "$PR_NUMBER" \
    --arg merged_at "$MERGED_AT" \
    --arg detector_version "$DETECTOR_VERSION" \
    '{
      event: $event,
      reason: $reason,
      pr_number: $pr_number,
      merged_at: $merged_at,
      detector_version: $detector_version
    }')"
  echo "$event" >> "$CLUSTER_LAG_LOG"
  exit 0
fi