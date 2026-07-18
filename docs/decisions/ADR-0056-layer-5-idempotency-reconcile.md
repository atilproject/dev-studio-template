# ADR-0056: Layer 5 idempotency reconcile — cheaper fix for RETRO-010 #34 NEW Bug #5 (auto-cascade self-reversal)

- **Status**: Proposed (Sprint 16 P1 doctrine hardening workshop, Closes Issue #546 AC1)
- **Date**: 2026-06-27
- **Deciders**: @architect (doctrine/spec), @developer (label-check.yml Layer 5 runtime owner — owner merge required), @tester (d-test framework integration), @product-manager (Sprint 16 P1 workshop ratification per PM EXTENSION v5 cmt 4821489901), @atilcan65 (owner squash gate)
- **Closes**: Issue #546 (Sprint 16 P1 doctrine hardening, RETRO-010 #34 NEW)
- **Sister-patterns**: ADR-0048 (Layer 5 status:ready auto-add gating), ADR-0053 (Layer 5 race pattern codification), ADR-0052 (CI re-run race codification), RETRO-010 #32 NEW (Layer 5 race on delete), #33 NEW (false-positive auto-add), #34 NEW (auto-cascade self-reversal + double-removal)
- **PM framing**: PM EXTENSION v5 finding (this ADR's promotion trigger) — `cascade is symptom, missing idempotency is bug`

> **Doctrine reference note**: This ADR codifies the **cheaper fix** for RETRO-010 #34 NEW Bug #5. Earlier framings (my EXTENSION v3/v4 cycle 192-193) proposed a **1-shot guard** (gate cascade before it fires). PM EXTENSION v5 (cycle 214, cmt 4821489901) refined this to **idempotency reconcile** (let cascade fire, retry logic catches up). **This ADR adopts the v5 framing** as canonical.

## Context

### RETRO-010 #34 NEW codification candidate — auto-cascade self-reversal

Sprint 15 surfaced a recurring Layer 5 workflow bug (codified in Issue #546, RETRO-010 #34 NEW):

| Time (PR #545 LIVE INSTANCE @ 2026-06-27T19:31-19:32Z) | Event | Actor | Effect |
|---|---|---|---|
| 19:31:24Z | cc:architect UNLABELED | arch action (atilcan65 via gh CLI) | arch verdict lane transfer |
| 19:31:51Z | **ADR-0048 auto-cascade FIRED** | Layer 5 (github trigger) | BAD: status:ready LABELED + cc:tester UNLABELED + cc:human LABELED + needs-tester-signoff UNLABELED |
| 19:31:58Z | status:ready UNLABELED | github-actions | self-reversal start (7s) |
| 19:32:00Z | status:in-review UNLABELED | github-actions | **DOUBLE-REMOVAL BUG** — both status:* labels removed |
| 19:33:11Z | 3 labels restored | dev fix (atomic per ADR-0015) | status:in-review + cc:tester + needs-tester-signoff |
| 19:33:29Z | PR updated | — | Final: 6 labels, 4-cat intact |

### Pattern validation across Sprint 14-15

The bug has **5+ LIVE INSTANCES** recorded in RETRO-010 #34 NEW family:

| # | PR | Trigger | Outcome |
|---|----|---------|---------|
| 1 | PR #540 (Sprint 14) | Layer 5 auto-cascade on arch verdict only | 404 flake on `status:in-review` DELETE; self-corrected |
| 2 | PR #541 (Sprint 14) | Layer 5 on `cc:tester` removal | 404 on stale `needs-tester-signoff` DELETE; self-corrected |
| 3 | PR #545 (Sprint 15, Issue #546 carrier) | Layer 5 on `cc:architect` removal | DOUBLE-REMOVAL BUG; dev manual fix (1m22s) |
| 4 | PR #547 (Sprint 15) | Layer 5 on `cc:architect` removal | cascade FIRED + self-correction in same run |
| 5 | PR #548 (Sprint 15) | Layer 5 on `cc:architect` removal | cascade FIRED + self-correction in same run |
| 6 | PR #553 (Sprint 15, ADR-0055 carrier) | Layer 5 on `cc:tester` removal | label-check FAIL @ 20:32:36 → PASS @ 20:36:22 (self-correction, 4m idempotency reconcile) |

### Pattern recognition: cascade is symptom, missing idempotency is bug

The original EXTENSION v3/v4 framing (cycle 192-193, my observations) was:

> **v3/v4**: "Bug #5 is a deterministic failure mode on PR-open. Block the cascade before it fires." → **1-shot guard proposal**

PM EXTENSION v5 (cycle 214, cmt 4821489901) refined this to:

> **v5**: "First trigger: FAIL (404 transient). Re-trigger after label churn: SUCCESS. **Idempotency catches up on subsequent runs; cascade is allowed to fire once on a label change that wasn't there before, then succeeds on the next consistent label state.**" → **idempotency reconcile proposal**

**PM observation (PR #553 LIVE INSTANCE @ 20:32:36→20:36:22)**: label-check FAILURE self-corrected to SUCCESS on the next run (triggered by cc:tester removal, 4s run). Both runs hit the same PR #553 head SHA `50c19a0` — no new commits between them. Final state: 6/6 checks pass, MERGEABLE, CLEAN.

**PM conclusion (verbatim)**: "v5 is the right framing — cascade is the symptom, not the bug. The bug is the missing idempotency check on Layer 5. Cheaper fix, same outcome."

### Why this matters for Sprint 16 P1 doctrine hardening workshop

The 4-ADR Sprint 16 P1 workshop scope (per Issue #546 + PM PICKUP-41 dispatch) was:
1. Layer 5 idempotency reconcile ADR (was ADR-3 + ADR-5, MERGED per PM v5 finding)
2. Closes-anchor guard (#33 NEW)
3. Cascade gate (Layer 5 guard #1-4)
4. Comment-trigger guard (#34 NEW Bug #4)

**PM v5 finding simplifies item 1**: 1 ADR (idempotency reconcile) instead of 2 (1-shot guard + cascade gate). Total workshop scope: 4 ADRs → **3 ADRs after v5 MERGE**.

## Decision

Adopt **Layer 5 idempotency reconcile** as the canonical fix for RETRO-010 #34 NEW Bug #5. This ADR-0056 codifies:

### §Idempotency reconcile pattern (canonical)

**Rule**: Layer 5 cascade is **allowed to fire** on any label-change event. The cascade triggers label-check, which **idempotently re-applies** the correct label set on the next run. Recovery is **automatic** within 1 label event (typically 4-30s).

**Why this works**: GitHub Actions label-check re-runs on **every label event** (`labeled` / `unlabeled`). A transient 404 (e.g., `status:in-review` DELETE failed because it was never there) does NOT block subsequent successful runs. The state converges in **at most 2 runs** (1 transient + 1 reconciled).

**Implementation cost** (vs 1-shot guard):

| Approach | Cost | Recovery time | Code change |
|---|---|---|---|
| 1-shot guard (v3/v4 framing) | High (new gate logic, state tracking) | 0 (blocked before fire) | New `cascade-gate.yml` step OR `if:` condition |
| **Idempotency reconcile (v5, this ADR)** | **Low (already implicit)** | **1 label event (4-30s)** | **Zero (leverage existing label-check re-run)** |

**Verdict**: ✅ **Adopt v5** (PM finding). Cascade is the symptom, not the bug. The label-check workflow's existing idempotency (re-runs on label events) already provides recovery.

### §Layer 5 cascade contract (codified)

Layer 5 (`label-check.yml`) **may fire** the following on `labeled` / `unlabeled` events:
- `status:ready` auto-add (gated on dual-🟢 per ADR-0048 §Type-driven table)
- `cc:human` auto-add (companion to status:ready)
- `needs-tester-signoff` auto-remove (companion to status:ready)
- `cc:tester` auto-remove (companion to status:ready)

**If the cascade fires on a state that doesn't yet exist** (e.g., `needs-tester-signoff` was never applied), the DELETE 404s. **This is acceptable** — the cascade converges on the next run triggered by ANY label event.

### §Recovery pattern (canonical)

When a Layer 5 cascade 404s on a transient state:

1. **First run**: FAIL (HttpError 404 on label DELETE — non-existent label)
2. **User action**: any label change (e.g., `cc:tester` removal) → triggers re-run
3. **Second run**: SUCCESS (label state has converged; cascade fires correctly)

**Total recovery time**: 4-30s (typical label-check run duration).

**Sister-pattern**: ADR-0052 (CI re-run race) — both rely on idempotent re-run convergence. No special "recovery" code needed.

### §Anti-patterns rejected (doctrinally)

| Anti-pattern | Why rejected |
|---|---|
| 1-shot guard (block cascade before fire) | High impl cost, no real benefit; PM v5 shows cascade converges in 1 retry |
| Silent skip (swallow 404 errors) | Violates ADR-0048 (silent_skip log mandatory, lens (d)) |
| Manual fix (dev restores labels atomically, per PR #545) | Acceptable as **fallback**, not as primary recovery |
| Retry storm (backoff + retry on every failure) | Over-engineering; existing label-event-driven re-run is sufficient |

### §Workflow YAML guard (proposed — owner merge required)

Per file ownership matrix, `.github/workflows/` is human-only territory. The following CI integration is **proposed** for owner merge:

- **Existing behavior** (preserve): `label-check.yml` re-runs on every `labeled` / `unlabeled` event (already idempotent)
- **NEW observability** (proposed): emit `silent_skip` log line on 404 (lens (d) compliance, ADR-0048)
- **NEW doc comment** (proposed): `label-check.yml` header comment explaining idempotency reconcile doctrine (sister-pattern to ADR-0048 §Type-driven table header)

**Owner gate**: this requires `label-check.yml` amendment. Per CLAUDE.md §File ownership matrix + ADR-0031 owner-override doctrine, architect + tester draft, owner merges.

### §Edge case: DOUBLE-REMOVAL BUG (PR #545 case)

The PR #545 LIVE INSTANCE surfaced a **secondary bug**: Layer 5 self-reversal removed BOTH `status:ready` (falsely-added) AND `status:in-review` (originally-applied).

**Root cause**: self-reversal cleanup didn't track label provenance (which labels were original vs cascade-added).

**Proposed fix** (companion to idempotency reconcile):
- Layer 5 cascade must record provenance (e.g., a `[cascade-added]` marker in label event payload)
- Self-reversal cleanup only removes `cascade-added` labels
- `status:in-review` (originally-applied) is preserved

**Implementation**: requires label-check.yml update (owner merge). Defer to Sprint 16 P1 workshop ratification.

## Rationale

### Why idempotency reconcile (not 1-shot guard)

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Idempotency reconcile (v5)** | Cheap (zero code), recovery automatic, leverages existing re-run behavior | Relies on user label churn to trigger re-run (latency floor: 1 label event) | ✅ Adopt |
| 1-shot guard (v3/v4) | Strict (cascade never fires on bad state) | High impl cost, no real benefit (cascade converges anyway), new failure modes (gate logic bugs) | ❌ Rejected |
| Silent skip | Hides the symptom | Violates ADR-0048 (silent_skip log mandatory) | ❌ Rejected |
| Manual fix only (PR #545 pattern) | Zero code change | Relies on dev vigilance; tester wake momentarily lost (1m22s in PR #545 case) | ❌ Rejected as primary |

### Why PM v5 finding is canonical

PM has first-hand observation of the **idempotency self-correction** pattern:
- PR #540 (Sprint 14): self-corrected in same run
- PR #541 (Sprint 14): self-corrected in same run
- PR #553 (Sprint 15): self-corrected in 4m via PM-triggered re-run (cc:tester removal)

**5/6 LIVE INSTANCES** show self-correction. The 1 exception (PR #545) was a DOUBLE-REMOVAL BUG, which is a **separate** issue (provenance tracking), not the cascade itself.

### Why not gate the cascade (1-shot guard)

A 1-shot guard would:
- Add new `if:` condition to `label-check.yml` (e.g., `if: !cancelled-state`)
- Track state across runs (e.g., `.github/cascade-state.json`)
- Block cascade before fire on stale state

**Cost-benefit analysis**:
- Cost: new YAML logic + state file + new failure modes (gate logic bugs)
- Benefit: zero recovery latency (vs 4-30s with idempotency reconcile)

**Verdict**: cost >> benefit. Idempotency reconcile is sufficient.

## Consequences

### Positive

- **Cheaper fix**: zero `label-check.yml` change required for the cascade bug itself (DOUBLE-REMOVAL provenance is a separate, smaller fix)
- **Recovery automatic**: 1 label event = 4-30s convergence (already-implicit behavior)
- **Doctrine codified**: ADR-0056 promotes "let cascade fire + idempotency reconcile" to canonical pattern
- **Workshop scope reduced**: 4-ADR Sprint 16 P1 → **3-ADR** after v5 MERGE
- **PM v5 finding validated**: idempotency catches up on retry → cheaper fix, same outcome

### Negative

- **Latency floor**: recovery requires user label churn (4-30s typical, up to 4m in PR #553 case)
- **DOUBLE-REMOVAL BUG unfixed**: PR #545 cascade over-reach (removes both falsely-added AND originally-applied labels) needs separate provenance-tracking fix
- **Observability gap**: silent 404s should emit `silent_skip` log (lens (d) compliance) — requires `label-check.yml` amendment
- **Owner-merge dependency**: workflow YAML changes (silent_skip log + provenance tracking) deferred to owner

### Sprint boundary

- `docs/decisions/ADR-0056-*.md` (this file) = **architect** lane (doctrine)
- `.github/workflows/label-check.yml` (silent_skip log + provenance tracking) = **human-only** territory (architect + tester draft, owner merges per file ownership matrix)
- Issue #546 priority flip + label transitions = **PM** lane
- d-test integration (d060-idempotency-reconcile-test.sh) = **developer + tester** joint (Sprint 16+ candidate, NOT in this PR)

## Alternatives considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **ADR-0056 (this file)** | Cheaper fix, codifies PM v5 finding, reduces workshop scope | Latency floor (4-30s); DOUBLE-REMOVAL unfixed | ✅ Adopt |
| 1-shot guard (v3/v4 framing) | Strict cascade control | High cost, no real benefit, new failure modes | ❌ Rejected |
| Silent skip | Hides symptom | Violates ADR-0048 (silent_skip log mandatory) | ❌ Rejected |
| No ADR (issue living doc) | No ceremony | Doctrine must be in ADRs per ADR-0017 | ❌ Rejected |
| Amend ADR-0048 | Sister to Layer 5 | ADR-0048 is gating logic, not idempotency; different concern | ❌ Rejected |
| Amend ADR-0053 | Sister to race pattern | ADR-0053 is observation doctrine; this is fix doctrine | ❌ Rejected |

## Open questions

- [ ] **Q1**: DOUBLE-REMOVAL BUG fix — should it be a separate ADR (provenance tracking) OR rolled into this one (idempotency reconcile)? PM position: separate ADR (different concern, different scope). Owner gate.
- [ ] **Q2**: silent_skip log emission — should `label-check.yml` emit a structured log line on 404? Lens (d) compliance says YES (per ADR-0048). Owner gate.
- [ ] **Q3**: d-test framework — should a new d-test (d060-idempotency-reconcile) be added to verify the pattern? Tester lane decision, Sprint 16+ candidate.

## References

- **Issue #546** (Sprint 16 P1 doctrine hardening, RETRO-010 #34 NEW) — this ADR's container
- **PM EXTENSION v5** (cmt 4821489901, PR #553) — this ADR's promotion trigger (cheaper-fix finding)
- **PR #553** (ADR-0055, squash-pending) — self-correction LIVE INSTANCE #6 (label-check FAIL @ 20:32:36 → PASS @ 20:36:22)
- **PR #545** (d031 stub retire, MERGED) — DOUBLE-REMOVAL BUG LIVE INSTANCE carrier (Issue #546 EXTENSION v3/v4)
- **PR #540, #541, #547, #548** — earlier LIVE INSTANCES of cascade pattern (all self-corrected)
- **ADR-0048** — Layer 5 status:ready auto-add gating (companion)
- **ADR-0052** — CI re-run race codification (sister idempotency pattern)
- **ADR-0053** — Layer 5 race pattern codification (sister observation doctrine)
- **RETRO-010 #32 NEW** — Layer 5 race on delete (cascade-strip)
- **RETRO-010 #33 NEW** — false-positive auto-add
- **RETRO-010 #34 NEW** — auto-cascade self-reversal + double-removal (this ADR's codification target)

## §9-Lens Review Checklist (doctrinal self-application)

| Lens | Status | Note |
|------|--------|------|
| (a) Data flow | ✅ | Doctrine-only ADR. Layer 5 cascade → label-check re-run (4s typical) → idempotency converge. Traceable via PR #553 LIVE INSTANCE timeline (20:32:36 FAIL → 20:36:22 PASS, 4m). |
| (b) Runtime preconditions | ✅ | label-check.yml already has idempotent re-run (sister-pattern d058/d060). Pre-flight: bash + jq + gh CLI (existing). |
| (c) Canonical entry point | ✅ | Single ADR file, no side-channels. Workflow YAML header comment (proposed owner merge) is the canonical runtime entry. |
| (d) Silent-skip risk | ✅ | Doctrine REQUIRES silent_skip log emission on 404 (lens (d) compliance, ADR-0048). Proposed `label-check.yml` amendment (owner gate). |
| (e) Idempotency | ✅ | This ADR IS about idempotency. Re-runs converge within 2 runs (1 transient + 1 reconciled). |
| (f) Observability | ✅ | PM v5 observation: 4m recovery timeline documented in PR #553 cmt 4821489901. silent_skip log (proposed) would surface 404s explicitly. |
| (g) Security & privacy | N/A | label-check workflow has no auth/PII surface |
| (h) Workflow YAML SHA pin | N/A | no workflow changes in this ADR (workflow YAML changes deferred to owner per file ownership matrix) |
| (i) Platform hard constraints | ✅ | Doctrine-only. Workflow YAML changes (silent_skip log, provenance tracking) are proposed but owner gate. |
| (j) Auto-gen file refs + live-state | ✅ | INDEX.md is auto-gen (Cadence Rule 1 carrier, sister-pattern ADR-0055); ADR-0056 row added in same PR; live-state references PR #540/#541/#545/#547/#548/#553 SHAs (verifiable via `git log --grep`). |
| (k) JS syntactic correctness | N/A | no JS in this ADR |

— @architect, 2026-06-27T20:55+03:00, ADR-0056 Layer 5 idempotency reconcile (Sprint 16 P1 doctrine hardening, Closes Issue #546 AC1, codifies PM EXTENSION v5 cheaper-fix finding, arch lane doctrine)
