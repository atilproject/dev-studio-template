## queue_empty_with_priority — technical complement spec

**Location**: `scripts/agent-watch.sh` (new query function + new event kind)

### Purpose

Defense-in-depth for the bounded standby doctrine (CLAUDE.md amendment + per-soul-file clauses). When an agent is silent (no `new_events` for N consecutive polls) AND has open P0/P1 work in its queue, emit a synthetic `queue_empty_but_priority_pending` wake. This breaks the agent out of indefinite standby automatically — even if the doctrine rule is somehow bypassed (forgot, misread, edge case).

### Event schema

```json
{
  "id": "queue-empty-priority-<role>-b<bucket>",
  "kind": "queue_empty_but_priority_pending",
  "number": 0,
  "title": "Queue empty but P0/P1 priority work pending — review needed",
  "url": "https://github.com/<owner>/<repo>/issues?q=is%3Aopen+label%3Apriority%3AP0+label%3Aagent%3A<role>",
  "updated_at": "<now ISO>",
  "context": {
    "role": "<role>",
    "silent_polls": 3,
    "priority_items": [
      { "number": 46, "title": "...", "url": "...", "priority": "P0", "labels": ["...", "..."] }
    ],
    "note": "Synthetic wake — watcher has been silent for 3+ polls but role has open P0/P1 work. Per CLAUDE.md bounded-standby doctrine."
  }
}
```

### Implementation sketch (for reference, NOT for commit)

```bash
# queue_empty_with_priority — bounded-standby technical complement.
#
# Fires `queue_empty_but_priority_pending` when:
#   1. last `new_events` for this role was empty for ≥3 consecutive polls, AND
#   2. role has ≥1 OPEN issue with `agent:<role>` AND (`priority:P0` OR `priority:P1`).
#
# Throttle: max 1 fire per 30-min bucket per role (prevent re-fire spam if the
# agent truly has nothing to do — different root cause, different action).
#
# Bypass: `QUEUE_EMPTY_DETECTOR_ENABLED=false` (kill switch for environments
# where the synthetic wake would be noise, e.g., scheduled downtime).
query_queue_empty_with_priority() {
  [ "${QUEUE_EMPTY_DETECTOR_ENABLED:-true}" = "false" ] && { echo '[]'; return 0; }

  local now_epoch bucket silent_threshold
  now_epoch="$(date -u +%s)"
  bucket=$(( now_epoch / 1800 ))  # 30-min buckets

  # Read consecutive silent polls counter from state (advanced by poll_once
  # on every empty `new_events` result).
  local silent_count
  silent_count="$("$STATE_HELPER" get "$ROLE" queue_empty_streak 2>/dev/null || echo 0)"
  silent_threshold="${QUEUE_EMPTY_THRESHOLD_POLLS:-3}"

  if [ "${silent_count:-0}" -lt "$silent_threshold" ]; then
    echo '[]'
    return 0
  fi

  # Throttle: at most 1 fire per 30-min bucket per role
  local last_bucket
  last_bucket="$("$STATE_HELPER" get "$ROLE" queue_empty_last_bucket 2>/dev/null || echo 0)"
  if [ "$last_bucket" = "$bucket" ]; then
    echo '[]'
    return 0
  fi

  # Check for P0/P1 work in role's queue
  local priority_items
  priority_items="$(gh issue list \
    --repo "$REPO" \
    --state open \
    --label "agent:${ROLE}" \
    --limit 50 \
    --json number,title,url,labels \
    --jq "[ .[] |
           (.labels | map(.name)) as \$lbls |
           select(\$lbls | any(. == \"priority:P0\" or . == \"priority:P1\")) |
           { number, title, url, priority: ((\$lbls | map(select(startswith(\"priority:\"))) | first) // \"P?\"), labels: \$lbls } ]" 2>/dev/null || echo '[]')"

  local count
  count="$(echo "$priority_items" | jq 'length')"
  if [ "$count" -eq 0 ]; then
    echo '[]'
    return 0
  fi

  local now_iso
  now_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  # Advance HWM
  "$STATE_HELPER" set "$ROLE" queue_empty_last_bucket "$bucket" >/dev/null 2>&1 || true

  jq -n \
    --arg role "$ROLE" \
    --arg now "$now_iso" \
    --arg bucket "$bucket" \
    --arg repo "$REPO" \
    --argjson items "$priority_items" \
    --argjson silent "$silent_count" '
    [ {
      id: ("queue-empty-priority-" + $role + "-b" + $bucket),
      kind: "queue_empty_but_priority_pending",
      number: 0,
      title: ("Queue empty but P0/P1 priority work pending — " + ($items | length | tostring) + " item(s)"),
      url: ("https://github.com/" + $repo + "/issues?q=is%3Aopen+label%3Apriority%3AP0+label%3Aagent%3A" + $role),
      updated_at: $now,
      context: {
        role: $role,
        silent_polls: $silent,
        priority_items: $items,
        note: "Synthetic wake — bounded-standby technical complement. Per CLAUDE.md amendment + retro A14."
      }
    } ]
  '
}
```

### poll_once integration

```bash
# In poll_once, after the merge step:
new_events_count="$(echo "$new_events" | jq 'length')"
if [ "$new_events_count" -eq 0 ]; then
  # Advance silent counter
  new_streak=$(( ${silent_count:-0} + 1 ))
  "$STATE_HELPER" set "$ROLE" queue_empty_streak "$new_streak" >/dev/null 2>&1 || true
else
  # Reset silent counter
  "$STATE_HELPER" set "$ROLE" queue_empty_streak "0" >/dev/null 2>&1 || true
fi

# Add to query list
queue_empty="$(query_queue_empty_with_priority 2>/dev/null || echo '[]')"

# Add to merge input
```

### State file schema (agent-state.sh)

New fields per role:
- `queue_empty_streak` (int) — number of consecutive polls with empty `new_events`
- `queue_empty_last_bucket` (int) — last 30-min bucket that fired this detector (throttle)

### Test cases (d013-queue-empty-detector.sh, future PR)

- T1: `query_queue_empty_with_priority` function exists in agent-watch.sh
- T2: Kill switch QUEUE_EMPTY_DETECTOR_ENABLED=false bypasses
- T3: Below-threshold silent count (1 or 2 polls) → no event
- T4: At-threshold silent count (3 polls) + P0 in queue → 1 event
- T5: At-threshold silent count (3 polls) + P1 in queue → 1 event
- T6: At-threshold silent count (3 polls) + only P2/P3 in queue → no event
- T7: Same bucket re-fire → suppressed (throttle)
- T8: New bucket → re-fire allowed
- T9: Empty new_events resets streak; non-empty new_events → streak=0
- T10: Event ID format: queue-empty-priority-<role>-b<bucket>

### Scope decision

This is a **separate PR from Issue #46** (different change class — Issue #46 is the ADR-0024 watchdog rewrite, queue-empty detector is the bounded-standby complement). Sequence:
1. Issue #109 (this proposal) → reviewer approval
2. CLAUDE.md amendment PR (human-owned file)
3. Per-soul-file clause PR (5 soul files — could be combined or split per reviewer preference)
4. queue-empty-detector impl PR (developer-owned, includes d013 test)

Steps 2-4 can run in parallel after step 1 approval.
