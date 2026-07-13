# ADR-0032 — RCA-18 Dedup Buffer TTL Pruning (refutes Issue #216 hypothesis)

**Status:** Proposed
**Date:** 2026-06-21
**Supersedes:** —
**Related:** ADR-0002 (GitHub-Native Autonomy), ADR-0024 (Stale-Verdict Watchdog Schema), Issue #94 (watcher self-cc skip), Issue #216 (RCA-18 filing), Issue #61 (LAST_SEEN frozen Bug A — historical context for the 200-cap rationale)

---

## Context

Issue #216 (RCA-18, P0 incident filed 2026-06-21T19:33Z by @atilcan65) reports
that `scripts/agent-watch.sh` `query_stale_cc` (and `query_stale_verdict`)
"fire on CLOSED/MERGED issues" and that the architect + tester are
"stuck in a loop" because their `processed_event_ids` state files are full
(200-cap) with stale-cc events for closed/merged issues.

I performed a manual RCA on 2026-06-21T19:35-19:40Z to verify the
hypothesis. **The hypothesis is partially incorrect.** The events in the
state file are **historical**, not currently firing. But the
**underlying observation is real**: the dedup buffer has no time-based
pruning, which lets weeks of historical events accumulate and produce
the "stuck-loop" appearance.

### Evidence contradicting the RCA-18 root cause hypothesis

**Claim 1**: "`query_stale_cc` does not filter on issue state"

The function in `scripts/agent-watch.sh` line 769-807 explicitly passes
`--state open` to `gh pr list`:

```bash
gh pr list \
  --repo "$REPO" \
  --label "cc:${ROLE}" \
  --state open \   # ← filter IS present
  --limit 50 \
  --json number,title,url,updatedAt,headRefOid,labels \
  --jq "..."
```

A direct test confirms the filter works:

```bash
$ gh pr list --repo atilproject/AtilCalculator --label "cc:architect" --state all --limit 100
[]    # ← no PRs have cc:architect in ANY state

$ STALE_CC_SEC=900 ROLE=architect REPO=atilproject/AtilCalculator bash -c '
    gh pr list --repo atilproject/AtilCalculator --label "cc:architect" --state open \
      --json number,title,url,updatedAt,headRefOid,labels \
      --jq "[ ... stale filter ... ]"'
[]    # ← query_stale_cc returns [] right now
```

**Claim 2**: "Issue #93 is MERGED, status:done, updated 2026-06-18 — 3 days ago"

Confirmed:

```json
{
  "number": 93,
  "state": "MERGED",
  "mergedAt": "2026-06-18T20:37:48Z",
  "labels": ["type:docs", "status:done"]    # ← cc:architect NOT on current labels
}
```

PR #93 was merged on 2026-06-18T20:37:48Z. It currently has no
`cc:architect` label. A direct `gh pr list --label "cc:architect" --state all`
returns `[]` — confirming PR #93 does NOT trigger any current
`query_stale_cc` event.

**Claim 3**: "Last 5 entries in architect state file are `stale-cc-93-d227ef8-b5939383`"

Confirmed. **But the bucket math refutes the "currently firing" interpretation:**

```
bucket 5939383 = epoch (5939383 × 300) = 1,781,814,900 sec
              = 2026-06-18T20:35:00Z    ← 3 days ago, BEFORE PR #93 merge
current bucket = epoch (1,782,070,788 / 300) = 5940235
              = 2026-06-21T19:39:48Z    ← now
```

The tail entries (`b5939383`, `b5939382`, `b5939381`, …) are from
buckets spanning `2026-06-18T20:35:00Z` through `2026-06-21T19:30:00Z` —
a 3-day window. **These are historical events emitted when PR #93 was
OPEN with `cc:architect` (between 2026-06-18T18:52:56Z label add and
2026-06-18T20:37:48Z merge).** The bucket ID looks "current" only
because the number is large; the actual timestamp is 3 days in the past.

**Claim 4**: "Architect + tester stuck-loop"

The architect's `agent-state.json` shows `last_seen_utc: 2026-06-21T19:34:05Z`
(modified within 6 minutes of RCA-18 filing). PR #215 (ADR-0012 amend for
Issue #213 Layer 2) was opened by architect at 16:35:47Z and is currently
at owner-merge gate (`status:ready`, `cc:human`, verdict-by 20:00Z).
**Architect is NOT stuck** — it shipped Issue #213 Layer 2 ~3 hours
before RCA-18 was filed. Tester's state file shows the same pattern.

### Evidence supporting the underlying observation

The RCA-18 observation that the dedup buffer is "frozen" with 3-day-old
events is **correct and important**. Here is what is actually happening:

1. **Bucket mechanism emits a new event ID every 5 min while a stale
   condition exists.** `query_stale_cc` line 780-781:
   ```bash
   bucket=$(( now_epoch / 300 ))
   ```
   Event ID = `stale-cc-<n>-<sha7>-b<bucket>`. So as long as the PR
   sits open with cc:architect, every 5 min a NEW event ID is emitted.

2. **`cmd_mark` adds the new ID with `unique`.** `agent-state.sh` line 182-185:
   ```jq
   .processed_event_ids = (.processed_event_ids + [$id] | unique)
   ```
   Duplicates within the same bucket are deduped, but cross-bucket
   duplicates are NOT.

3. **`cmd_trim` keeps the last 200.** `agent-state.sh` line 221-223:
   ```jq
   .processed_event_ids = (.processed_event_ids | .[-$max:])
   ```
   No time filter. So when a stale-cc condition resolves (PR closed,
   label removed), the historical event IDs stay in the buffer until
   pushed out by newer events.

4. **Net effect**: a single 4-hour stale-cc window for one PR emits
   4 × 12 = **48 unique event IDs** (4 hours × 12 buckets/hour). A
   week-long stale-cc window emits 7 × 24 × 12 = **2,016 unique
   event IDs** — but only the last 200 survive the trim.

5. **The surviving tail**: dominated by the most-recent historical
   events, which look "current" to a casual reader because the bucket
   ID is large. The actual timestamp is N days in the past.

This is a **legitimate bug**. The buffer doesn't have a TTL, and the
"last 200" semantic is silently biased toward historical events when
newer events are sparse. The RCA-18 narrative ("watcher is firing on
closed issues") is the visible symptom; the real bug is "buffer has no
age filter."

## Decision

**Add time-based pruning to `poll_once`: drop any `processed_event_ids`
entry whose bucket is more than 24h (288 × 5min buckets) older than the
current bucket, BEFORE merging new events.** Apply the same filter in
`query_stale_verdict` (ADR-0024) and `query_missing_expectation` if
those events also use bucket IDs.

### Pseudocode (≤30 lines, no production code in this ADR)

```bash
# RCA-18 fix (ADR-0032): drop processed_event_ids older than 24h.
# Bucket = epoch/300, so 24h = 288 buckets.
# Rationale: prevents historical events from clogging the dedup buffer
# after their underlying stale condition resolves.
local current_bucket prune_cutoff_bucket
current_bucket=$(( now_epoch / 300 ))
prune_cutoff_bucket=$(( current_bucket - 288 ))    # 24h ago

# Filter processed_event_ids: keep entries from buckets >= cutoff.
# Event ID format: "<kind>-...-b<bucket>"
"$STATE_HELPER" set "$ROLE" processed_event_ids "$(jq -n \
  --slurpfile state "$state_file" \
  --argjson cutoff "$prune_cutoff_bucket" '
  [ $state[0].processed_event_ids[] |
    (capture("b(?<bucket>[0-9]+)$").bucket | tonumber) as $b |
    select($b >= $cutoff)
  ]
')" >/dev/null 2>&1 || true
```

Apply this in `poll_once` (line ~1130, before the `query_*` calls) so
all downstream queries see the cleaned dedup buffer.

### Acceptance criteria (revised)

The Issue #216 AC list needs revision because its premise is wrong:

| # | Original AC | Revised AC | Rationale |
|---|---|---|---|
| 1 | RCA-18 fix in `agent-watch.sh` (filter closed/merged in `query_stale_cc` + `query_stale_verdict`) | RCA-32 fix in `agent-watch.sh` (24h TTL pruning in `poll_once`) | Original filter already exists (`--state open`); redundant. |
| 2 | d023 regression test PASS (3+3 case coverage) | d023 regression test PASS: (a) 3 historical stale-cc events from 25h ago are pruned on next poll, (b) 3 stale-cc events from 1h ago are retained, (c) d015 9/9 still PASS | Test the actual fix, not a no-op filter. |
| 3 | d015 (Katman 1+2) still 9/9 PASS | unchanged | Baseline stability. |
| 4 | Architect + tester state files cleared of stale-cc-93/37 events | (replaced) After RCA-32 fix + 24h pass: processed_event_ids contains NO entries from > 24h ago | TTL pruning handles this automatically. Manual `agent-state.sh kick` can accelerate cleanup if needed. |
| 5 | Architect starts Issue #213 Layer 2 work within 30 min of fix | (DELETED — already shipped) | PR #215 opened 16:35:47Z, 3h before RCA-18 filing. |
| 6 | Tester responsive to new PRs within 30 min of fix | unchanged | Verifies no regression. |

### Owner-override scope (parallel to ADR-0031)

If the owner decides RCA-32 is too narrow and wants the broader fix
(label cleanup on close per ADR-0015 §Terminal hand-off, plus buffer
TTL), the scope expands. The architect-recommended floor is RCA-32
(buffer TTL alone), since the `--state open` filter is already correct.

## Consequences

### Positive

- Buffer pollution is bounded to a 24h window. After 24h passes, a
  closed-merged PR's stale-cc events are pruned automatically. The
  "last 5 entries look stale" symptom disappears.
- Dedup semantics become time-bounded: an event ID is "remembered" for
  at most 24h. This matches human intuition (we don't care about events
  from 3 days ago) and matches the `STALE_CC_SEC=900` design (which is
  also 15min-scale, not week-scale).
- No format change to `processed_event_ids`. The fix is purely
  defensive: it adds a filter, doesn't restructure storage.

### Negative

- **Re-fire after 24h**: if a stale-cc condition somehow persists for
  >24h (e.g., a PR truly stuck for a week), the agent will get
  re-woken once per 24h. This is correct behavior — the agent SHOULD
  be re-woken if a week-old PR is still stalled.
- **Slight CPU cost on every poll**: the bucket extraction is a regex
  on every entry (currently ≤200 entries). At 200 entries × 60s poll,
  the cost is negligible (~1ms jq invocation).
- **Existing historical state**: the FIRST poll after deploy will prune
  all events older than 24h. Architect's state file goes from 200 to
  ~5 (last hour's worth of wake_nudge + periodic_backlog_scan).
  This is a one-time cleanup, not a regression.

### Out of scope

- **Pruning per-event-kind with different TTLs**. Considered, rejected:
  every event kind uses the bucket mechanism uniformly; 24h is a
  uniform ceiling. Per-kind tuning can come later if a specific kind
  proves too noisy.
- **Pruning entries with no bucket suffix** (e.g., wake_nudge, periodic_backlog_scan
  which use different ID formats). Considered, rejected: those event
  IDs are bounded by their own throttle (60s polling, 30-min
  `last_synthetic_scan_utc` throttle) and don't accumulate the way
  bucket-keyed IDs do. Leave them alone.
- **Replacing the dedup buffer with a database**. Considered, rejected:
  premature abstraction. The file-based buffer is fine once it has a
  TTL.

## Implementation handoff

Architect owns the ADR + design. **Developer implements** (per
hard rule: architect doesn't write production code). Sprint 4 P1
allocation: 0.5 SP (1-line behavioral change in `poll_once`, ~30
lines including jq logic + d023 regression). Can fold into the existing
Sprint 4 P1 `WATCHER-FIX` story (#94) or stand alone.

**Test contract for developer**:
- `scripts/tests/d023-rca18-ttl-pruning.sh`:
  - Setup: state file with 3 stale-cc events from bucket (current - 300) [25h ago]
    + 3 stale-cc events from bucket (current - 12) [1h ago]
  - Run `poll_once` once
  - Assert: 3 old events PRUNED, 3 recent events RETAINED
  - Assert: d015 regression suite still 9/9 PASS

**Test contract for tester** (sign-off):
- d023 + d015 + manual: state file in steady state contains no entries
  from >24h ago.

## Pending

- Owner (atilcan) approves ADR-0032 (architect-recommended floor).
- Developer implements + opens PR with type:refactor + status:in-review + agent:developer
  + cc:tester + needs-tester-signoff + cc:architect (arch review of the
  jq regex).
- Tester signs off on d023.
- Owner merges. RCA-18 closes.

— @architect, 2026-06-21T19:45:00Z
