#!/usr/bin/env bash
# proactive-board-scan.sh — Standalone orchestrator-only board anomaly sweep.
#
# Per Issue #44 (Sprint 1 ORCH proactive mode A) + Event Model v5 in
# agent-watch.sh: detects board anomalies and emits a single synthetic
# proactive_scan event aggregating all detections. Extracted from
# agent-watch.sh's inline query_proactive_sweep() so the logic can be
# ported to dev-studio-template as a project-agnostic script.
#
# Per AtilCalculator #48 PR-T1 (owner decision 2026-06-21T08:42Z):
#   - One PR per item (no batching)
#   - No dry-runs (test once + continue)
#   - Ship without sprint-boundary waits
#
# Detections (matches inline function behavior):
#   D1: ready_unblocked — status:ready issues with closed blockers
#   D2: orphan_backlog — status:backlog with no cc:* label
#   D3: stalled         — status:in-progress older than STALLED_THRESHOLD_SEC
#                         (default 4h) with no PR opened
#   D4: wip_overflow    — 3+ in-progress (configurable)
#
# Inputs (env vars):
#   REPO                          (required) — e.g. atilproject/AtilCalculator
#   ROLE                          (default: orchestrator)
#   PROACTIVE_SWEEP_ENABLED       (default: true)
#   PROACTIVE_SWEEP_INTERVAL_SEC  (default: 300)
#   STALLED_THRESHOLD_SEC         (default: 14400 = 4h)
#   STATE_HELPER                  (default: scripts/agent-state.sh)
#
# Output: JSON array of synthetic events to stdout (empty array [] if no
# detections). Shape matches agent-watch.sh Event Model v5.
#
# Exit codes:
#   0 = success (regardless of detection count)
#   1 = REPO missing or state helper broken
#
# Kill switches:
#   PROACTIVE_SWEEP_ENABLED=false  → always return []
#   ROLE != orchestrator           → always return []
#
# Called by: agent-watch.sh (orchestrator role only). The wrapper in
# agent-watch.sh (`query_proactive_sweep` shell function) sources this
# script as a fallback OR invokes it via `$(...)` substitution.

set -euo pipefail

# --- help / usage ---
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'EOF'
Usage: proactive-board-scan.sh [REPO]

Standalone orchestrator board anomaly sweep (Issue #44, forward-ported via S29-008).

Arguments:
  REPO              GitHub repo (owner/name). Can also be set via REPO env var.

Environment:
  ROLE                              (default: orchestrator)
  PROACTIVE_SWEEP_ENABLED           (default: true)
  PROACTIVE_SWEEP_INTERVAL_SEC      (default: 300)
  STALLED_THRESHOLD_SEC             (default: 14400 = 4h)

Output: JSON array of synthetic events to stdout.

Exit codes:
  0  Success (regardless of detection count)
  1  REPO missing or state helper broken
EOF
  exit 0
fi

REPO="${REPO:-${1:-}}"

ROLE="${ROLE:-orchestrator}"
PROACTIVE_SWEEP_ENABLED="${PROACTIVE_SWEEP_ENABLED:-true}"
PROACTIVE_SWEEP_INTERVAL_SEC="${PROACTIVE_SWEEP_INTERVAL_SEC:-300}"
STALLED_THRESHOLD_SEC="${STALLED_THRESHOLD_SEC:-14400}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_HELPER="${STATE_HELPER:-$SCRIPT_DIR/agent-state.sh}"

# --- Kill switch + role gate ---
# Per #202 (tester C4): kill switch + role gate run BEFORE REPO check so
# `PROACTIVE_SWEEP_ENABLED=false bash proactive-board-scan.sh` (without REPO)
# returns '[]' unconditionally rather than 'ERROR: REPO required'. The REPO
# check stays as a final guard for the "all gates pass, REPO is empty" case.
if [ "$PROACTIVE_SWEEP_ENABLED" = "false" ]; then
  echo '[]'
  exit 0
fi
if [ "$ROLE" != "orchestrator" ]; then
  echo '[]'
  exit 0
fi

# --- REPO check (after kill switch + role gate) ---
if [ -z "$REPO" ]; then
  echo "ERROR: REPO env var (or arg) is required" >&2
  exit 1
fi

# --- Throttle via HWM ---
now_epoch="$(date -u +%s)"
bucket=$(( now_epoch / 300 ))
interval="$PROACTIVE_SWEEP_INTERVAL_SEC"

last_sweep=""
if [ -x "$STATE_HELPER" ] || [ -f "$STATE_HELPER" ]; then
  last_sweep="$("$STATE_HELPER" get "$ROLE" proactive_sweep_last_utc 2>/dev/null || true)"
fi

if [ -n "$last_sweep" ] && [ "$last_sweep" != "null" ] && [ "$interval" -gt 0 ]; then
  last_epoch="$(date -u -d "$last_sweep" +%s 2>/dev/null || echo 0)"
  elapsed=$(( now_epoch - last_epoch ))
  if [ "$elapsed" -lt "$interval" ]; then
    echo '[]'
    exit 0
  fi
fi

detections='[]'

# --- D1: ready_unblocked ---
ready_issues="$(gh issue list \
  --repo "$REPO" \
  --state open \
  --label "status:ready" \
  --json number,title,body,updatedAt \
  --limit 50 \
  2>/dev/null || echo '[]')"

d1_items="$(echo "$ready_issues" | jq -c '
  [ .[] | (.body // "") as $b |
    ( try (
        ($b | capture("(?i)block(?:ed|s)?\\s+by:?\\s*#?(?<nums>(?:\\s*[#,\\s]*\\d+\\s*)+)"; "g").nums)
        | scan("\\d+")
        | if type == "string" then [.] else . end
      ) catch null
    ) as $nums |
    select($nums != null and ($nums | length) > 0) |
    { number: .number, title: .title, blocker_nums: $nums }
  ]' 2>/dev/null || echo '[]')"

d1_fired='[]'
if [ "$(echo "$d1_items" | jq 'length')" -gt 0 ]; then
  while read -r item; do
    [ -z "$item" ] && continue
    all_closed=true
    nums="$(echo "$item" | jq -r '.blocker_nums[]')"
    for bn in $nums; do
      bstate="$(gh issue view "$bn" --repo "$REPO" --json state --jq '.state' 2>/dev/null || echo "open")"
      if [ "$bstate" != "closed" ]; then
        all_closed=false
        break
      fi
    done
    if [ "$all_closed" = "true" ]; then
      d1_fired="$(echo "$d1_fired" | jq -c --argjson it "$item" '. + [$it]')"
    fi
  done < <(echo "$d1_items" | jq -c '.[]')
fi
if [ "$(echo "$d1_fired" | jq 'length')" -gt 0 ]; then
  detections="$(echo "$detections" | jq -c --argjson items "$d1_fired" \
    '. + [{detection: "ready_unblocked", items: $items}]')"
fi

# --- D2: orphan_backlog ---
orphans="$(gh issue list \
  --repo "$REPO" \
  --state open \
  --label "status:backlog" \
  --json number,title,updatedAt,labels \
  --limit 50 \
  --jq '[ .[] | select(((.labels // []) | map(.name) | any(startswith("cc:"))) | not) | {number, title, age_hours: 0} ]' \
  2>/dev/null || echo '[]')"
if [ "$(echo "$orphans" | jq 'length')" -gt 0 ]; then
  detections="$(echo "$detections" | jq -c --argjson items "$orphans" \
    '. + [{detection: "orphan_backlog", items: $items}]')"
fi

# --- D3: stalled ---
cutoff_iso="$(date -u -d "@$(( now_epoch - STALLED_THRESHOLD_SEC ))" '+%Y-%m-%dT%H:%M:%SZ')"
stalled="$(gh issue list \
  --repo "$REPO" \
  --state open \
  --label "status:in-progress" \
  --json number,title,updatedAt \
  --limit 50 \
  --jq "[ .[] | select(.updatedAt < \"$cutoff_iso\") | {number, title, updatedAt} ]" \
  2>/dev/null || echo '[]')"
if [ "$(echo "$stalled" | jq 'length')" -gt 0 ]; then
  detections="$(echo "$detections" | jq -c --argjson items "$stalled" \
    '. + [{detection: "stalled", items: $items}]')"
fi

# --- D4: wip_overflow (per-role, ADR-0038 §Work-Stream Awareness) ---
# Sprint 17 P1 LIVE INSTANCE: PM + arch both at WIP=2/2 (legitimate AT-CAP)
# fired wip_overflow alerts (false positive). Root cause: previous code
# queried `--wip-count-only '*'` (GLOBAL sum across all roles) and compared
# against hardcoded 2. PM=2 + arch=2 → global=4 > 2 → FIRES (false positive).
#
# Fix: per-role iteration over the 5 lanes from the file ownership matrix
# (ADR-0012). Fire wip_overflow ONLY when a specific role exceeds its
# per-role cap (count > 2). AT-CAP (count == cap) is LEGITIMATE and silent.
#
# Issue #552 AC2 dual mechanism (arch verdict cycle 481): stream: label
# preference + commit-base fallback — both delegated to claim-next-ready.sh
# (single source of truth for work-stream-count logic).
for role in developer product-manager architect tester orchestrator; do
  role_wip="$(bash "$SCRIPT_DIR/claim-next-ready.sh" --wip-count-only "$role" 2>/dev/null \
    | grep -oE 'wip_count=[0-9]+' | cut -d= -f2 || echo 0)"
  if [ "${role_wip:-0}" -gt 2 ]; then
    detections="$(echo "$detections" | jq -c --arg role "$role" --argjson count "$role_wip" \
      '. + [{detection: "wip_overflow", role: $role, count: $count}]')"
  fi
done

# --- Emit aggregated event if any detection fired ---
det_count="$(echo "$detections" | jq 'length')"
if [ "$det_count" -eq 0 ]; then
  echo '[]'
  exit 0
fi

now_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
if [ -x "$STATE_HELPER" ] || [ -f "$STATE_HELPER" ]; then
  "$STATE_HELPER" set "$ROLE" proactive_sweep_last_utc "$now_iso" >/dev/null 2>&1 || true
fi

jq -n \
  --arg now "$now_iso" \
  --arg bucket "$bucket" \
  --arg repo "$REPO" \
  --argjson detections "$detections" '
  [ {
    id: ("proactive-scan-b" + $bucket),
    kind: "proactive_scan",
    number: 0,
    title: ("Proactive scan — " + ($detections | length | tostring) + " detection(s)"),
    url: ("https://github.com/" + $repo + "/issues?q=is%3Aopen"),
    updated_at: $now,
    context: {
      detections: $detections,
      note: "Synthetic wake — proactive sweep caught board anomaly (Issue #44)."
    }
  } ]
'
