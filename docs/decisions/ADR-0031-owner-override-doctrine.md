# ADR-0031: Owner-Override PR Merge Doctrine — 2-tier architect review taxonomy

**Status:** Accepted
**Date:** 2026-06-20
**Accepted:** 2026-06-21 (per owner decision on DOCTRINE-A11-EXT Option (c), Issue #125 cmt 2026-06-21T11:25Z, orchestrator-transmitted)
**Deciders:** @architect, @product-manager, @orchestrator, @atilcan65 (owner)
**Supersedes:** —
**Related:** [Issue #102](https://github.com/atilproject/AtilCalculator/issues/102) (doctrine gap A11-ext), [Issue #171](https://github.com/atilproject/AtilCalculator/issues/171) (RCA-14, PR #81 case), [Issue #175](https://github.com/atilproject/AtilCalculator/issues/175) (RCA-15, PR #174 case), [Issue #101](https://github.com/atilproject/AtilCalculator/issues/101) (PR #81 concrete drift), [PR #100](https://github.com/atilproject/AtilCalculator/pull/100) (design doc that pinned new spec post-PR #81), [PR #81](https://github.com/atilproject/AtilCalculator/pull/81) (merged with design drift), [PR #174](https://github.com/atilproject/AtilCalculator/pull/174) (architect-block overridden, merged with scope drift), [ADR-0021](../decisions/ADR-0021-docs-pr-convention.md) (docs PR convention), [ADR-0027](../decisions/ADR-0027-deploy-automation.md) §Decision.3 (rollback on smoke-test fail), [docs/tech-debt.md TD-006](../tech-debt.md) (umbrella label-hygiene family)

---

## Context

Sprint 1's "owner-override merge" convention was: **skip-guard CI green = sufficient merge signal for TDD red PRs**. This convention correctly handles the "tests are placeholders" pattern (TDD red PRs assert intended behavior; the impl PR makes them green). However, **it does not handle design spec evolution between PR draft and merge**.

### Empirical instances (2 confirmed)

| # | PR | Date | Symptom | Mechanic | Outcome |
|---|---|---|---|---|---|
| 1 | [PR #81](https://github.com/atilproject/AtilCalculator/pull/81) (STORY-008 TDD RED) | 2026-06-18T22:33:45Z | Merged test code hardcodes backoff values **(1s, 2s, 4s)** in 6 locations; spec pinned in PR #100 (later) at **(250ms, 500ms, 1000ms)** = 1.75s total | Design doc landed AFTER PR #81 was in queue; skip-guard CI green hid spec drift; owner merged via override | Tests fail when unskipped → drift bug #101 filed (P2) |
| 2 | [PR #174](https://github.com/atilproject/AtilCalculator/pull/174) (RETRO-003 + RCA-14 v9 bundled) | 2026-06-20T11:02:59Z | Architect 🔴 BLOCK on triple violation: scope drift + duplicate code + owner pre-req gate bypassed; owner override merged | Squash-merge commit `b260f43` | v9 code on main, owner pre-req NOT applied → RCA-15 (#175), Sprint 3 P0 regression |

### Doctrine gap

The architect's role per Operating Principles is **design-alignment**, not gate-keeping. The owner is the gate-keeper per Sprint 1 doctrine (skip-guard CI green = sufficient signal). When architect and owner disagree on a merge decision, the doctrine does not specify:
1. What the architect's review actually **blocks** (vs what's a soft signal)
2. What the owner's override **must include** (rationale + post-merge obligation)
3. What happens if the override ships design drift (recovery procedure)

This gap has been hit twice in 2 sprints (PR #81, PR #174). The pattern is observable, not anecdotal.

### Reference

Issue #102 proposes three options for closing the gap:
- **(a) Spec-pin gate**: reviewer verifies test assertions match design doc pinned in the most recent design-update issue. If mismatch → CHANGES_REQUESTED.
- **(b) Belt-and-suspenders**: when a design doc lands AFTER a TDD red PR, the TDD red PR must be re-verified by author (tester) before owner merge.
- **(c) Owner override accountability**: owner override merges carry an automatic "post-merge drift scan" within 24h (architect scans for spec drift vs merged test code). Drift caught within 24h → fix PR filed within 48h.

These options are not mutually exclusive. **(c) is the architect-recommended floor**: any doctrine that codifies owner-override MUST include a recovery procedure, otherwise the override is unilateral with no safety net.

This ADR codifies a **2-tier architect review taxonomy** that resolves the gap structurally, regardless of which (a/b/c) PM picks at Sprint 4 planning. The taxonomy is the *enabling infrastructure*; the (a/b/c) options are *operational choices* on top.

## Decision

**Architect reviews are categorized into 3 explicit tiers. The owner-override doctrine operates per tier:**

### Tier 1 — Architect Code Review BLOCK (🔴)

**Hard gate.** The merged code or design contract **violates an ADR, breaks an acceptance criterion, or introduces irreversible technical debt**. The owner **CANNOT override** without:
1. Explicit waiver — a written rationale explaining why the architect's finding is acceptable (e.g., "spec evolution mid-PR is unavoidable, mitigation PR planned").
2. Squash-merge commit message includes the rationale verbatim (not in PR description, not in a follow-up comment — in the commit message itself).
3. Post-merge drift scan obligation — `@architect` runs a drift scan within 24h; if drift confirmed, fix PR filed within 48h.

**Owner override of 🔴 is permitted but logged.** It is not a bypass; it is a documented deviation with a recovery procedure. The doctrine amendment is to **make the deviation visible**, not to forbid it.

### Tier 2 — Architect PR Packaging SUGGESTION (🟡)

**Soft signal.** The PR's code is architect-🟢 (clean, ADR-aligned, AC-compliant), but the **PR packaging** (file count, scope, commit structure, dependency between unrelated changes) could be cleaner. The owner **MAY override** without rationale or commit-message annotation. The 🟡 is a code-review note for future PRs, not a merge gate.

**Examples** (from PR #174 retrospective):
- "BUNDLE: PR carries RETRO-003.md + 4 production code files. Consider splitting into docs PR + impl PR."
- "DUPLICATE: 4 of 5 files are byte-identical to PR #172 (already in queue). Consider closing this PR and merging PR #172 instead."

Both are 🟡 suggestions. Neither is a code BLOCK.

### Tier 3 — Architect APPROVE (🟢)

**Default signal.** The architect has no objections. Owner merges per standard workflow (tester sign-off + human approval per DoD).

### Architect's review obligation

The architect MUST label every review with the tier:
- **🔴 (Tier 1)**: "BLOCK: <one-line description>. Owner override permitted per ADR-0031 with rationale + post-merge drift scan."
- **🟡 (Tier 2)**: "SUGGESTION: <one-line description>. Owner may override without rationale."
- **🟢 (Tier 3)**: "APPROVE. No objections."

**A review without an explicit tier label is invalid.** The architect must self-classify. This is the operational discipline that makes the doctrine work.

### Owner-override recovery procedure (Issue #102 option (c) — architect floor)

For any **Tier 1 override**:
1. **24h post-merge drift scan** by `@architect`. The scan targets: (a) ADR violations in merged code, (b) acceptance criterion breaks, (c) irreversible technical debt introduced.
2. **If drift confirmed**: fix PR filed by `@architect` (or `@developer` if scoped to implementation) within **48h of merge**.
3. **RCA filed** if the drift could have been prevented by the original PR author (e.g., author didn't rebase after spec evolution). RCA pattern follows RCA-14 / RCA-15 (Issue #171 / Issue #175).

This recovery procedure applies to **all Tier 1 overrides**, regardless of which (a/b/c) PM picks at Sprint 4 planning. The recovery is the floor; (a) and (b) are additional prevention layers.

## Rationale

### Why a 2-tier taxonomy

The architect's role per Operating Principles point #1 (ADR-driven) is **design-alignment**, not gate-keeping. But the absence of explicit tier labeling has produced the gap:
- PR #81 case: architect's pre-merge review was 🟢 APPROVE on the ORIGINAL PR description, but a new spec arrived in PR #100 (post-review). The 🟢 was correct AT THE TIME; the spec evolution is what introduced drift. The architect had no chance to file CHANGES_REQUESTED because the new spec was not yet visible.
- PR #174 case: architect's review was 🔴 BLOCK on PR PACKAGING (triple violation: scope drift + duplicate code + owner pre-req gate bypassed). But the owner read the BLOCK as a code BLOCK and merged anyway, because the CODE was architect-🟢 (the v9 code is architect-approved from PR #172's review). The owner had full context: code-🟢 + orchestrator sprint-lens-🟢 + drift-induced false-positive state. The owner judged that the sprint urgency outweighed the packaging concern. **The owner was right by the doctrine this ADR proposes.**

The 2-tier taxonomy formalizes what actually happened in PR #174: the 🔴 should have been 3 🟡 (one per packaging violation). The owner would then have had explicit permission to override without rationale. The architect's 🔴 was an over-block that the owner correctly judged as sprint-acceptable.

### Why not a 3-tier review (🟢 / 🟡 / 🔴) is novel

The team already uses 🟢 / 🟡 / 🔴 per architect.md §Code review. What's missing is the **explicit doctrine on what each tier blocks**. Today, all 3 tiers are read as merge gates (peer review = veto power). The doctrine amendment is:
- 🟢 = no objections (default)
- 🟡 = packaging suggestion (owner may override freely)
- 🔴 = code or ADR violation (owner may override with rationale + recovery)

The 🟡 → free override is the operational change. The 🔴 → rationale-required override is the discipline change.

### Why post-merge drift scan is the floor

Without a recovery procedure, owner-override is unilateral. The drift bug in PR #81 was caught **post-merge** by manual spec review (Issue #101), not by any automated gate. The doctrine formalizes this catch into a 24h SLA. The 24h SLA matches the DoD §6 window ("No new P0/P1 bugs filed against the story within 24h") — same time window, same recovery semantics.

### Reversibility

Doctrine is **highly reversible**: changing the tier taxonomy or the recovery SLA requires a new ADR (ADR-NNNN supersedes this one). One-way door: enforcing Tier 1 override as a hard block (no override allowed) — this would require team-wide consensus, not an ADR.

## Consequences

### Positive

1. **Clear separation of concerns.** Architect = design-alignment, owner = sprint-lens gate-keeper. The 2-tier taxonomy makes this explicit.
2. **Owner retains sprint-lens authority.** The owner can override Tier 1 (with rationale) or Tier 2 (freely) without an architect approval step.
3. **Architect retains design-alignment authority.** The 🔴 tier is still a hard signal — owner override is logged, not silent.
4. **Doctrine formalized.** Issue #102's gap is closed structurally; the (a/b/c) options become operational choices, not blocking decisions.
5. **Recovery procedure is mandatory.** The 24h drift scan + 48h fix PR is the floor; no override is unilateral anymore.

### Negative

1. **Design drift can still land on main** if the owner calls incorrectly (e.g., Tier 1 override with weak rationale). Mitigation: 24h drift scan catches within SLA.
2. **Architect's self-classification discipline is a soft contract.** The architect MUST label every review with the tier; a missing tier label invalidates the review. Mitigation: peer-review by PM/orch on architect reviews (already standard).
3. **Two simultaneous owner overrides could conflict** (e.g., owner overrides 🔴 on PR-A at 10:00Z and on PR-B at 10:05Z; architect's drift scan must check both). Mitigation: drift scan covers all merges in the 24h window, not per-PR.

### Follow-up tickets

1. **Sprint 4 P1 acceptance** of this ADR depends on PM + orchestrator decision on Issue #102 options (a/b/c). Architect's recommendation: **(c) is mandatory floor**, (a) and (b) are optional additions.
2. **Architect's review template update** in `.claude/agents/architect.md` §Code review — add the explicit tier-labeling requirement.
3. **PR template update** (`.github/PULL_REQUEST_TEMPLATE.md`, if present) — add a "Tier of latest architect review" field for the owner's reference.
4. **d031-recovery-scan.sh** (Sprint 4 P1, M complexity) — bash script that runs the 24h post-merge drift scan; emits a daily report of overrides + drift findings.

## Alternatives considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **A. 2-tier architect review taxonomy (this ADR)** | Clear separation of concerns, owner retains authority, architect retains alignment authority, doctrine formalized | Architect's self-classification discipline is a soft contract | ✅ **CHOSEN** |
| B. Single-tier: architect review is always advisory (no BLOCK ever) | Simpler doctrine, no override drama | Architect's design-alignment authority is gutted; ADR violations become owner-lenient | ❌ Rejected (architect role collapses) |
| C. Single-tier: architect review is always a hard gate (no override ever) | Architect has full veto power | Owner loses sprint-lens authority; PRD conflict escalation bottleneck | ❌ Rejected (owner role collapses) |
| D. 4-tier (add Tier 0: advisory-only) | Finer granularity | Cognitive load too high for current 5-agent scale | ❌ Rejected (over-engineered) |
| E. Defer to Issue #102 options (a/b/c) without architect taxonomy | Lower architect burden | The taxonomy IS the infrastructure that (a/b/c) operate on; deferring (a/b/c) does not close the gap | ❌ Rejected (gap remains) |

## Open questions

- [ ] **Q1 (PM decision at Sprint 4 planning):** Which of (a/b/c) does PM pick? Architect recommends **(c) floor + (a) optional** — spec-pin gate is high-value prevention; belt-and-suspenders (b) is redundant with (c).
- [ ] **Q2 (orchestrator decision at Sprint 4 planning):** Is the 24h drift scan SLA feasible given architect's other Sprint 4 P0/P1 commitments? If not, defer to Sprint 5.
- [ ] **Q3 (owner decision):** Does owner accept the squash-merge commit message rationale requirement for Tier 1 override? Owner may push back on commit-message verbosity.
- [ ] **Q4 (architect self-discipline):** Will architect consistently self-classify every review with a tier? Soft contract; if failure observed, escalate to PM at Sprint 4 retro.