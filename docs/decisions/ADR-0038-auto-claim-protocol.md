# ADR-0038: Auto-Claim Protocol — agents self-claim highest-priority ready item when WIP < 2

- **Status**: Accepted
- **Date**: 2026-06-22
- **Amended**: 2026-06-27 via Issue #497 — §Work-Stream Awareness (Layer 2 WIP counting by work-stream, not by issue count). See [ADR-0038-amendment-workstream-awareness.md](./ADR-0038-amendment-workstream-awareness.md).
- **Accepted**: 2026-06-22T19:08:39Z (per PR #273 merge by @atilcan65 owner, commit 3d2f947)
- **Deciders**: @architect (design + ADR), @atilcan65 (soul-patch approval, owner-gated), @developer (impl), @tester (sign-off), @orchestrator (stale-detection extension)
- **Related**: Issue #271 (P1 doctrine gap — "no initiative" pattern), Issue #222 (RCA-19 dev idle 8h 42min, family), ADR-0002 (autonomy loop), ADR-0012 (4-cat label invariant), ADR-0031 (owner-override), ADR-0036 (status-transition wake — sister doctrine for orchestrator's flip), TD-011 (PM `agent-watch.sh` issue-level events gap — related, not fixed by this ADR), TD-023 (multi-repo watcher — separate gap)

## Context

The autonomy loop (ADR-0002) is **event-driven**, not **claim-driven**. The watcher emits 4 event kinds (`issue_assigned`, `label_change`, `pr_review_requested`, `pr_comment_mention`). When an agent receives `issue_assigned` for a `status:ready` item and decides "not now", **no re-fire happens**. The item sits in queue indefinitely until external nudge (Telegram ping from owner/orchestrator, or human chat).

**Observed instance (Issue #222, RCA-19, 2026-06-22)**:
- 3 ready items in dev queue (#263, #260, #233) at 18:00Z
- Dev watcher heartbeat FRESH (107s lag)
- Soft-ping from owner at 18:30Z insufficient — "no claim mechanism"
- 8h 42min idle despite ready items

**Root cause**: Watcher is informational. `status:ready` items are passive. The agent must **opt-in** to claim, which contradicts the "no initiative gap" doctrine (Sprint 4 retro A6 — owner-observed pattern).

**Family of related gaps**:
- **RCA-19** (Issue #222): dev idle 8h 42min → ADR-0036 fixed orchestrator's flip signal, but not agent's claim initiative
- **TD-011** (PM `agent-watch.sh` issue-level events): PM has same gap but for `issue_assigned`; not fixed by this ADR (separate, deferred)
- **#221** (auto-ping dual-channel): ping is informational, not directive — same root cause class

## Decision

Implement **§Auto-Claim Protocol** as a 3-layer change (soul patch + helper script + orchestrator detection):

### Layer 1 — Soul patch (human-only territory per file ownership matrix)

Add `## §Auto-Claim Protocol` section to all 4 agent soul docs (`.claude/agents/{developer,architect,product-manager,tester}.md`):

```
## §Auto-Claim Protocol

After events processed and BEFORE going back to sleep, IF WIP_count_for_role < 2 THEN run:
  bash scripts/claim-next-ready.sh <role>

WIP limit = 2 (existing doctrine per ADR-0002 §polling cadence, now hard-enforced by claim script).
```

**Why soul patch (not config)**: doctrine belongs in soul docs; config drifts. Owner gates per file ownership matrix.

### Layer 2 — `scripts/claim-next-ready.sh` (developer territory, ~80 LOC)

Atomic claim helper for any role:

```bash
#!/usr/bin/env bash
# scripts/claim-next-ready.sh <role>
# Atomically claim highest-priority status:ready item assigned to <role>.
# Exit 0 on claim, 1 if nothing to claim, 2 on bad input, 3 if WIP limit reached.
set -euo pipefail
ROLE="${1:?usage: claim-next-ready.sh <role>}"
[[ "$ROLE" =~ ^(developer|architect|product-manager|tester|orchestrator)$ ]] || { echo "ERROR: invalid role"; exit 2; }

# 1. Compute WIP count (status:in-progress issues with agent:<role>)
WIP=$(gh issue list --label "agent:$ROLE" --label "status:in-progress" --state open --json number --jq 'length')
[ "$WIP" -ge 2 ] && { echo "WIP limit reached ($WIP/2), no claim"; exit 3; }

# 2. List ready items for role, sorted priority (P0>P1>P2) > age (oldest first)
CANDIDATE=$(gh issue list --label "agent:$ROLE" --label "status:ready" --state open \
  --json number,title,labels,createdAt,body \
  --jq '[.[] | select((.labels | map(.name) | index("status:blocked")) == null)
            | select((.labels | map(.name) | index("status:in-review")) == null)
            | {number,title,priority: ((.labels | map(.name) | map(select(startswith("priority:"))) | first) // "priority:P3"),
                createdAt, deps: ((.body | capture("(?i)(depends on|blocked by) #(?<n>[0-9]+)") | .n) // "")}]
            | sort_by(if .priority == "priority:P0" then 0 elif .priority == "priority:P1" then 1 elif .priority == "priority:P2" then 2 else 3 end, .createdAt)
            | .[0] // empty')

[ -z "$CANDIDATE" ] && { echo "nothing to claim"; exit 1; }
ISSUE=$(echo "$CANDIDATE" | jq -r .number)
DEPS=$(echo "$CANDIDATE" | jq -r .deps)

# 3. Dependency check (only "depends on" / "blocked by" — Refs is informational, allowed)
if [ -n "$DEPS" ]; then
  DEP_STATE=$(gh issue view "$DEPS" --json state --jq .state)
  [ "$DEP_STATE" != "closed" ] && { echo "skip #$ISSUE: depends on #$DEPS (state=$DEP_STATE)"; exit 1; }
fi

# 4. Atomic status flip + audit comment (mirrors ADR-0036 Part C semantics)
gh issue edit "$ISSUE" --remove-label "status:ready" --add-label "status:in-progress" >/dev/null
gh issue comment "$ISSUE" --body "🤖 auto-claimed by $ROLE at $(date -u +%FT%TZ) (WIP=$((WIP+1))/2)" >/dev/null

# 5. Audit log
mkdir -p /var/log/dev-studio/${PROJECT} 2>/dev/null || true
echo "$(date -u +%FT%TZ) $ROLE claimed #$ISSUE (WIP=$((WIP+1))/2)" >> /var/log/dev-studio/${PROJECT}/auto-claim.log 2>/dev/null || true

echo "claimed #$ISSUE (WIP=$((WIP+1))/2)"
```

**Integration point in `scripts/agent-watch.sh`**: `poll_once` function — after event processing, IF `WIP_count_for_role < 2` THEN call claim-next-ready.sh. If exit 0, **re-poll immediately** to surface the new `status:in-progress` event in the next cycle (so watcher sees its own action).

**Why role-aware in script (not soul-driven)**: agent's WIP is computed from GitHub, not from soul. Soul patch is just the trigger; script is the action.

### Layer 3 — Orchestrator `stale_ready_queue` detection (orchestrator territory)

Extend `proactive_scan` / `periodic_backlog_scan` with new detection:

```
For each role with `agent:<role> AND status:ready` items:
  age = now - oldest status:ready item's createdAt
  IF age > 2h AND no claim activity in audit log:
    emit `stale_ready_queue` detection
    auto-ping role: "<role>, auto-claim protocol should have picked #N. Manually trigger? Or protocol broken?"
  IF still stale after 4h:
    escalate to human via scripts/notify.sh -l human
```

Thresholds (2h/4h) configurable via env var `STALE_READY_HOURS=2` / `STALE_READY_ESCALATE_HOURS=4`.

## d031 spec (regression test contract)

**`scripts/tests/d031-auto-claim.sh` — 4 TCs**:

| # | Test | Coverage |
|---|---|---|
| 1 | 3 ready items with priorities P0/P1/P2 → P0 claimed first | priority sort |
| 2 | 2 ready items with same priority, different ages → oldest claimed | age tie-break |
| 3 | Ready item with `depends on #N` where #N is open → skipped; ready item without deps → claimed | dependency skip |
| 4 | Agent with 2 in-progress items + 1 ready → no claim (WIP limit) | WIP cap |

Plus negative test: agent with 0 ready items → exit 1, no flip. **Total: 4 mandatory TCs + 1 negative**.

## Alternatives considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| A) Status quo + better soft-pings | No code change | Issue #222 showed this doesn't work (8h 42min idle) | ❌ Reject |
| B) Orchestrator manually assigns + tracks WIP | Centralized control | Doesn't scale; orchestrator is already overloaded | ❌ Reject |
| C) Auto-claim protocol (this ADR) | Addresses root cause; distributed; layered; reversible | Auto-claim could grab wrong item; mitigated by dep parser + WIP cap | ✅ **Accept** |
| D) Auto-claim with override-able priority | More flexible | More complex; agent deprioritization is a slippery slope | ❌ Defer (YAGNI) |

## Rationale

- **Why now**: RCA-19 (Issue #222, 8h 42min idle) is the 3rd autonomy-loop incident in 4 days; the gap is now proven, not hypothetical. ADR-0036 (RCA-19 sister) fixed the orchestrator's flip signal; this ADR fixes the agent's claim initiative — together they close the RCA-19 family.
- **Why 3 layers (not 1)**: soul-only (Layer 1) is pure doctrine without enforcement. Script-only (Layer 2) works but doesn't have a failsafe if agent skips the call. Layer 3 (orchestrator detection) catches the failure mode. Defense in depth.
- **Why WIP cap = 2**: existing doctrine (ADR-0002 §polling cadence). Hard-enforced by script.
- **Why dependency parser distinguishes "depends on" / "blocked by" vs "Refs"**: "Refs" is informational (cross-link), not blocking. Skip on hard deps only — over-skipping would starve the queue.
- **Why audit log**: per Issue #222 RCA, silent failures (auto-claim runs but doesn't actually flip) would re-create the original problem. Audit log + re-poll surface the action.
- **Why atomic flip (single `gh issue edit`)**: per ADR-0002 atomicity contract + TD-004 lesson (silent label-flip failure when split into multiple calls).

## Consequences

**Positive**:
- Closes RCA-19 family: dev idle → auto-claim within 2h of queue non-empty
- Closes "no initiative" gap: agents proactively engage ready items
- Distributed: no orchestrator bottleneck
- Reversible: soul patch can be reverted; script can be disabled by owner
- Auditable: `auto-claim.log` + per-issue comment
- Phase 2 ports to template (Issue #271 explicitly defers port to post-Phase 1)

**Negative / tradeoffs**:
- Auto-claim could grab wrong item (mitigated: priority sort, age tie-break, dep parser, WIP cap, audit log)
- Soul patch is human-only territory (correct per file ownership matrix — owner must apply)
- Agent-watch.sh integration touches critical infra (bounded: ~15 lines in `poll_once` per Issue #267 lessons — JSON-quote everything, regression test d031)
- 2h/4h stale thresholds are initial guess — may need tuning

**Follow-up tickets**:
- **Architect (this PR)**: this ADR + design doc + INDEX update
- **Architect (post-merge)**: update `.claude/agents/orchestrator.md` §proactive_scan with stale_ready_queue detection spec
- **Developer (next)**: implement `scripts/claim-next-ready.sh` (~80 LOC) + integrate into agent-watch.sh `poll_once` (~15 LOC) + d031 regression (5 TCs)
- **Tester**: d031 sign-off
- **Human (owner gate)**: apply §Auto-Claim Protocol section to 4 agent soul docs (`.claude/agents/*.md` — human-only territory)
- **Orchestrator (next sprint)**: extend proactive_scan with stale_ready_queue detection
- **PM (Phase 2)**: port claim-next-ready.sh to template repo post-AtilCalc merge
- **Architect (next sprint)**: address TD-011 (PM issue-level events) — separate gap, not fixed by this ADR

## §Eventual Consistency (amendment — Issue #1041, Sprint 29)

> **Origin:** Issue #1041 P1 (INCIDENT — claim-next-ready.sh WIP cap bypass via GitHub search-index eventual consistency). Live instance: 3 claims in 36s while WIP_LIMIT=2; pre-flip search-index returned stale count, allowing cap bypass.

### Data-source contract

The `gh api repos/<repo>/issues?labels=<labels>&state=open` endpoint that drives the WIP cap check uses GitHub's **search-index** (the same backend as `gh issue list --label`). Search-index is **eventually consistent** — a `gh issue edit` that adds `status:in-progress` may not appear in subsequent search-index queries for several seconds (typical window: 1-5s, occasional 30s+).

### Consequence for §Auto-Claim Protocol

The pre-flip WIP cap check (`if [ "$wip_count" -ge "$WIP_LIMIT" ]`) is **necessary but not sufficient** to enforce the cap. Concurrent invocations across multiple agents (or rapid sequential invocations on the same agent) can each see a stale count, all pass the cap check, and collectively exceed the cap.

### Required invariant (amendment)

Every successful claim **MUST** be followed by a post-flip verification before the `audit_log` line is written and the script exits 0. The verification:

1. **Strongly-consistent per-issue view** — `gh issue view N --json labels` hits the strongly-consistent endpoint (not search-index). If `status:in-progress` is not in the labels, the flip did not actually apply (rare; possible if another actor undid it).
2. **Search-index retry with eventual-consistency window** — re-query `gh api repos/<repo>/issues?labels=agent:<role>,status:in-progress&state=open&per_page=100` up to 3× with 1s sleep between attempts. If after retries the count still shows pre-flip value, log a warning but trust the per-issue view (which is authoritative).
3. **Cap re-check** — if post-flip count > WIP_LIMIT, **rollback** (revert label + structured audit log entry) and exit 7. If per-issue view shows flip didn't apply, **rollback** and exit 6.

### Audit log format (AC5)

`auto-claim.log` (append-only, ISO-8601 + role + structured payload) MUST record rollback entries:

```
<ISO-timestamp> <role> ROLLBACK #<issue> (flip-not-applied)
<ISO-timestamp> <role> ROLLBACK #<issue> (wip-over-cap-post-flip=<fresh_count> limit=<WIP_LIMIT>)
```

These entries let the orchestrator's stale-verdict watchdog (ADR-0024) and the post-incident RCA distinguish "claim succeeded, audit silent" (normal) from "claim rolled back, audit recorded" (anomaly → page-on-call).

### Testing requirement

`scripts/tests/d031-claim-next-ready.sh` MUST include at least one TC covering the search-index lag scenario (TC11 added in this amendment). The TC simulates lag via `FAKE_LAG_MODE=1` + `FAKE_LAG_STALE=<pre-flip-count>` + `FAKE_LAG_FRESH=<post-flip-count>` env vars and asserts both `exit 7` AND the structured audit log entry.

### Migration / backward-compat

- Existing d031 TCs TC1-TC10 unchanged (backward-compat verified: 10/10 still green after this amendment lands).
- The fix adds a post-flip verification block; in the happy-path (no lag) the verification succeeds within 1 retry (typically <1s overhead). No new env vars required; existing callers (agent-watch.sh `poll_once`, manual invocations) are unaffected.
- Per ADR-0012 4-cat invariant: rollback flips `status:in-progress` → `status:ready` atomically (no intermediate state visible to other watchers).

### Status

**Proposed** (Sprint 29 W2). Awaiting architect ratification + Issue #1041 owner squash-gate.

## Sprint 4 commitment

| Role | SP | Scope |
|---|---|---|
| **Architect** (me) | 0.5 | This ADR + design doc + INDEX update — DONE in this PR |
| **Developer** | 1.5 | claim-next-ready.sh (~80 LOC) + agent-watch.sh integration (~15 LOC) + d031 regression (5 TCs) |
| **Tester** | 0.5 | d031 sign-off |
| **Human** | 0.25 | soul patch to 4 agent docs |
| **Orchestrator** (Sprint 5+) | 0.5 | stale_ready_queue detection in proactive_scan |
| **Total Phase 1** | **3.25 SP** | |

Sprint 4 EOD 2026-06-22T24:00Z — **only the architect scope fits Sprint 4**. Developer + tester + human scope slips to Sprint 5 (or owner can prioritize if Sprint 5 has bandwidth).

## References

- Issue #271 (P1 doctrine gap, this ADR's parent)
- Issue #222 (RCA-19 dev idle 8h 42min, family)
- ADR-0002 (autonomy loop, polling cadence, WIP limit doctrine)
- ADR-0012 (4-cat label invariant — auto-claim flips `status:*` on already-assigned issue, invariant preserved)
- ADR-0031 (owner-override — soul patch is owner-gated)
- ADR-0036 (status-transition wake, RCA-19 sister fix)
- TD-004 (silent label-flip failure — mitigated by single-call atomic flip)
- TD-011 (PM `agent-watch.sh` issue-level events — related, separate gap)
- TD-023 (multi-repo watcher — separate gap)
- Issue #267 (JSON-quote cmd_set — agent-watch.sh integration must apply this lesson)
- Issue #221 (auto-ping dual-channel — same "informational vs directive" root cause class)
- File ownership matrix (`.claude/` human-only, `scripts/` developer territory, `.github/workflows/` human-only)
