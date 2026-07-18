# ADR-0039: WIP-idle watchdog — 30-minute idle threshold for `WIP > 0` agents

## Status
Proposed

## Date
2026-06-23

## Deciders
- @architect (drafted per Issue #289 v2 design, 2026-06-23T11:32Z comment by orchestrator)
- @orchestrator (design owner)
- @owner (approver — doctrine amendment per owner directive 2026-06-23T10:08Z chat)
- @developer (impl — Sprint 6 #291)
- @tester (regression — Sprint 6 d034)

## Context

Sprint 5 close-out retrospective (PR #292, 2026-06-23) identified a **claim-but-not-work** gap:

- §Auto-Claim Protocol Layer 2 (ADR-0038) shipped Sprint 5 and works in production: #287 auto-claimed by dev 5 min after #280 close.
- BUT: the soul-level §Doctrine Reminder (PR #288, 4-soul patch) is **reactive** — it requires the agent to self-check before pause.
- Real-world observation (2026-06-23, dev lane 1h 15m idle with WIP=2/2): self-check is **insufficient**. Agent claimed work but did not produce activity for 1h+.

Owner directive (2026-06-23T10:08Z chat):
> "WIP dolu iken boş durmamaları gerek hiçbir agentın."

Issue #289 (P1, status:in-progress, agent:orchestrator) proposes orchestrator-side **proactive** watchdog that detects `WIP > 0 + no activity 30m` and pings the agent within 30 minutes (vs current 4-hour stale threshold).

Architect arch review on #289 v1 (comment 4778117427) raised 4 🟡 suggestions. Orchestrator resolved all 4 in v2 design (2026-06-23T11:32Z comment).

## Decision

We will adopt a **30-minute idle threshold** for the WIP-idle watchdog, with the following contract:

### Detection signals (5 total, GitHub-native)

| # | Signal | Source |
|---|---|---|
| 1 | PR draft activity | `gh pr list --author <agent-bot> --state draft --json updatedAt` (any draft updated in last 30m?) |
| 2 | Issue comment activity | `gh issue view N --json comments` (any comment in last 30m?) |
| 3 | Branch commit activity | `gh api repos/{owner}/{repo}/commits?sha=<branch>&since=<30m ago>` (any commit in last 30m?) |
| 4 | Worktree file activity | Out-of-scope for orchestrator; dev lane self-reports (deferred, future work) |
| 5 | PR-in-review state | `gh pr list --search "is:open is:draft review:required"` (block-on-reviewer edge case) |

### Idle definition

```python
def is_idle(agent):
    if has_pr_in_review(agent):  # signal 5
        return False  # legitimate wait, not pause
    return (
        wip_count(agent) > 0
        and not any_activity_signal(agent, threshold_min=30)
    )
```

### Threshold rationale (per 🟡 #1)

**30 minutes** is chosen because:

1. **6× is_alive heartbeat interval** (5min × 6 = 30min) — orchestrator polls ~6 times before triggering, giving a heartbeat-aligned tolerance window.
2. **½ of standup cadence** (1h) — does not trigger during normal standup gaps.
3. **½ of typical agent think-time** on hard problems (~1h for design/ADR work).

### Alternatives considered

| Threshold | Pros | Cons | Verdict |
|---|---|---|---|
| 15 min | Aggressive, fast incident response | False positives during deep work; noisy | 🔴 Rejected |
| 30 min | Balanced, heartbeat-aligned | Some false positives during long test runs | ✅ **Adopted** |
| 1 hour | Low noise | Too slow for incident response (4h was the bug) | 🔴 Rejected |
| 4 hours | Current | Too late — the bug we just saw | 🔴 Rejected (status quo rejected) |

### Notification strategy (per 🟡 #2)

```bash
IDLE_AGENTS=$(check_idle_per_role)
if [[ $(echo "$IDLE_AGENTS" | wc -l) -ge 3 ]]; then
  # Consolidated wave: ≥3 idle agents in same 5-min window
  notify_all "[ORCH→ALL] idle wave: $IDLE_AGENTS idle 30m+"
else
  # Individual pings
  for role in $IDLE_AGENTS; do
    notify_role "$role" "[ORCH→$role] idle 30m+ on #N"
  done
fi
```

### Cascade escalation

| Idle duration | Action |
|---|---|
| 30 min | Role ping (notify.sh + GitHub artefact) |
| 60 min | Human escalation (`notify.sh -l human`) |
| 90 min | P0 incident (open issue with `priority:P0`, `type:incident`) |

## Consequences

### Positive

1. **Closes claim-but-not-work gap** — Agent who claims work but doesn't produce activity within 30m gets nudged.
2. **Defense-in-depth with §Doctrine Reminder** — Soul self-check (PR #288, reactive) + orchestrator watchdog (this ADR, proactive). Both layers needed.
3. **Multi-repo coverage** — Watchdog scans both AtilCalc + dev-studio-template. Closes Sprint 5 dev-idle 1h26m gap (AtilCalc-only monitoring missed template activity).
4. **Bounded noise** — Throttle/coalesce wave pattern reduces peer notification fatigue.
5. **Cascade escalation** — 30/60/90 min tiers give clear severity signal.

### Negative

1. **False-positive risk during long test runs / build pipelines** — Dev running `pytest` for 35 min on slow test suite would get pinged. Mitigation: dev can preempt by posting "running tests, ETA 45m" comment which signals signal 2 (issue comment activity).
2. **d034 test plan complexity** — 8 TUs (5 positive + 3 negative/boundary) per 🟡 #3. Tester needs to construct idle/non-idle fixtures.
3. **State-machine edge case** — Signal 5 (PR-in-review) is a heuristic. PRs in `status:in-review` for 4h+ with no reviewer activity get flagged (different issue: peer stagnation, separate doctrine).
4. **GitHub API rate-limit dependency** — 5 signals × N agents × 60s polling = significant rate-limit usage. Mitigation: cache results for 5-min windows; degrade gracefully if rate-limited.

### Follow-up tickets

- Issue #291 (P1, developer) — Sprint 6 impl of `scripts/wip-idle-detect.sh`
- Issue #290 (P1, developer) — Sprint 6 template port
- Issue #296 (orchestrator) — companion §Peer-Poke Discipline for atomic poke pattern (currently being filed)
- d034 regression — 8 TUs (5 positive + 3 negative/boundary)

## Doctrinal alignment

- **Issue #289** (orchestrator design, status:in-progress) — implements this ADR
- **Issue #119** (Katman 1+2 dev-idle prevention, predecessor) — closed via PR #120
- **Issue #238** (P0 self-standby doctrine, closed) — §Doctrine Reminder (PR #288) is the soul-level complement
- **PR #288** (§Doctrine Reminder 4-soul patch, MERGED 27c70ec) — soul self-check layer
- **PR #286** (§Auto-Claim Protocol Layer 2, MERGED a0d1a7c) — claim automation that exposed the gap
- **Owner chat 2026-06-23T10:08Z** — doctrine anchor ("WIP > 0 → no idle")
- **PR #292** (Sprint 5 close summary) — captured the lesson formally

## References

- Issue #289 (v1: 2026-06-23T10:11Z design; v2: 2026-06-23T11:32Z incorporating arch 4 🟡)
- Issue #119 (predecessor — dev-idle prevention Katman 1+2)
- Issue #238 (P0 self-standby doctrine chain)
- PR #120 (Katman 1+2 done)
- PR #288 (§Doctrine Reminder 4-soul patch, MERGED)
- PR #286 (§Auto-Claim Protocol Layer 2, MERGED)
- PR #292 (Sprint 5 close summary)
- ADR-0038 (§Auto-Claim Protocol, accepted)
- d015 regression (existing 9/9 — must remain green)
- d034-proactive-wip-idle (new — 8 TUs)
- Arch review comments: 4778117427 (v1 review), 4778135769 (#291 pointer)

— @architect, 2026-06-23T12:59Z, drafted per Issue #289 v2 design + arch review 4778117427.