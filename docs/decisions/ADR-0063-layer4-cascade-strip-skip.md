# ADR-0063: §Layer 4 Cascade-Strip Part 2.5 — Lane-Transition Skip

- **Status**: Accepted
- **Date**: 2026-07-19
- **Deciders**: @architect
- **Supersedes**: none
- **Related**: [ADR-0012](./ADR-0012-required-label-set.md) (cascade-strip Part 1), [ADR-0015](./ADR-0015-atomic-agent-handoff.md) (atomic handoff / Lane Discipline), [ADR-0048](./ADR-0048-status-ready-auto-add-gating.md) (Part 2 status:ready auto-add), [ADR-0049](./ADR-0049-behavioral-workflow-test-framework.md) (d-test framework), [ADR-0050](./ADR-0050-pre-merge-4-cat-verification.md) (4-cat verification sister-pattern), [ADR-0055](./ADR-0055-d-test-id-uniqueness-sub-pattern-matrix.md) (Cadence Rule 1 atomic), [ADR-0056](./ADR-0056-layer-5-idempotency-reconcile.md) (Layer 5 idempotency reconcile)
- **Ported-from**: AtilCalculator ADR-0063 (S32-027 Cadence-Rule-2-B DEFERRED renumber/port batch, Issue #164)

> Ported from AtilCalculator ADR-0063 as part of S32-027 Cadence-Rule-2-B (Issue #164). Calc-specific instances redacted; portable doctrine preserved. Cycle-number lineage retained as historical provenance.

---

## Context

ADR-0012 §Cascade-strip scope-tightening Part 1 established that when a PR carries multiple `status:*` labels (e.g., `status:in-review + status:ready`), Layer 4 of the label-check workflow must remove **only the duplicate** (most-recent by createdAt) and preserve the canonical primary (oldest). It MUST NOT cascade-strip the reviewer chain (`cc:*` + `needs-*-signoff`).

**However, Part 1's cascade-strip fires on the `unlabeled` event regardless of what was unlabeled.** When the `unlabeled` label is `cc:tester` or `needs-tester-signoff` (i.e., a **lane-transition event** signaling tester verdict posted), Part 1's strip is **incorrect** — the layer is interpreting a verdict lane transfer as a duplicate-status trigger.

### Triggering LIVE INSTANCE (RETRO-016 #6)

A tester APPROVED PR exhibited the following sequence in its bot audit-trail:

| Time (relative) | Bot marker | Layer | Action |
|-----------------|------------|-------|--------|
| T+0s | (tester verdict) | — | PR Review APPROVED posted (tester self-sign-off) |
| T+15s | Layer 4 cascade-strip marker | Layer 4 | Trigger: `unlabeled cc:tester`. Status labels observed: `status:in-review, status:ready`. Primary (oldest): `status:in-review`. **Removed: `status:ready`** as duplicate |
| T+17s | Layer 5 status:ready gating marker | Layer 5 | Trigger: `unlabeled needs-tester-signoff`. `status:ready` auto-added (per ADR-0048 §Type-driven) |
| T+84s | Layer 5 TC4 reversal marker | Layer 5 TC4 reversal | Trigger: `undefined` event, action=`labeled`, label=`needs-tester-signoff`. **Removed: `status:ready`** ("tester re-rejected after APPROVED — needs-tester-signoff re-added" per bot log) |

**Net pathology**: `status:ready` added then removed twice. Final state: no `status:*` label on PR (`type:feature + agent:developer + cc:human` only). **4-cat invariant visually broken** until owner manually re-adds `status:ready`.

### Root cause

**Layer 4 cascade-strip** (label-check workflow):
- Reads `target.labels` from event payload snapshot
- Sees `[status:in-review, status:ready, ...]` at `unlabeled cc:tester` event time
- Sorts by `earliestByName.get()` createdAt, treats newer `status:ready` as duplicate, removes it
- **Bug**: Does not distinguish between Layer 5's INTENTIONAL `status:ready` add (per ADR-0048, auto-promote on reviewer-chain-clear) and an accidentally-duplicated `status:*` label

**Layer 5 TC4 reversal handler** (label-check workflow):
- Fires on `labeled needs-tester-signoff && hasLabel('status:ready')`
- Removes `status:ready` unconditionally
- **Bug**: Does not verify the `labeled needs-tester-signoff` event was triggered by an actual tester re-rejection (vs. a phantom/side-effect re-label from Layer 4 cascade-strip)

**Race window:**
1. Tester approves → triggers `unlabeled cc:tester` + `unlabeled needs-tester-signoff` (sequence not guaranteed)
2. Layer 4 fires on `unlabeled cc:tester` → sees 2 status labels → cascade-strips `status:ready`
3. Layer 5 fires on `unlabeled needs-tester-signoff` (sister event) → re-adds `status:ready`
4. Some `labeled needs-tester-signoff` event fires (Layer 4 cascade-strip side-effect, or workflow re-trigger) → Layer 5 TC4 reversal removes `status:ready` again
5. Net: `status:ready` absent

## Decision

Extend Layer 4 cascade-strip scope-tightening with **Part 2.5 — Lane-transition event skip**. Layer 4 MUST skip `unlabeled` events where the unlabeled label starts with `cc:` or `needs-`, because these are **intentional lane transitions**, not status-reset signals.

### §Part 2.5 Lane-Transition Skip

Additive to ADR-0012 §Part 1 + §Part 2 (ADR-0048 status:ready auto-add gating):

```yaml
# PSEUDOCODE (label-check.yml Layer 4, early-return):
# ------------------------------------------------------------------
# ADR-0063 Part 2.5: Layer 4 cascade-strip MUST skip unlabeled events
# where the unlabeled label is a lane-transition signal (cc:* or
# needs-*-signoff). Verdict lane transfers are verdict semantics, not
# status-reset triggers.
# Sister-pattern: ADR-0048 silent_skip lens d; Issue sister-pattern TC1
# short-circuit on status:* unlabeled. LIVE INSTANCE: tester APPROVED
# PR race pattern (RETRO-016 #6).
# ------------------------------------------------------------------
if (evtAction === 'unlabeled' &&
    context.payload.label &&
    (context.payload.label.name.startsWith('cc:') ||
     context.payload.label.name.startsWith('needs-'))) {
  core.info(`[Layer 4 RETRO-016 #6] lane-transition short-circuit (label=${context.payload.label.name}) — verdict semantics, not status reset.`);
  return;  // skip cascade-strip; allow existing logic to handle status:* state
}
```

### Decision rules

| Event type | Unlabeled label is `cc:*` or `needs-*` | Layer 4 action |
|------------|----------------------------------------|----------------|
| `unlabeled cc:tester` (tester lane transfer) | yes | **SKIP cascade-strip** (Part 2.5) |
| `unlabeled cc:developer` (dev lane transfer) | yes | **SKIP** |
| `unlabeled cc:architect` (arch lane transfer) | yes | **SKIP** |
| `unlabeled cc:human` (owner lane transfer) | yes | **SKIP** |
| `unlabeled needs-tester-signoff` (signoff cleared) | yes | **SKIP** |
| `unlabeled needs-architect-review` (signoff cleared) | yes | **SKIP** |
| `unlabeled status:ready` (manual flip per silent_skip sister-pattern) | no (status:) | Existing logic (Layer 5 silent_skip) — handled by separate branch |
| `unlabeled status:in-review` (manual flip) | no | Existing cascade-strip logic (Part 1 — preserves canonical primary) |

### Why this path (not alternatives from the carrier issue)

**Alternative B (Layer 5 TC4 reversal verify re-rejection signal)** — adds sender-type check + re-rejection signal in same event payload. **Rejected**:
- (+) No false-strip on legitimate re-rejection
- (-) Does not fix the underlying Layer 4 over-strip pathology (race still observable via `unlabeled cc:tester` → cascade-strip fires before Layer 5 re-add)
- (-) Combines multiple event semantics into one check (sender-type + re-rejection signal); harder to d-test
- (-) Layer 5 reversal handler has different scope than Layer 4 cascade-strip; mixing concerns

**Alternative C (post-event state fetch)** — both Layer 4 and Layer 5 fetch CURRENT labels via the issues API instead of reading from event snapshot. **Rejected**:
- (+) No stale-snapshot race
- (-) Latency: extra API call per event (Layer 4 + Layer 5 × N events)
- (-) GitHub Actions rate-limit risk on high-traffic repos
- (-) Does not address the doctrinal gap (Layer 4 interpreting lane-transition as status-reset)

**Path A (Layer 4 lane-transition skip)** — **CHOSEN**:
- (+) Minimal LoC delta (~6 LoC, sister-pattern to silent_skip TC1 short-circuit)
- (+) Doctrinal clarity: lane-transition events are verdict semantics (Lane Discipline per ADR-0015), Layer 4 (status-cascade layer) should not interpret them
- (+) Sister-pattern to Layer 5 TC1 silent_skip — both layers short-circuit on lane-transition `unlabeled` events
- (+) No new API calls (uses event payload already in scope)
- (+) Compatible with ADR-0056 (Layer 5 idempotency reconcile) — Layer 5 still self-corrects on next label event
- (-) Does not address Layer 5 TC4 reversal phantom-trigger separately (separate doctrine gap, deferred)

### Why now (P2 doctrine hardening, not later)

The RETRO-016 cluster has multiple LIVE INSTANCES in a short window (sister-pattern #1, #3, #5, #6). Pattern is **active, not historical**. P2 doctrine hardening is the right vehicle.

The exemplar PR specifically blocks the current Wave 2 PR squash cadence — its state has `type:feature + agent:developer + cc:human` only (no `status:*`); owner cannot squash until `status:ready` is manually re-added (one-shot operator action per the carrier issue §Decision matrix).

## Rationale

### Why extend Layer 4 (not Layer 5 reversal handler)

| Option | Cost | Doctrinal clarity | Symmetry | Verdict |
|--------|------|-------------------|----------|---------|
| **A. Layer 4 lane-transition skip (THIS)** | ~6 LoC | High (lane-transition ≠ status-reset) | Sister-pattern TC1 silent_skip | **Chosen** |
| **B. Layer 5 reversal verify re-rejection** | ~25 LoC | Medium (sender-type check + signal) | None | Does not fix L4 over-strip |
| **C. Both Layer 4 + Layer 5 fetch current state** | ~40 LoC | Low (state-reconciliation in two layers) | None | Latency + rate-limit |
| **D. Disable Layer 4 cascade-strip entirely** | ~0 LoC | Very low (loses Part 1 duplicate removal) | None | Reverts Part 1 fix |

### Evidence

- **Tester APPROVED PR (exemplar LIVE INSTANCE)** — primary carrier; bot audit-trail shows the cascade-strip-then-restore-then-strip sequence
- **Part 1 canonical case** — sister-pattern PR demonstrating Part 1 duplicate removal on non-lane-transition events
- **RETRO-016 #1, #3, #5 sisters** — pattern is repeated, not isolated
- **ADR-0048-amendment** — Path A verdict-state-aware WARN-not-FAIL proven in production
- **ADR-0056** — Layer 5 idempotency reconcile WARN-not-FAIL proven in production

### Compatibility

- Backward compatible with ADR-0012 Part 1 (canonical-primary duplicate removal preserved for non-lane-transition events)
- Backward compatible with ADR-0048 (Layer 5 `status:ready` auto-add unchanged; only Layer 4 cascade-strip fires less often)
- Backward compatible with ADR-0056 (Layer 5 idempotency reconcile still self-corrects on next event)
- Backward compatible with ADR-0062-sister-pattern (Layer 5 label-change verdict gate; orthogonal concern, no overlap — separate ADR in calc repo, not ported here)

## Consequences

### Positive

- Race pattern closed; `status:ready` will not be cascade-stripped on lane-transition `unlabeled` events
- Layer 4 doctrine gap closed (Layer 4 = duplicate-status layer; NOT verdict-lane layer)
- §9-Lens lens (b) Runtime preconditions + lens (d) Silent-skip improved (Layer 4 silent_skip on lane-transition)
- Sister-pattern symmetry with Layer 5 TC1 silent_skip — both layers short-circuit on lane-transition `unlabeled`
- ~6 LoC implementation (within P2 budget; well below Path B + C cost)
- Exemplar PR owner-disposition actionable: re-add `status:ready` (carrier issue §Decision matrix option)

### Negative (mitigated below)

- Edge case: what if a PR has actual `status:*` duplicate + concurrent `cc:tester` removal? (R1) — mitigate: duplicate-status removal is Part 1 sister-pattern; Part 2.5 only skips when the UNLABELED label is `cc:*` or `needs-*`; if a separate `status:*` add/remove fires, Part 1 still applies
- Layer 5 TC4 reversal handler remains unfixed (separate phantom-trigger pathology) (R2) — mitigate: deferred to a separate ADR (out of RETRO-016 #6 scope; Layer 5 reversal is distinct concern)
- Owner merge required per file ownership matrix (R3) — mitigate: standard P2 codification workshop flow (arch drafts, tester signs off, owner merges)
- Exemplar PR still needs manual `status:ready` re-add (R4) — mitigate: one-shot operator action per carrier issue §Decision matrix; document in PR squash notes

### d-test integration

**New d-test required** (sister-pattern to the existing dNNN family — d069/d073/d075/d076/d077/d081/d091/d093):

```bash
# dNNN d-test contract (ADR-0049 + ADR-0044 RED-first):
# 3 minimum TCs per ADR-0049:
# TC1: PR with status:in-review + status:ready → unlabeled cc:tester → status:ready preserved (Part 2.5 SKIP)
# TC2: PR with status:in-review + status:ready → unlabeled status:in-review → status:ready preserved as canonical primary (Part 1 unchanged)
# TC3: Regression — PR with actual duplicate status:in-review + status:in-review-stale → unlabeled status:in-review-stale → status:in-review-stripe removed (Part 1 unchanged)
# Optional TC4: exemplar PR replay simulation (full Layer 4 + Layer 5 sequence, verify final state has status:ready)
```

**Cadence Rule 1 atomic (ADR-0055 §1)**: this ADR + d-test + INDEX.md row in same PR.

### Sister-pattern: future prevention

- **RETRO-016 #5** — Layer 5 false-positive verdict-gate on cc:* label-change. **Separate ADR** (in calc repo, not ported here) — Layer 5 doctrine gap; orthogonal concern.
- **RETRO-016 #1** — already closed (Layer 5 initial-add race fix)
- **RETRO-016 #3** — closed (cross-watchdog 30s gap fix)
- **Layer 5 TC4 reversal handler phantom-trigger** (R2 above) — P3 candidate for separate ADR

## Implementation checklist (P2 codification)

**Pre-Phase 0 (arch + tester)**:
- [ ] dNNN d-test drafted (tester-led, RED-first per ADR-0044)
- [ ] 3 minimum TCs as above (TC1/2/3) + optional TC4 exemplar replay

**Phase 0 (arch authored)**: THIS ADR (docs PR lane; sprint-gated)

**Phase 1 (dev + tester)**:
- [ ] 1.1 yaml impl in `.github/workflows/label-check.yml` (~6 LoC, file ownership matrix human-only → owner merges)
- [ ] 1.2 dNNN TC1/2/3 GREEN

**Phase 2 (owner)**:
- [ ] 2.1 Owner manually re-add `status:ready` to exemplar PR (one-shot operator action per carrier issue §Decision matrix option)
- [ ] 2.2 Owner squash exemplar PR + sprint wave merge (status:ready restored, 4-cat invariant intact)
- [ ] 2.3 Owner squash workflow file change PR for Part 2.5

**Phase 3 (orch + all)**:
- [ ] 3.1 RETRO-016 watchlist updated: #6 closed by THIS ADR
- [ ] 3.2 Carrier issue status:done

## Cross-refs

- **RETRO-016 cluster** — #1, #3, #5, #6 (THIS)
- **ADR-0012** — cascade-strip Part 1 (this ADR adds Part 2.5)
- **ADR-0015** — atomic agent hand-off (Lane Discipline)
- **ADR-0048** — status:ready auto-add gating (Part 2 of ADR-0012 cascade-strip scope-tightening)
- **ADR-0049** — d-test framework
- **ADR-0050** — 4-cat verification
- **ADR-0055** — d-test ID uniqueness + Cadence Rule 1 atomic
- **ADR-0056** — Layer 5 idempotency reconcile
- **File ownership matrix**: `.github/workflows/` = human-only (arch + tester draft, owner merges)

— Ported from AtilCalculator ADR-0063 (cycle ~#1610, AtilCalculator-arch authored, 2026-06-30, post-claim-next-ready auto-pickup)
