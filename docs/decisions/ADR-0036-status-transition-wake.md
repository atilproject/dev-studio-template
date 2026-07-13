# ADR-0036: Status-Flip Wake on Label Change (Option A: watcher extend + Option C: orchestrator helper) — RCA-19 fix

- **Status**: Accepted
- **Date**: 2026-06-22 (original); 2026-06-22T06:30Z (this revision)
- **Accepted**: 2026-06-22T08:57:22Z (per PR #234 merge by @atilcan65 owner, commit ec384d1; original Options A+C design approved at 2026-06-22T06:15Z per Issue #231 owner comment)
- **Deciders**: @architect (revised design), @atilcan65 (owner-approved Options A+C at 2026-06-22T06:15Z, owner-merged PR #234 at 2026-06-22T08:57:22Z)
- **Related**: Issue #231 (RCA-19, P0 INCIDENT), Issue #94 (RCA-1 sister, PR #184), RCA-18 (Issue #216, ADR-0032), ADR-0033 (auto-ping dual-channel), Issue #222 (dev idle 8h 42min), `scripts/agent-watch.sh` (L1060-1086 `query_board_changes`, L1088-1135 `wake_pane_for_role`)

## CHANGELOG

- **2026-06-22T06:30Z — REVISION (this version)**: Owner override per ADR-0031 §Owner-Override PR Merge Doctrine. **Original design (Option 2 + 3) replaced** with **Option A + C** (owner-approved at 2026-06-22T06:15Z). Rationale (owner): smaller blast radius, reuses existing `wake_pane_for_role`, reuses content-stable event ID semantics, encapsulates orchestrator's flip workflow in a helper tool. Scope reduced from 2.5 SP → 2.0 SP (architect 0.5 unchanged, dev 1.5 → 1.0, tester 0.5 unchanged).
- **2026-06-22T06:18Z — ORIGINAL (superseded)**: Option 2 (new `status_transition` event kind) + Option 3 (backstop poll). Superseded by this revision per ADR-0031 owner override.

## Context

Third autonomy-loop incident in 4 days. The `scripts/agent-watch.sh` event taxonomy is **incomplete** — it does not emit a wake event for the assigned `agent:<role>` when a `status:*` label flips on an issue where the agent is already the owner.

**Incident timeline (Issue #222, dev idle 8h 42min)**:

| Time | Event | Effect |
|---|---|---|
| 2026-06-21T20:41:48Z | Issue #222 opened, `agent:developer` added | `issue_assigned` event → dev woken |
| 2026-06-21T21:26:20Z | Orchestrator flipped `status:ready → status:in-progress` via raw `gh issue edit` | **NO wake event** for dev (`query_board_changes` is orchestrator-only) |
| 2026-06-21T22:00:55Z | Dev committed PR #230 (Issue #201) instead | Different work |
| 2026-06-22T06:08Z | Owner asked "why is dev idle on #222?" | RCA filed → Issue #231 |
| 2026-06-22T06:10:14Z | Orchestrator added `@developer` comment mention | `pr_comment_mention` event → dev woken (workaround) |

**Root cause** (architect-confirmed by reading `scripts/agent-watch.sh`):

1. **Receive-side gap**: `query_board_changes()` (L1060-1086) hard-guards on `ROLE == orchestrator` (line 1061: returns `[]` for all other roles). Non-orchestrator agents have no visibility into label changes on their assigned issues.
2. **Emit-side gap**: Orchestrator's status-flip workflow uses raw `gh issue edit` with no helper, no wake signal, no audit trail. The flip happens "silently" from the assigned agent's perspective.

**Family of related incidents**:
- **RCA-1** (Issue #94): self-cc filter — fixed via PR #184
- **RCA-18** (Issue #216, ADR-0032): stale-cc on closed/merged — fixed via PR #224 + #225
- **RCA-19** (Issue #231, this ADR): status flip wake — **3rd in 4 days**

## Decision (revised — owner-approved A+C)

Two complementary fixes, one for each side of the wake signal:

### Part A — Extend watcher label_change handler (receive side)

Modify `scripts/agent-watch.sh` `query_board_changes()` (L1060-1086) to be **role-aware** instead of orchestrator-only:

- For `ROLE=orchestrator`: return all label changes on any issue (current behavior, **unchanged** — back-compat)
- For other roles: return label changes ONLY on issues with `agent:<role>` label present
- Event ID is content-stable and **role-scoped** to prevent dedup collisions: `id = "board-${role}-${number}-${sorted_label_set}"`

`wake_pane_for_role()` (L1088-1135) is **unchanged** — it already takes `role + events_json` and routes to the role's tmux pane. The new role-aware query feeds into the existing wake function with no further changes.

**Blast radius**: ~15 lines changed in `query_board_changes()`. New branch on `ROLE` variable. No new event kinds. No new dedup logic. No new state file fields. Backward compatible — orchestrator's behavior is identical to today.

### Part C — New helper script `scripts/orchestrator-status-flip.sh` (emit side)

Encapsulates the orchestrator's status-flip workflow in a single idempotent tool:

```bash
scripts/orchestrator-status-flip.sh <issue_number> <new_status> [next_role]
# Example: orchestrator-status-flip.sh 222 in-progress developer
```

**POC spec** (dev writes final, ~40 lines):

```bash
#!/usr/bin/env bash
# orchestrator-status-flip.sh — atomic status transition + wake signal
# See ADR-0036 Part C for full design.
set -euo pipefail
ISSUE="${1:?usage: orchestrator-status-flip.sh <issue_number> <new_status> [next_role]}"
NEW_STATUS="${2:?missing <new_status>}"
NEXT_ROLE="${3:-}"
[[ "$ROLE" == "orchestrator" ]] || { echo "ERROR: orchestrator-only"; exit 3; }
case "$NEW_STATUS" in backlog|ready|in-progress|in-review|blocked|done) ;; *) echo "ERROR: invalid status"; exit 2 ;; esac
CURRENT="$(gh issue view "$ISSUE" --json labels --jq '[.labels[].name] | map(select(startswith("status:"))) | first // ""')"
[ "$CURRENT" = "status:$NEW_STATUS" ] && { echo "noop (already $NEW_STATUS)"; exit 0; }
gh issue edit "$ISSUE" --remove-label "status:*" --add-label "status:$NEW_STATUS" >/dev/null
[ -n "$NEXT_ROLE" ] && bash scripts/notify.sh -w -r "$NEXT_ROLE" "[ORCH→${NEXT_ROLE^^}] status flip on #${ISSUE} → $NEW_STATUS" 2>/dev/null \
                    || bash scripts/notify.sh -l "$NEXT_ROLE" "[ORCH→${NEXT_ROLE^^}] status flip on #${ISSUE} → $NEW_STATUS" 2>/dev/null
echo "flipped #${ISSUE}: ${CURRENT:-none} → status:${NEW_STATUS} (wake: ${NEXT_ROLE:-none})"
```

**Properties**:
1. **Role guard**: requires `ROLE=orchestrator` (exit 3 if not). Prevents accidental misuse.
2. **Input validation**: `new_status` must be in {backlog, ready, in-progress, in-review, blocked, done} (exit 2 on invalid).
3. **Idempotent**: if issue already has the target status, exit 0 (no-op, no label flip, no wake).
4. **Atomic flip**: `gh issue edit ${issue} --remove-label "status:*" --add-label "status:${new_status}"` — single command, atomic from the agent's perspective.
5. **Wake next role**: if `next_role` provided, calls `notify.sh -w -r ${next_role}` (dual-channel per ADR-0033, when impl'd) with fallback to `-l ${next_role}` (legacy single-channel).
6. **Audit log**: append to `/var/log/dev-studio/${PROJECT}/status-flips.log` (timestamp, issue, old_status, new_status, next_role, exit code).
7. **Closed-state guard**: if issue is `state: closed`, exit 4 (no-op, terminal).

### Why both A and C (not either alone)

- **A alone** fixes receive-side: any role's watcher now sees label changes on its assigned issues. But orchestrator's flip via raw `gh issue edit` is still silent from the agent's perspective until their next 60s poll.
- **C alone** fixes emit-side: orchestrator's helper guarantees wake fires immediately on flip. But other roles' raw `gh issue edit` (e.g., developer manually flipping their own issue status) still has no wake.
- **A + C together**: C makes orchestrator's workflow emit a guaranteed wake; A ensures the wake reaches the right role's watcher. Defense in depth — both paths work independently.

## d025 spec (regression test)

**Numbering conflict noted**: d025 is currently assigned to Issue #228 (cmd_set JSON contract, per ADR-0034 merged in PR #229). Owner directive uses "d025" for RCA-19. Proposing rename: `#228` regression → `d025-cmd-set`, RCA-19 regression → `d025-status-transition` OR free number `d027`. Will confirm with owner in PR review.

**Test contract for `scripts/orchestrator-status-flip.sh` + extended `query_board_changes`**:

| # | Test | Coverage |
|---|---|---|
| 1 | `orchestrator-status-flip.sh 222 in-progress developer` → label flipped + `notify.sh -w` called with developer role | happy path |
| 2 | Same with `-w` flag not yet impl'd (ADR-0033 impl pending) → falls back to `notify.sh -l` (legacy) | fallback |
| 3 | Idempotent: `orchestrator-status-flip.sh 222 in-progress` (already in-progress) → exit 0, no flip, no wake | idempotency |
| 4 | Invalid status: `orchestrator-status-flip.sh 222 foo` → exit 2 with usage error | input validation |
| 5 | Non-orchestrator caller: `ROLE=developer` → exit 3, no flip | role guard |
| 6 | `query_board_changes` for `developer` role returns label changes only on issues with `agent:developer` | role-aware query (Part A) |
| 7 | `query_board_changes` for `orchestrator` role returns all label changes (back-compat) | orchestrator lens preserved |
| 8 | Dedup: same label set on same issue does NOT emit duplicate event (content-stable ID) | dedup |
| 9 | Status flip on closed issue → exit 4, no-op, no wake | closed-state guard |
| 10 | Missing args: `orchestrator-status-flip.sh` (no args) → exit 2 with usage | usage |

**Total: 10 TCs**.

## Rationale (revised)

- **Why Option A (extend existing handler) vs Option 2 (new event type)**: Smaller blast radius. Reuses existing `wake_pane_for_role` function (L1088-1135). Reuses content-stable event ID semantics (no new dedup logic). Backward compatible — orchestrator's behavior is unchanged. Per ADR-0031 owner override: smaller is better when reversibility is high.
- **Why Option C (helper script) vs Option 3 (backstop poll)**: Backstop is passive (catches missed events after the fact). Helper is active (guarantees wake fires on emit). Active > passive for the orchestrator's own workflow. Also encapsulates the pattern in a reusable tool — orchestrator's other workflows (cc flip, priority escalation) can adopt the same helper pattern.
- **Why both A and C**: A handles receive-side (any role sees label changes on its queue). C handles emit-side (orchestrator's helper guarantees wake). Together = both directions covered.
- **Why d025 numbering conflict noted but not blocking**: The test contract is what matters; the number is a label. Owner can correct in PR review.

## Consequences (revised)

**Positive**:
- Smaller change than original (Option 2+3) — ~50 lines total (vs ~80) in scripts/agent-watch.sh + 1 new ~40-line helper
- Backward compatible — orchestrator's behavior unchanged
- Reuses existing event ID semantics (content-stable, role-scoped)
- Active emit-side fix via helper script (orchestrator's status flips are now guaranteed to wake the next role)
- Reusable pattern — other label-flip workflows (cc:*, priority:*, type:*) can adopt the same helper
- Scope reduced 2.5 SP → 2.0 SP (owner-approved)

**Negative / tradeoffs**:
- Part A still relies on the 60s poll cycle for delivery (no real-time wake without dual-channel impl per Issue #232)
- Part C is opt-in — orchestrator must use the helper, not raw `gh issue edit`. Discipline required until enforced via CI gate (out of scope for this PR)
- d025 numbering conflict (see spec section) — owner decision needed

**Follow-up tickets**:
- **Dev**: implement Part A (`query_board_changes` role-aware, ~15 lines)
- **Dev**: implement Part C (`scripts/orchestrator-status-flip.sh`, ~40 lines)
- **Dev**: write d025 spec test contract (10 TCs)
- **Tester**: sign off on d025
- **Orchestrator**: migrate status-flip calls from raw `gh issue edit` to `orchestrator-status-flip.sh` (Sprint 5 cleanup)
- **Orchestrator**: monitor for RCA-20 (`cc:<role>` removal) + RCA-21 (`priority:*` escalation) — same A+C pattern applies, separate ADRs
- **Human**: approve the watcher patch + helper script (no workflow file change, no CI gate)
- **Architect (post-merge)**: update `.claude/agents/orchestrator.md` §Handoff Discipline to mandate `orchestrator-status-flip.sh` over raw `gh issue edit` for status transitions

## Sprint 4 commitment (revised)

| Role | SP | Scope |
|---|---|---|
| **Architect** (me) | 0.5 | This ADR revision + d025 spec — DONE on PR #234 amend |
| **Developer** | 1.0 | Part A impl + Part C impl + d025 regression (10 TCs) |
| **Tester** | 0.5 | d025 sign-off |
| **Total** | **2.0** | (down from 2.5 SP — owner-approved smaller scope) |

Fits Sprint 4 EOD 2026-06-22T24:00Z (~17h 30m from this revision).

## References

- Issue #231 (RCA-19, this fix)
- Issue #94 (RCA-1 self-cc filter, PR #184)
- Issue #216 (RCA-18 hypothesis, refuted by ADR-0032)
- ADR-0031 (Owner-Override PR Merge Doctrine — basis for this revision)
- ADR-0032 (RCA-18 dedup buffer TTL — sister fix)
- ADR-0033 (auto-ping dual-channel — referenced for `-w` flag in Part C)
- ADR-0034 (cmd_set JSON contract, Issue #228 — owns current d025 number)
- Issue #222 (incident timeline — dev idle 8h 42min)
- Issue #232 (design drift — dual-channel impl gap, blocks Part C dual-channel mode)
- `scripts/agent-watch.sh` L1060-1086 (`query_board_changes`), L1088-1135 (`wake_pane_for_role`)
