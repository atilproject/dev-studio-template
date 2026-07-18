# ADR-0072: S32-026 Soul-Sync State Correction — tmpl AHEAD of calc on orchestrator+architect soul files

- **Status**: Accepted (state-correction doc, no future work)
- **Date**: 2026-07-18
- **Deciders**: @architect
- **Supersedes**: none
- **Related**: ADR-0055 §1 (Cadence Rule 1 atomic), ADR-0057 (Closes anchor), RETRO-024 (work-done-elsewhere), RETRO-027 (Retroactive-Close Precondition), Issue #972 (Path-Verify Doctrine), Issue #155 (S32-026)
- **Closes**: Issue #155 (state-correction close, NOT port-work close)

## Context

S32-026 (Issue #155) was opened with the title "Sync orchestrator.md.tmpl + architect.md.tmpl with calc's +5500B / +1440B amendments". The premise: calc's `.claude/agents/orchestrator.md` (12607B) and `.claude/agents/architect.md` (4333B) were AHEAD of tmpl, and tmpl needed to receive the delta.

### Cycle ~#3443 — Issue #155 REOPENED by ORCH

The architect reflexively closed Issue #155 via RETRO-024 work-done-elsewhere pattern (claiming PR #140 S32-004+5 already did the sync work). ORCH diagnosed:

> "`gh pr view 155` → 'Could not resolve to a PullRequest' + checked `gh api .../issues/155/timeline` → 'only event is closed, NO cross-referenced / referenced'. Diagnosis: zero PR-persistence in `atilproject/dev-studio-template origin/main` → retroactive close WITHOUT anchor-PR is INVALID per RETRO-027 §Retroactive-Close Precondition."

ORCH reopened Issue #155 + restored 4-cat labels (`status:ready + agent:architect + cc:architect`) + dispatched Cadence Rule 2 §Operational chain step 2/7 to architect: "Architect opens ADR-0061 docs PR (or next unused slug), `Refs` template ADR + sister template PRs".

### Cycle ~#3475 — Ground-truth re-query (this ADR)

Per Issue #972 Path-Verify Doctrine + RETRO-005 #26 (verdict-chain trust-but-verify), architect re-queried the canonical tmpl path BEFORE acting on the dispatch. Result: **the original Issue #155 premise is OBSOLETE**.

| File | Calc bytes | Tmpl bytes | Delta | Direction |
|---|---|---|---|---|
| `.claude/agents/orchestrator.md` | 12607 | 12969 | **+362B** | **tmpl AHEAD** |
| `.claude/agents/architect.md` | 4333 | 6117 | **+1784B** | **tmpl AHEAD** |

The "calc ahead by +5500B / +1440B" estimate was based on pre-PR-#140 state. PR #140 (commit `411c274`, merged 2026-07-17T14:02:20Z, "S32-004+5 sync orchestrator+architect soul files to calc") brought BOTH KAPI HOTFIX + Cadence Rule 2 Retroactive-Close Precondition amend blocks into tmpl.

The +362B orchestrator lead = forward-reference expansion on Issue #144 sister-issue link + ADR-0044/0055/0059 RED-first paragraph on the d-test.
The +1784B architect lead = full Issue #972 Path-Verify Doctrine SOUL AMEND block.

### Trailing-newline check (sister-pattern: NOT a real regression)

The "44B newline regression" mentioned in architect's cycle ~#3449 delta calc is a FALSE POSITIVE. All 4 files (calc orchestrator.md, tmpl orchestrator.md.tmpl, calc architect.md, tmpl architect.md.tmpl) end with the literal bytes `44 45 4e 44` = "D END" with NO trailing newline equivalently. No regression; the cosmetic difference is between calc (which renders `architect.md` with trailing newline) and tmpl (which renders `architect.md.tmpl` without trailing newline by default in many editors).

## Decision

**No port work is needed in the calc→tmpl direction.** Issue #155's premise has reversed in the 24 hours since it was filed; tmpl is now ahead of calc on both soul files.

This ADR documents the actual current state and serves as the anchor-PR for Issue #155's state-correction close (per RETRO-027 §Retroactive-Close Precondition, retroactive close WITHOUT anchor-PR is INVALID; this PR provides the anchor).

### Future work (NOT this PR)

The REVERSE direction — calc back-porting tmpl's lead content (architect Issue #972 Path-Verify Doctrine, orchestrator ADR-0044/0055/0059 RED-first paragraph) — is a separate concern that lives in **Sprint 33+** under a different issue (likely `STORY-S33-NNN: calc back-port tmpl-leads soul content`). The cadence rule applies symmetrically (calc must mirror tmpl's lead content before sprint close), but it does NOT block Issue #155 closure.

## What this PR does

Per Cadence Rule 1 atomic (ADR-0055 §1):

1. **ADR-0072** (this document) — state-correction, `Closes #155`.
2. **d-test d155** (`scripts/tests/d155-s32-026-soul-sync-state.sh`, ≥5 TCs per ADR-0049) — verifies tmpl-leads invariant + KAPI HOTFIX block + RETRO-027 block + Issue #414 SOUL AMEND block + Issue #972 Path-Verify Doctrine SOUL AMEND block presence in tmpl.
3. **scripts/tests/INDEX.md row** — Cadence Rule 1 atomic d-test + INDEX.md entry in same commit.

**No code changes** to `.claude/agents/orchestrator.md.tmpl` or `.claude/agents/architect.md.tmpl` — tmpl already leads calc; the work would be the reverse direction (out-of-scope for Issue #155).

## d-test verification (5 TCs)

See `scripts/tests/d155-s32-026-soul-sync-state.sh`:

- **TC1** — `tmpl orchestrator.md.tmpl` byte count >= `calc orchestrator.md` byte count (tmpl-leads invariant)
- **TC2** — `tmpl orchestrator.md.tmpl` contains KAPI HOTFIX SOUL AMEND markers (`# >>> KAPI HOTFIX SOUL AMEND BEGIN` + `# <<< KAPI HOTFIX SOUL AMEND END`)
- **TC3** — `tmpl orchestrator.md.tmpl` contains Cadence Rule 2 Retroactive-Close Precondition SOUL AMEND markers (`# >>> Cadence Rule 2 Retroactive-Close Precondition SOUL AMEND BEGIN`)
- **TC4** — `tmpl architect.md.tmpl` contains Issue #972 Path-Verify Doctrine SOUL AMEND markers (`# >>> Issue #972 SOUL AMEND BEGIN`)
- **TC5** — `tmpl orchestrator.md.tmpl` contains Issue #414 Dispatch Discipline SOUL AMEND markers (`# >>> Issue #414 SOUL AMEND BEGIN` + 3-rule pre-flight text)

## Why this exists (RETRO-027 lesson)

The reflexive RETRO-024 close of Issue #155 was INVALID because there was no anchor-PR. RETRO-027 §Retroactive-Close Precondition requires BOTH (a) PR-persistence in `origin/main` AND (b) Closes anchor in PR body. Without those, the issue MUST be reopened + dispatched through Cadence Rule 2 §Operational chain. This ADR IS the anchor-PR.

The original premise of Issue #155 has now been overtaken by events (PR #140 landed in between). The right close is state-correction, not pretend-port. Sister-pattern: cycle ~#2919 RETRO-024 work-done-elsewhere retroactive-close lessons, cycle ~#3256 Refs-anchor manual close pattern, cycle ~#3443 ORCH reopen + Cadence Rule 2 dispatch.

## Sister-pattern references

- **PR #140** (tmpl#140 S32-004+5) — original calc→tmpl soul sync that brought KAPI HOTFIX + RETRO-027 (commit `411c274`, merged 2026-07-17T14:02:20Z)
- **PR #163** (tmpl#163 S32-027) — 10 doctrine-critical ADRs port batch (cluster-squash candidate, Issue #156 + PORT-DECISIONS.md)
- **Issue #972** (Path-Verify Doctrine) — issue #972 SOUL AMEND in tmpl architect.md.tmpl (line 82) is the source of the +1784B architect lead
- **Issue #144** (sister-issue d-cadence-rule-2 d-test) — forward-reference resolved by tmpl orchestrator.md.tmpl line 140 (source of part of the +362B orchestrator lead)
- **RETRO-024** — work-done-elsewhere 4-cat exception (NOT applicable here since this PR provides anchor)
- **RETRO-027** — Cadence Rule 2 Retroactive-Close Precondition (this PR is the anchor)
- **Cycle ~#2599** — PM wake-pickup cadence preference (heartbeat-only baseline, peer-poke only on state delta)
- **Cycle ~#3443** — ORCH reopen + Cadence Rule 2 dispatch
- **Cycle ~#3449** — initial architect delta calc that overestimated (pre-PR-#140 state was captured; PR #140 hadn't landed yet)
- **Cycle ~#3453** — RETRO-027 reopen dispatch pickup
- **Cycle ~#3475** — current ground-truth re-query per Issue #972 Path-Verify Doctrine

## Domain lens applicability

- **(a) Data flow**: tmpl → calc single-direction sync chain documented + verified
- **(b) Runtime preconditions**: trust-but-verify pre-flight (Issue #972) caught the reversed-premise anti-pattern
- **(c) API contract**: ADR-0057 Closes anchor strict format honored in PR body
- **(j) Auto-gen refs**: d-test ID 155 allocated for Issue #155 (sister-pattern ADR-0049)
