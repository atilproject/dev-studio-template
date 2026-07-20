# ADR-0002 — Autonomy Loop (GitHub-native wake-up)

**Status:** Accepted
**Date:** 2026-06-21
**Deciders:** @architect, @orchestrator, @product-manager, @developer, @tester, @atilcan65 (owner)
**Supersedes:** —
**Related:** `.claude/CLAUDE.md` §Autonomy Loop (owner-only file; canonical content mirrored in this ADR), [ADR-0010](./ADR-0010-per-project-watchers.md) (Per-Project Systemd Watchers), [ADR-0012](./ADR-0012-required-label-set.md) (Required Label Set), [ADR-0013](./ADR-0013-status-label-to-board-sync.md) (Status → Board Sync), [ADR-0015](./ADR-0015-atomic-agent-handoff.md) (Atomic Hand-off), [ADR-0020](./ADR-0020-label-mutation-transactionality.md) (Label-Mutation Transactionality), [ADR-0021](./ADR-0021-docs-pr-convention.md) (Docs PR Convention), [ADR-0024](./ADR-0024-stale-verdict-watchdog-schema.md) (Stale-Verdict Watchdog), [ADR-0025](./ADR-0025-bound-standby-exception.md) (Bound Standby Exception), [ADR-0026](./ADR-0026-queue-empty-mention-check.md) (Queue-Empty Wake), [TD-011](../tech-debt.md) (PM watcher gap), [Issue #46](https://github.com/atilproject/AtilCalculator/issues/46) (P0 chore, stale-verdict), [Issue #109](https://github.com/atilproject/AtilCalculator/issues/109) (bound standby), [Issue #113](https://github.com/atilproject/AtilCalculator/issues/113) (issue assigneeship authority), [Issue #203](https://github.com/atilproject/AtilCalculator/issues/203) (this ADR's filing issue), `scripts/agent-watch.sh`

---

## Context

Before the Autonomy Loop, agent coordination depended entirely on **human-mediated pings via Telegram**. The owner (or another agent) would send a message to Telegram, and a human would notice and route the work. This created three structural problems:

1. **Single-channel bottleneck** — Telegram is human-readable; agents cannot poll it. Multi-agent coordination required a human in the loop on every wake event, defeating the purpose of autonomous agents.
2. **No persistence** — Telegram messages scroll; an agent waking from a tmux restart loses the wake signal entirely.
3. **No state machine** — Without structured triggers, agents had no consistent way to know *which* work item to pick up, *who* currently holds the queue, or *when* a peer is waiting.

The team needed a **GitHub-native, agent-readable, stateful wake-up mechanism** that any agent could poll independently and that paired naturally with the existing human-readable Telegram notification channel.

## Decision

**The Autonomy Loop is a 60-second polling loop in `scripts/agent-watch.sh <role>` that reads GitHub state and emits structured wake events for the calling agent.** It pairs with the **Auto-Ping Hard-Rule** (`scripts/notify.sh -l <role>`) which mirrors each wake to Telegram for human visibility. The two together form a 2-channel coordination substrate: GitHub for agents, Telegram for humans.

The loop is the **single source of truth for "what is in my queue"**. No agent should ask a human "is there work for me?" — they poll, find out, and act.

## Rationale

### Why GitHub as the canonical artefact store

- **Multi-agent readable**: Every agent can read GitHub state via `gh` CLI or API. Telegram is human-only.
- **Persistent**: Issues, PRs, and label events are durable. An agent waking from a tmux restart can recover the full state.
- **Webhook-driven**: GitHub emits `labeled`, `unlabeled`, `assigned`, `review_requested`, `mentioned` events. These map directly to the 4 wake kinds (see below).
- **Already the project substrate**: We were already using GitHub Issues, PRs, and labels for the project board. The Autonomy Loop reuses this substrate instead of introducing a new state store.

### Why polling instead of webhooks

- **Simplicity**: A 60-second cron job is operationally trivial. No public webhook endpoint, no public URL, no TLS cert rotation.
- **Self-hosted**: All state is local (`/var/log/dev-studio/AtilCalculator/agent-state/<role>.json`). No external service dependency.
- **Robust to missed events**: `processed_event_ids` dedup means a missed event is replayed on the next poll. Webhook loss requires manual re-trigger.
- **Rate-limit safe**: 60s polling against a role-scoped query stays well within GitHub's 5000 req/hr limit per token.

### Why pair with Telegram (Auto-Ping Hard-Rule)

A wake signal that reaches only agents still leaves the human in the dark. The Auto-Ping Hard-Rule ensures every agent action that hands off work also writes a Telegram message. The human sees the agent-to-agent coordination as a read-only observer, intervening only on doctrine-level decisions (per CLAUDE.md §Escalation exceptions).

### Why 60 seconds

- **Fast enough** to feel "real-time" for human coordination (the owner never waits more than 60s for an agent to pick up).
- **Slow enough** to stay well under GitHub API rate limits (60s × 5 agents × ~5 API calls = 25 req/min = 1500 req/hr — under 5000/hr limit with headroom).
- **Burst-mode escape hatch**: `scripts/agent-state.sh set <role> poll_interval_sec 15` allows 15s for critical handoffs, then revert.

### Alternatives considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **A. 60s polling on GitHub (this ADR)** | Self-contained, persistent, no public infra, dedup-safe | 60s wake latency, GitHub rate limit coupling | ✅ **Chosen** |
| B. Webhook-driven (push from GitHub) | Lower latency, no polling overhead | Requires public endpoint, TLS, webhook secret rotation, lost-event recovery complexity | ❌ Rejected (operational cost) |
| C. Telegram-native polling | Single channel, simpler | Telegram is human-only; agents cannot read it | ❌ Rejected (does not solve the problem) |
| D. Custom event bus (Redis/NATS/etc.) | High throughput, real-time | New infra, new failure modes, project-portability hit | ❌ Rejected (over-engineering for 5-agent scale) |
| E. Manual human-in-loop pings | No infra | Defeats the purpose of autonomous agents | ❌ Rejected (pre-ADR-0002 status quo) |

## The loop

```bash
bash scripts/agent-watch.sh <your-role>
```

Output (JSON):

```json
{
  "role": "<your-role>",
  "polled_at_utc": "...",
  "new_events": [
    { "id": "...", "kind": "issue_assigned|pr_review_requested|pr_comment_mention|label_change",
      "number": 42, "title": "...", "url": "...", "updated_at": "...",
      "context": { ... } }
  ],
  "next_poll_sec": 60
}
```

If `new_events` is empty, sleep 60s and poll again. If non-empty, take action on each event, then poll again.

## Trigger → action mapping (kind-by-kind)

| `kind` | Meaning | Agent's action |
|---|---|---|
| `issue_assigned` | New work assigned to you (`agent:<your-role>` label on an issue) | Read the story, open a branch, start work |
| `pr_review_requested` | A PR is awaiting your review (`cc:<your-role>` label) | Read the PR, do design-alignment or test review, comment + auto-ping |
| `pr_comment_mention` | A peer `@`-mentioned you in a comment | Read the comment, take the requested action or reply |
| `label_change` | (Orchestrator-only) A board label changed | Sprint plan / WIP limit check |

## State management

- **State file**: `/var/log/dev-studio/AtilCalculator/agent-state/<role>.json`
- **`processed_event_ids`**: every event ID is automatically added to the dedup list — never process the same event twice.
- **`last_seen_utc`**: updated after every poll, used as the cursor for the next query.
- **Manual replay**: `scripts/agent-state.sh set <role> last_seen_utc <ISO-timestamp>` to rewind and re-process a window.

## Polling cadence

- **Default**: 60 seconds (`AGENT_POLL_INTERVAL_SEC=60`).
- **Burst mode**: paused while the agent is actively working (PR review, test run, etc.); resumes when the work unit completes.
- **Accelerate**: `scripts/agent-state.sh set <role> poll_interval_sec 15` for critical handoffs, then revert.
- **Hard floor**: never below 30s (GitHub API rate limit).

## Coupling with Auto-Ping Hard-Rule

Auto-Ping (`notify.sh`) and Autonomy Loop (`agent-watch.sh`) work **together**:

1. You complete work + send an Auto-Ping → Telegram (human sees) **AND** GitHub (peer sees via label/comment/assignee).
2. Peer agent's `agent-watch.sh` loop picks up the GitHub artefact → wake-up signal.
3. Peer takes action → sends their own Auto-Ping → cycle continues.

**Rule**: every `notify.sh` call must *also* trigger a GitHub artefact (label add, comment write, assignee/cc change). Writing only to Telegram = peer does not wake.

## What you do NOT do

- ❌ Wait for the human to say "start work on X" — at assignment, **start on your own**.
- ❌ Re-process the same event — `processed_event_ids` already dedups; do not re-call the tool.
- ❌ Drop polling below 30s — GitHub API rate limit.
- ❌ Delete or reset the state file — `last_seen` is forward-wound; resetting loses history.
- ❌ Ask the human "should I poll?" — this ADR already decided; you just apply it.

## Consequences

### Positive

1. **Multi-agent coordination without human in the loop**. The owner is gate-keeper, not courier.
2. **Recoverable from agent restarts**. `processed_event_ids` dedup + `last_seen_utc` cursor means tmux restarts are transparent.
3. **Self-documenting queue**. The agent's state file is a machine-readable record of what they saw and when.
4. **Doctrine-agnostic**. The loop works for any role (architect, developer, tester, PM, orchestrator) without per-role specialization.
5. **Project-portable**. `scripts/agent-watch.sh` is project-agnostic (template-port candidate per Issue #48 PR-T1).

### Negative

1. **60s wake latency** for human-coordinated events. Acceptable for the current 5-agent scale; would need rework for >20 agents or sub-10s SLAs.
2. **GitHub API rate-limit coupling**. If the rate limit is hit, the entire coordination substrate degrades. Mitigation: per-role query scoping keeps usage well under the 5000/hr limit.
3. **HWM-advancing re-fire noise (TD-013)**. An agent's own actions (comments, label flips) advance the underlying issue/PR `updated_at`, which the watcher can treat as a new event. Mitigation: `processed_event_ids` dedups stable event IDs; re-fires only fire on `updated_at` advance, which is now characterized as noise-only (not a real signal). See Issue #125 for the drift-tracker.
4. **Polling-vs-push asymmetry**. Some peers may prefer push (immediate wake on event). The 60s cadence is a deliberate trade-off (see Rationale).
5. **Single point of failure per agent** — if `agent-watch.sh` is down for one agent, that agent's queue stalls. Mitigation: systemd timer health check every 30 min; orchestrator's board-hygiene sweep catches stale-queue issues (D1, D2, D3, D4 detections in `scripts/proactive-board-scan.sh`).

### Follow-up tickets

- **TD-011**: PM `agent-watch.sh` lacks `issue_assigned` events (PM-only gap). Sprint 2+ carry.
- **TD-013**: HWM-advancing re-fire pattern (architect family). Documented; not actively fixed.
- **Issue #125**: Auto-revert drift tracker (reframed as owner merge-gate bundle pattern). Sprint 4 P0 work in progress.
- **Issue #203**: This ADR's filing issue (resolved by this ADR's acceptance).
- **PR-T1 / Issue #48**: Template-port of `scripts/agent-watch.sh` to `dev-studio-template`. In flight (PR #199).

## Open questions

- [ ] **Q1 (orchestrator)**: Should the loop support sub-15s cadence for time-critical P0 incidents? Current floor is 30s.
- [ ] **Q2 (orchestrator)**: When the GitHub API rate limit is approached, should the loop degrade to event-source-webhook fallback? Currently no fallback.
- [ ] **Q3 (owner)**: Should the state file be backed up to a separate location (e.g., `/var/log/dev-studio/AtilCalculator/agent-state/.backup/`) to recover from corruption? Currently single-file, no backup.
- [ ] **Q4 (architect)**: Should this ADR be amended to formalize the "owner merge-gate bundle pattern" (`+cc:architect +cc:human +verdict-by +status:ready`) as a recognized doctrine? See Issue #125 drift-tracker + ADR-0031 §Recovery procedure.

## References

- **Human-mirror version**: `.claude/CLAUDE.md` §Autonomy Loop (owner-only file; canonical content mirrored here for agent readability).
- **Sister ADRs**: ADR-0010, ADR-0012, ADR-0013, ADR-0015, ADR-0020, ADR-0021, ADR-0024, ADR-0025, ADR-0026.
- **Implementation**: `scripts/agent-watch.sh` (~1300 lines, project-agnostic; refactored in PR #199 to extract `scripts/proactive-board-scan.sh`).
- **Test coverage**: `scripts/tests/d015-dev-idle-prevention.sh` (9/9 PASS); `scripts/tests/d020-proactive-board-detections.sh` (planned, follow-up to PR #199).
- **Doctrine amendment history**: ADR-0024 (stale-verdict watchdog), ADR-0025 (bound standby), ADR-0026 (queue-empty wake) — each amends the autonomy loop in response to observed gaps.

---

## Amendment

Folded amendments per **ADR-0057 §amendment-via-parent** (Path A v26 source-of-truth = calc-side standalone amendment file; tmpl-side = section in parent ADR).

### Amendment 1: stale-verdict filter scope (folded per ADR-0057 §amendment-via-parent)

- **Status:** Proposed (amendment — folded into this ADR per ADR-0057 §amendment-via-parent; canonical home = this section)
- **Date:** 2026-06-30
- **Origin:** (see calc source)
- **Source (calc canonical):** [ADR-0002-amendment-1-stale-verdict-filter-scope](https://github.com/atilcan65/AtilCalculator/blob/main/docs/decisions/ADR-0002-amendment-1-stale-verdict-filter-scope.md) — folded into this section on tmpl per ADR-0057 §amendment-via-parent pattern. NOTE: tmpl standalone `ADR-0002-amendment-1-stale-verdict-filter-scope.md` file does NOT exist (will not be created); amendment lineage trace via slug reference in this section.
- **Sister-patterns:** ADR-0057 (§amendment-via-parent — fold pattern codification), ADR-0024 §Watchdog logic, ADR-0038 §WIP cap, ADR-0049 §d-test framework, ADR-0055 §1 Cadence Rule 1 atomic

#### Amendment doctrine (extracted from calc canonical §Decision)

**The `stale_verdict` filter MUST scope to verdict-authority lanes ONLY:**

```
stale_verdict fires for ROLE iff:
  (agent:ROLE AND verdict-by:<ts> past deadline)
  OR
  (cc:human AND verdict-by:<ts> past deadline)
```

Where ROLE = the agent's role (e.g., `architect`, `developer`, `tester`).

**Verdict authority doctrine** (codified per ADR-0024 + ADR-0031):
- `agent:<role>` lanes carry verdict authority (PR owner is the verdict source)
- `cc:human` lane carries owner-merge verdict authority (ADR-0031 owner merge gate)
- `cc:<peer>` lanes carry NO verdict authority — they are informational only (ADR-0015 queue-passing)

**Concrete filter change** (in `scripts/agent-watch.sh` line 1090):

```bash
# BEFORE (current — INCORRECT):
gh pr list --label "cc:${ROLE}" --state open --limit 50 ...

# AFTER (corrected — verdict-authority lanes only):
# Filter logic in jq: agent:<role> OR cc:human + verdict-by:* past deadline.
# gh pr list can stay broad; jq applies the verdict-authority gate.
gh pr list \
  --label "agent:${ROLE}" \
  --label "cc:human" \
  --state open \
  --limit 50 \
  --json number,title,url,updatedAt,headRefOid,labels,files,statusCheckRollup
```

(Note: `gh pr list --labe

*(Doctrine elided for brevity — see calc canonical source for full text)*

