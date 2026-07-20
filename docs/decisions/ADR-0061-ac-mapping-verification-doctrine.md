# ADR-0061: §AC Mapping Verification Doctrine (arch verdict pre-ratification AC list 1:1 mirror)

- **Status**: Accepted
- **Date**: 2026-07-19
- **Deciders**: @architect (doctrine spec + `.claude/agents/architect.md` amendment), @product-manager (cross-lane sponsor), @atilcan65 (owner squash gate for soul amendment per file ownership matrix)
- **Supersedes**: none
- **Related**: ADR-0012 (4-cat label invariant — applied at spec level), ADR-0015 (atomic 4-flag handoff — doctrine protocol exit codes 0/1/2/3 = handoff states), ADR-0044 (RED-first TDD), ADR-0045 (9-Lens pre-publish gate — lens a data flow augmented), ADR-0048 (type-driven verdict gate matrix), ADR-0049 (d-test framework), ADR-0055 (Cadence Rule 1 atomic — ADR + design doc + INDEX.md in same PR), ADR-0059 (cluster-squash batch-lag detection — sister-pattern: arch design + ADR + INDEX atomic)
- **Ported-from**: AtilCalculator ADR-0060 (RENUMBERED to tmpl 0061 to avoid collision with tmpl ADR-0060 Claude-Code-agent-flag; S32-027 Cadence-Rule-2-B, Issue #164)

> **Doctrinal home note**: This ADR is the canonical home for §AC mapping verification doctrine. The doctrine is operationalized in `.claude/agents/architect.md` as a new section "§AC Mapping Verification Doctrine" (sister-pattern to orchestrator's §Verdict-by Discipline). Sister-pattern: PM-side §Pre-citation cross-check + PM-side §Timing window + Arch-side §AC mapping verification (this ADR) = **cross-lane "verify-before" doctrine triangulation**.

## Context

> **Ported from AtilCalculator ADR-0060, renumbered to 0061 (tmpl 0060 collision) as part of S32-027 Cadence-Rule-2-B (Issue #164).**

### Arch AC mapping drift LIVE INSTANCE

An upstream P1 cluster surfaced a real AC drift event:

- **Design doc** for a STORY (PR carrying ADR + design + INDEX atomic per ADR-0059) listed N ACs (AC1..ACn) per ADR-0059 §1-§3.
- **Impl branch** discovered mid-flight that AC4 (a documentation / curatorial gap) was a parallel concern needing its own lane endorsement, not a pure detector impl AC.
- **Disposition cycle** — multi-lane consensus (arch + dev + tester + PM + orchestrator) resolved via rescope option (AC4 → F3 explicit jq check) + Option X (F3 jq error check) without owner escalation.
- **Detection**: Tester review caught the drift during doctrinal clear phase, NOT during design phase.

**Pattern**: AC mapping drift in arch slice = design doc AC list vs impl AC list diverge mid-flight. Caught late (in impl phase), resolved by ad-hoc multi-lane consensus. No codified doctrine forces 1:1 verification BEFORE ADR ratification.

### Architectural gap (no canonical doctrine)

As of 2026-07-19, **no arch doctrine forces AC list 1:1 verification** between design doc §Acceptance Criteria and impl branch AC list. Current state:
- AC mapping verification is informal — relies on reviewer (tester or arch) noticing drift during review.
- The drift cycle was the LIVE INSTANCE; no codified prevention.
- Codified as a Tier 1 cluster ProcessGap.
- PM sponsor commitment + cross-lane "verify-before" triangle (PM-side pre-citation + timing window + Arch-side §AC mapping verification = this ADR).

### Sister-pattern (cross-lane "verify-before" triangle)

- **PM-side §Pre-citation cross-check** — PM verdict on any PR re-queries comments[] AND reviews[] before posting verdict.
- **PM-side §Timing window** — re-query ground truth within 30s of verdict post.
- **Arch-side §AC mapping verification** (this ADR) — arch verdict on type:docs + agent:architect PR re-queries impl branch AC list, mirrors design doc AC1..ACn 1:1.

All 3 doctrines = cross-lane "verify-before" triangulation. PM-side ratified. Arch-side codification in flight (this ADR).

## Decision

Adopt **§AC mapping verification doctrine** with 5 canonical components:

### §1 — Mandatory pre-ratification check

**Trigger**: Every arch verdict on `type:docs` PR with `agent:architect` label MUST execute §AC mapping verification BEFORE posting verdict comment.

**Why**: Arch verdict is the lane-monitoring signal that downstream peers (tester, PM, owner) rely on for AC list correctness. If arch verdict passes with AC drift undetected, the drift propagates downstream as spec-level truth, forcing costly mid-flight rescope (LIVE INSTANCE cost = multi-lane consensus + AC4 mid-flight rescope).

**Pre-condition**: Design doc MUST have a §Acceptance Criteria section listing AC1..ACn. If absent → exit code 2 (legacy/exception, log warning, proceed with arch verdict — explicit non-silent).

### §2 — Protocol (6 steps)

**Step 1**: Re-query impl branch AC list via gh API (`gh api repos/{owner}/{repo}/pulls/{N} --jq '.body'`).

**Step 2**: Extract AC labels from impl body using regex `^- \*\*AC\d+\*\*/` OR `^- AC\d+/` (tolerates both `**AC1**` and `AC1` forms).

**Step 3**: Extract AC labels from design doc §Acceptance Criteria using same regex.

**Step 4**: Compare: 1:1 set match required on AC1..ACn. AC0 (impl-only housekeeping) is exempt.

**Step 5**: If drift detected → flag in 9-Lens review (lens a: data flow) as 🟡 NEEDS CHANGES, citing drift (`design=[AC1,AC2,AC3], impl=[AC1,AC2,AC4]`).

**Step 6**: If no drift → AC mapping verification passed ✅, proceed with arch verdict (🟢 OK / 🟡 Suggestion / 🔴 Block).

### §3 — Doctrine protocol exit codes

| Code | Semantic | Verdict action |
|------|----------|----------------|
| 0 | AC list 1:1 verified | Proceed with verdict (🟢 / 🟡 / 🔴) |
| 1 | AC drift detected | Verdict must include 🟡 NEEDS CHANGES citing drift |
| 2 | Design doc has no AC section | Log warning, proceed (legacy/exception, explicit non-silent per ADR-0048 lens d) |
| 3 | Impl branch not yet opened | Doctrine dormant this iteration (design-only), proceed |

**Why explicit exit codes**: Doctrine protocol exit codes mirror ADR-0015 atomic 4-flag handoff states. Each exit code has a prescribed verdict action — no implicit / silent skip path. Per ADR-0048 lens d (silent-skip risk), every conditional branch MUST log a structured event.

### §4 — 9-Lens lens a (data flow) augmentation

Per ADR-0045 9-Lens pre-publish gate, lens a (data flow) is augmented with AC mapping verification:

```yaml
lens_a_data_flow:
  standard_check: "Trace request/response path end-to-end"
  doctrine_augmentation: "Verify design doc AC1..ACn 1:1 mirrors impl branch AC list"
  output:
    verified: "AC mapping 1:1 ✅, data flow trace clean"
    drift: "AC drift detected: design=[AC1,AC2,AC3], impl=[AC1,AC2,AC4] — NEEDS CHANGES"
```

**Sister-pattern**: lens augmentation = additive to existing 9-Lens checks, NOT replacement. AC mapping verification augments lens a; other 10 lenses unchanged.

### §5 — Cross-lane "verify-before" triangle completion

This ADR + `.claude/agents/architect.md` amendment completes the cross-lane "verify-before" doctrine triangulation:

- **PM-side §Pre-citation cross-check** — ratified
- **PM-side §Timing window** — ratified
- **Arch-side §AC mapping verification** (this ADR) — codification in flight

**Triangle complete when**: Both PM-side ratified + Arch-side ratified by owner (PR with this ADR merged to main). Arch slice is the LAST doctrine needed for triangulation completion.

**Sister-pattern to orchestrator §Verdict-by Discipline**: Combined with PM-side + Arch-side doctrines, 3-lane expectation + verification doctrine triangulation is in flight.

## Rationale

### Why this doctrine now (LIVE INSTANCE)

The drift cycle surfaced as a real drift event in an upstream P1 cluster. Without codified doctrine, future AC drift events rely on:
- Tester doctrinal clear catching drift late (impl phase)
- Multi-lane ad-hoc consensus resolving drift (expensive, not always feasible)
- Owner escalation as backstop (slow, not scalable)

Doctrine codifies the EARLY detection path (arch verdict phase, BEFORE peer review phase) and eliminates tester-as-drift-catcher anti-pattern.

### Why file ownership matrix correctness (architect.md over script)

Per file ownership matrix:
- `.claude/agents/architect.md` = arch lane draft territory (owner squash gate for soul amendment)
- `scripts/` + `scripts/tests/` = dev lane territory (out of scope for arch slice)
- `.github/workflows/` = human-only territory (out of scope)

Doctrine codification in `architect.md` is the **correct lane** for arch doctrine. Script-based enforcement is a future candidate when dual-channel-enforcement d-test warrants it.

### Why doctrine not CI gate (deferred)

Doctrine codification is the **first step**; CI gate enforcement comes after doctrine has been operationally validated for ≥1 sprint.

### Why cross-lane "verify-before" triangle (3-lane triangulation)

PM-side doctrines + Arch-side doctrine (this ADR) = 3-lane "verify-before" triangulation. Each lane enforces its own verify-before protocol at verdict time:
- PM: comments[] + reviews[] + ground truth timing window
- Arch: design doc AC list + impl branch AC list mirror
- Orch: cc:<role> + verdict-by:<ts> expectation-set

All 3 lanes converge on **peer-verdict-quality** as the shared objective. Triangulation ensures no single lane is the verify-before bottleneck.

## Consequences

### Positive outcomes

1. **AC drift eliminated as failure mode** — every arch verdict 1:1 verifies AC list before peer review phase. Drift-class events become structurally impossible.
2. **Tester role returns to doctrinal clear, not drift detection** — tester no longer catches arch slice drift (which is arch's job, not tester's). Tester focuses on d-test sign-off per ADR-0044.
3. **Owner escalation cost reduced** — ad-hoc multi-lane consensus on AC drift replaced by deterministic arch verdict verdict (🟡 NEEDS CHANGES citing drift).
4. **Cross-lane "verify-before" doctrine triangulation complete** — 3-lane peer-verdict-quality framework operationalized. PM-side + Arch-side + Orch-side doctrines form a coherent verification ecosystem.

### Negative tradeoffs

1. **Arch verdict latency increases** — every arch verdict now requires gh API call + grep + set comparison. Estimate +2-5s per verdict (within p95 budget of design doc §Performance budget).
2. **AC0 exemption needs governance** — design doc spec'd AC1..ACn, impl legitimately may add AC0 (impl-only housekeeping). Doctrine protocol allows AC0 exemption, but requires consistent interpretation across arch verdicts. Open question in design doc §Open questions.
3. **Doctrine dormant on design-only iterations** — when impl branch not yet opened (exit code 3), doctrine doesn't fire. Drift undetected until impl phase. Mitigation: design doc §Acceptance Criteria is the canonical home for AC list (impl must mirror it, not the other way around).

### Follow-up tickets to file

- **TD-NEW (TBD)**: AC0 exemption scope clarification (doctrine OQ #1) — backlog candidate.
- **TD-NEW (TBD)**: Doctrine enforcement at PR creation vs PR review (doctrine OQ #2) — backlog candidate.
- **TD-NEW (TBD)**: Cross-repo propagation timeline (doctrine OQ #3) — future candidate.
- **Future CI gate**: `scripts/check-ac-mapping.sh` + d-test sister-pattern — out of scope for this sprint.

## Alternatives considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **A. Codify in architect.md (CHOSEN)** | Operates on arch lane directly; minimal ceremony; aligned with file ownership matrix (architect.md = arch territory draft, owner merge) | Requires owner squash gate; soul amendment slower than script change | ✅ CHOSEN — file ownership matrix correctness |
| B. CI gate / script enforcement | Automated; faster detection | Out of scope (doctrine-only this sprint); future candidate | ❌ deferred |
| C. Tester lane AC verification | Testers already verify AC traceability | Tester lane AC verification out of scope; separate doctrine candidate | ❌ out of scope |
| D. Backfill historical ADR drift | Catches existing drift | Out of scope (forward-looking only); historical ADRs are exempt | ❌ out of scope |

## Cross-references

### Doctrinal anchors

- **ADR-0012** — 4-cat label invariant (AC list comparison = 4-cat invariant applied to spec level)
- **ADR-0015** — atomic 4-flag handoff (doctrine protocol exit codes 0/1/2/3 = handoff states)
- **ADR-0044** — RED-first TDD (tester sign-off lane)
- **ADR-0045** — 9-Lens pre-publish gate (lens a data flow augmented with AC mapping verification)
- **ADR-0048** — type-driven verdict gate matrix (type:docs = arch lane-monitoring informational)
- **ADR-0049** — d-test framework (future CI gate sister-pattern)
- **ADR-0055** — Cadence Rule 1 atomic (ADR + design doc + INDEX.md in same PR)
- **ADR-0059** — cluster-squash batch-lag detection (sister-pattern: arch design + ADR + INDEX atomic)

### Upstream P1 cluster precedents (generalized)

- **Sister-PR (ADR-0059 + STORY-P1-1 design + INDEX atomic)** — MERGED, sister-pattern: ADR + design + INDEX atomic
- **Sister-PR (STORY-P1-1 cluster-lag-detector.sh impl)** — AC drift LIVE INSTANCE
- **Sister-PR (RETRO-012 ProcessGap retro + post-squash cleanup)** — origin for §1 arch AC drift codification candidate
- **Multi-lane consensus disposition comment** — 5-of-5 lane consensus on AC4 rescope (drift disposition)
- **Tester doctrinal clear comment** — tester catching AC drift during impl phase (lacks codified doctrine for arch-side prevention)
- **Arch FINAL 🟢 verdicts on cluster impl + retro PRs** — sister-pattern verdicts (post-disposition)
- **PM sponsor commitment comment** — cross-lane codification sponsor signal

### Sister-pattern cross-lane triggers

- **Cross-lane "verify-before" triangle**: PM-side §Pre-citation cross-check + PM-side §Timing window + Arch-side §AC mapping verification (this ADR)
- **Orch-side §Verdict-by Discipline** — codifies orch-side expectation-setting (verdict-by:<ts> + cc:<role>)

— @architect, 2026-07-19, ADR-0061 §AC mapping verification doctrine codification, canonical home for cross-lane "verify-before" triangle (PM-side ratified + Arch-side codification in flight), sister-pattern to ADR-0059 + RETRO-012 + verdict-by Discipline codification, multi-lane consensus principle preserved (drift disposition pattern)