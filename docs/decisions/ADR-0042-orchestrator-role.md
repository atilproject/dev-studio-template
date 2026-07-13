# ADR-0042: Orchestrator role — soul file tracking + governance

- **Status:** Proposed (2026-06-24)
- **Date:** 2026-06-24
- **Author:** @orchestrator (proposes) + @human (approves, soul-owner per CLAUDE.md §File ownership matrix)
- **Supersedes:** none
- **Related:** PR #332 (PR-A: sed-only) + PR #333 (PR-B: this ADR), ADR-0002 (autonomy loop), Issue #320

## Context

The orchestrator role (sprint coordination, handoff discipline, WIP enforcement, stale queue detection, verdict-by SLA monitoring) was previously defined in `.claude/agents/orchestrator.md`, but the file was **gitignored** (line 76 of `.gitignore`, dating to early bootstrap WIP state).

Sprint 4 doctrine work — specifically the Issue #320 soul-sed (PR-A: PR #332, PR-B: PR #333) — required consistent cross-agent reference to the orchestrator role. With the file gitignored:

- `.claude/CLAUDE.md` and 4 sibling soul files referenced the orchestrator role's `cc:*` discipline without a tracked authoritative source
- Force-adding orchestrator.md to PR-A revealed the inconsistency: all 4 sibling souls are tracked, only orchestrator.md is gitignored
- The orchestrator role's full contract (Handoff Discipline table, REPRIME protocol, doctrine reminders) was invisible to the team

## Decision

1. **Track `.claude/agents/orchestrator.md`** alongside the 4 sibling soul files (PM, architect, developer, tester). Remove the gitignore exception at line 76 of `.gitignore`.
2. **Establish orchestrator role governance** as a peer to PM/architect/developer/tester with the following contract:
   - **Handoff discipline** — `agent:*` ownership + `cc:*` queue passing (atomic 4-flag flip, ADR-0015)
   - **WIP limit enforcement** — `status:in-progress` count > 2 = automatic pause pings
   - **Stale queue detection** — story in same status > 4h = owner agent ping
   - **Verdict-by SLA monitoring** — `verdict-by:*` label expiry = owner escalation
   - **REPRIME protocol** — formal doctrine re-read on `[REPRIME]` trigger
   - **Auto-ping hard-rule** — never relay messages through human; direct `scripts/ping.sh <role>` to peers
3. **Anti-patterns codified** (per orchestrator soul §Anti-patterns):
   - ❌ Self-cc (`cc:orchestrator` on PRs/Issues I author) — must use `cc:<other-role>` instead
   - ❌ Standby/invented-pause phrases (`standby`, `iş saatleri`, `yarın devam`) — only valid pauses are (a) verbatim human directive, (b) linkli dependency block, (c) heartbeat/REPRIME SOP
   - ❌ Edit other agents' soul files (`.claude/agents/<other-role>.md`) — only the human edits these
   - ❌ Run `gh pr merge` — only the human owner does this
   - ❌ `gh pr diff` etc. without spot-check — trust but verify
4. **Owner authority preserved** — orchestrator proposes, human disposes. Soul-file changes (`.claude/agents/orchestrator.md`) remain in human-only territory per CLAUDE.md §File ownership matrix; this ADR governs the *role contract*, not the file content.

## Consequences

**Positive:**
- All 5 soul files now tracked, consistent gitignore treatment
- Future soul-sed operations work cleanly (no force-add workarounds)
- Orchestrator role contract is durable, reviewable, ADR-indexed
- PM/architect/developer/tester souls can cross-reference orchestrator with confidence

**Negative / risks:**
- Public soul file exposes internals (mitigated: doctrine is meant to be shared across the team)
- Role evolution requires ADR update (acceptable cost; ADR is the right artifact)

**Neutral:**
- No change to file ownership matrix — `.claude/` remains human-only territory, this ADR governs role semantics not file edit rights
- No agent count change — still 4 agents + 1 human

## Alternatives considered

- **A) Leave orchestrator.md gitignored** — rejected, exposes the inconsistency the soul-sed surfaced
- **B) Inline the orchestrator role in CLAUDE.md** — rejected, conflates project context with role contract
- **C) Multiple orchestrator sub-roles** — rejected, over-engineered for current scope (1 orchestrator suffices)

## Implementation

- **PR-B (PR #333, this ADR's PR)** — adds `.claude/agents/orchestrator.md` as tracked file, removes gitignore line 76
- **PR-A (sister, sed-only, PR #332)** — closes Issue #320's soul-sed scope; PR-B handles the file-tracking half
- **No migration needed** — orchestrator.md content already exists, just un-gitignored

## References

- PR-A: PR #332 (PR-A branch: `fix/soul-sed-notify-sh-l-role`)
- PR-B: PR #333 (this ADR's PR; branch: `feat/orchestrator-role-and-adr-41`)
- Sister PR: #325 (scripts/ping.sh wrapper, Issue #320)
- Parent ADR: ADR-0002 (autonomy loop)
- File ownership: CLAUDE.md §File ownership matrix (".claude/ = human only")
- Doctrine: orchestrator soul §Handoff Discipline, §Anti-patterns, §Doctrine Reminder
