# ADR-0071 — Open-Time Label-Strip Diagnostic for `label-check.yml`

**Status:** Proposed
**Date:** 2026-07-09
**Deciders:** @architect (doctrine/spec + impl proposer), @developer (impl reviewer per file ownership), @tester (d067c-open-time-label-strip.sh ≥5 TCs RED-first per ADR-0044), @orchestrator (sprint tracking per Issue #941 Sprint 26 Kickoff), @atilcan65 (workflow YAML owner squash-gate per ADR-0031 + file ownership matrix)
**Closes:** Issue #931 (TD-067c open-time sister-finding, P1, Sprint 26 candidate). Refs Issue #941 (Sprint 26 Kickoff umbrella), Issue #939 (Sprint 25+ Wave 1 deferral source — pre-staged artifacts preserved)
**Supersedes:** —
**Related:** [ADR-0070](./ADR-0070-closed-diagnostic.md) (TD-067b closed-event diagnostic — sister-pattern, this ADR is the open-time axis extension), [ADR-0012](./ADR-0012-required-label-set.md) (4-cat invariant being protected), [ADR-0015](./ADR-0015-atomic-agent-handoff.md), [ADR-0027](./ADR-0027-deploy-automation.md) §Threat model (SHA-pin), [ADR-0043 §lens (h)](./ADR-0043-8-lens-architect-review-checklist.md), [ADR-0044](./ADR-0044-verdict-by-scope-clarification.md) (RED-first TDD, tester), [ADR-0045](./ADR-0045-auto-generated-file-refs-design-verification.md) (9-Lens pre-publish, all 10 attested in design doc §9-Lens checklist), [ADR-0049](./ADR-0049-behavioral-workflow-test-framework.md) (d-test framework ≥5 TCs baseline), [ADR-0055](./ADR-0055-d-test-id-uniqueness-sub-pattern-matrix.md) (d-test ID uniqueness + Cadence Rule 1), [ADR-0057](./ADR-0057-amendment-closes-vs-refs-intent.md) (Closes vs Refs intent rule, Amendment #1 — post-Issue #877 Phase 2 v1.0.0 audit ratification 2026-07-07). Canonical design contract: `docs/designs/TD-067c-open-time-design.md` (this PR).

---

## Context

**TD-067b** (PR #938 squash @ 4975c22f, 2026-07-09T15:50:52Z, sister ADR-0070) adds a **closed-event** diagnostic to `label-check.yml` — a Layer 6 step that fires on `pull_request_target: closed` with `merged == true`, reads the post-cleanup label state, and posts a comment if the expected post-cleanup baseline is violated. **It does NOT catch open-time label-strip** — strips that occur while the PR is still OPEN.

**The problem this ADR solves**: the open-time strip class is a **real regression** with **4 known instances** (per Issue #931 §Evidence stack + orchestrator cmt 4925168092):

| # | Instance | Time | Strip pattern |
|---|---|---|---|
| 1 | Issue #927 | 2026-07-09T11:35Z | `agent:architect` + 4 `cc:*` stripped during PR #926 merge window |
| 2 | PR #928 | 2026-07-09T11:51:20Z | `cc:product-manager` stripped during OPEN review window |
| 3 | PR #933 | 2026-07-09T12:40:53Z | `cc:product-manager` + `cc:tester` stripped between 12:32Z and 12:40:53Z |
| 4 | Unstaged | unknown | Other instances may exist in label event log on PRs |

**Architectural hypothesis** (NOT root-cause-confirmed, per Issue #931 §Architectural hypothesis): possible causes include (a) `status-label-to-board.yml` mirror race (ADR-0013), (b) `peer-poke.sh` label-add path incorrect sequence, (c) GitHub-native label event propagation delay creating observer misreads. This ADR does NOT confirm root cause — it provides **forward-action observability** regardless of root cause, sister-pattern to TD-067b.

**Deferral context**: Issue #939 (Sprint 25+ Wave 1 kickoff) was closed as `not_planned` at 2026-07-09T16:00:27Z because owner directed template v1.0.1 workstream priority. Pre-staged artifacts (3 design clarifications + 3 non-blocking suggestions from arch review cmt 4927052273) preserved verbatim for Sprint 26 re-trigger. **Re-trigger conditions** ALL RESOLVED:

1. ✅ Template v1.0.1 Grup C re-render (PR #942 squash-merged, version bump)
2. ✅ Owner release v1.0.1 published 2026-07-09T16:26:58Z
3. ✅ Sprint 26 Kickoff issue #941 opened 2026-07-09T16:15:50Z, `agent:architect` flipped to `status:ready` on Issue #931

**LIVE EVIDENCE** (orchestrator cmt 4925168092 on Issue #931): "PR #933 — `cc:product-manager` + `cc:tester` stripped between 12:32Z (orchestrator add) and 12:40:53Z (re-query). Sister-pattern implication: This is EXACTLY the regression class TD-067c is meant to detect. The TD-067b closed-event diagnostic will NOT catch this because PR #933 is still OPEN."

---

## Decision

**Adopt Layer 7 — `TD-067c open-time label-strip diagnostic`** as a new step in `.github/workflows/label-check.yml`.

### File changes

- `.github/workflows/label-check.yml` — NEW `on:` block:
  ```yaml
  on:
    pull_request:
      types: [opened, reopened, labeled, unlabeled, synchronize]
    issues:
      types: [opened, reopened, labeled, unlabeled]
  ```
  (Add to existing workflow's triggers; do NOT modify existing `pull_request_target:` block for Layer 6.)
- `.github/workflows/label-check.yml` — NEW Layer 7 step block (`open-diagnostic` step) — sister-pattern to existing Layer 6 closed-event step.

### Step semantics

- **Trigger**: step-level `if:` gate — `if: github.event_name == 'pull_request' || github.event_name == 'issues'` AND action ∈ allowed list AND synchronize-invariance gate (see below).
- **Fresh label fetch**: `github.rest.pulls.get` (PR events) or `github.rest.issues.get` (Issue events) — Issue #819 fix sister-pattern (webhook snapshot can be 1-30s stale).
- **Actor check** (sister to TD-067b's "skip if owner" precedent per suggestion S1 from arch review cmt 4927052273):
  - `github.actor == 'atilcan65' || github.actor == 'github-actions[bot]'` → ℹ️ info-level log, NO comment (distinguishes hostile strip from intentional maintainer reset).
  - All other actors → 4-cat invariant check.
- **4-cat baseline comparison** (per design doc §Data model, condensed into JS):
  - REQUIRED: `type:*` (exactly 1, from `vision|feature|bug|docs|chore|refactor|incident`) + `status:<not done>` (exactly 1) + `agent:*` (exactly 1) + `cc:*` (≥1)
  - Breaking: missing `type:*` OR missing `status:*` (AND not `done`) OR missing `agent:*` OR zero `cc:*`
- **`synchronize` no-op diff gate** (per design R2 mitigation):
  - Compute label diff between pre-event and post-event snapshot
  - IFF diff preserves 4-cat invariant → silent_skip log, no comment
  - IFF diff breaks 4-cat invariant → diagnostic comment fires
- **Concurrency group parameterization** (per arch review cmt 4927052273 clarification #1 + cmt 4927243051 clarification #1):
  ```yaml
  concurrency:
    group: label-check-${{ github.event.pull_request.number || github.event.issue.number }}
    cancel-in-progress: false
  ```
  Sister-pattern with TD-067b's existing `label-check-${{...number}}` group, but parameterized for PR + Issue surfaces (Issue events don't have `pull_request.number`, they have `issue.number`).
- **3 structured log paths** (ADR-0045 lens d compliance):
  - `event=triggered` — every invocation
  - `event=baseline-match` — silent_skip per ADR-0045 lens d (no comment)
  - `event=deviation-detected` — `core.warning` + bot comment posted, includes `missing_labels[]`
  - `event=maintainer-actor` — ℹ️ info-level log, no comment
- **Bot comment idempotency**: marker `<!-- adr-0071-open-diagnostic -->` (sister to TD-067b's `<!-- adr-0070-closed-diagnostic -->`), reuses L108-110 dedup pattern.
- **SHA-pinned**: `actions/github-script@f28e40c7f34bde8b3046d885e986cb6290c5673b` (matches existing Layer 1-6 usage at L54, 178, 243, 334, 455, TD-067b Layer 6 884).
- **Permissions inherit** from workflow-level block (L37-39: `issues: write`, `pull-requests: write`).

### Implementation surface

- **Single workflow file**: `.github/workflows/label-check.yml` — adds Layer 7 (~150-200 LoC YAML delta, sister to TD-067b's ~130 LoC delta).
- **Single d-test file**: `scripts/tests/d067c-open-time-label-strip.sh` (NEW) with ≥5 TCs per ADR-0049.
- **Mock event generator**: `scripts/tests/d067c-mock-event-generator.sh` (NEW) sister-pattern to existing d-test fixtures — synthetic `pull_request: opened|labeled|unlabeled` payloads mirroring GitHub's webhook schema.
- **INDEX update**: `scripts/tests/INDEX.md` (Cadence Rule 1 atomic per ADR-0055).
- **ADR**: `docs/decisions/ADR-0071-td-067c-open-diagnostic.md` (this file).
- **Design doc**: `docs/designs/TD-067c-open-time-design.md` (this PR's primary deliverable).
- **tech-debt update**: `docs/tech-debt.md` TD-067c row (Sprint 25+ → Sprint 26, 4th evidence instance, re-trigger conditions).

### Sister-pattern consolidation (suggestion S3 from arch review cmt 4927243051)

TD-067b's Layer 6 + TD-067c's Layer 7 ship in the **SAME IMPL PR** for architectural consolidation:

- Single workflow file edit (Layer 6 already merged, Layer 7 added in same PR)
- Concurrency group unified from TD-067b's existing form to parameterized form (per clarification #1)
- Both layers share primitives (bot comment dedup, fresh-label fetch, structured silent_skip log)
- Test framework unified (d068-td067-combined.sh 7 TCs + d067c-open-time-label-strip.sh ≥5 TCs = combined 12+ TCs)
- Architecture doc (this ADR) covers both axes (closed-time + open-time observability)

---

## Rationale

### Why Layer 7 (workflow file addition) vs alternatives

| Alternative | Verdict |
|---|---|
| **A. Layer 7 in `label-check.yml`** (this ADR) | ✅ **CHOSEN**: single workflow, sister-pattern with TD-067b, concurrency-group unification, reuses existing primitives |
| B. Separate `label-check-open-diagnostic.yml` workflow | ❌: DRY violation, pattern drift risk, 2 workflows to maintain |
| C. GitHub-native label event observability | ❌: archival delays (Issue #931 §hypothesis c), higher ops complexity, doesn't fit existing pattern |
| D. Root-cause fix on `peer-poke.sh` / `status-label-to-board.yml` | ❌ for Sprint 26: requires root-cause confirmation first (architectural hypothesis a/b/c unconfirmed); separate investigation track if confirmed |

### Why parameterized concurrency group

TD-067b uses `concurrency-group: label-check-${{ github.event.pull_request.number }}`. Issue events don't have `pull_request.number` (they have `issue.number`). The parameterized form `${{ github.event.pull_request.number || github.event.issue.number }}` ensures:
- **Same concurrency group key shape** across PR + Issue surfaces (sister-pattern alignment)
- **No race** between PR diagnostic and Issue diagnostic on same logical entity
- **Drop-in compatible** with TD-067b's existing concurrency group (one variable name changed, no other modification)

### Why mock event generator for d-test replay

Per arch review cmt 4927243051 clarification #2 (re-bound from #939): **STORY-S25-002 (Sprint 25+ carryover)**'s AC3 replay of 4 known instances should use a **mock event generator** (shell fixture firing synthetic `pull_request: opened|labeled|unlabeled` sequences), NOT historical `gh api /repos/.../issues/<N>/events`. Rationale:
- **Faster** (no API call latency)
- **More reliable** (no archival delay dependency per Issue #931 §hypothesis c)
- **Sister-pattern** with `d058-label-check.sh` precedent
- **Testable in CI** without external state
- **Avoids GitHub-native event propagation delay observer misreads** (the very failure mode the diagnostic catches)

### Why `synchronize` no-op diff gate

`synchronize` (push) events fire frequently during PR development (every commit push). Without a gate, the diagnostic would fire alerts on every push that touched labels — most of which are legitimate (e.g., maintainer adding a `priority:` label during sprint planning). The gate:
- Computes label diff between pre-event and post-event snapshot
- ONLY alerts if the diff BREAKS the 4-cat invariant
- Sister-pattern of TD-067b's `merged == true` gate (which only fires on close, never on push)

### Why maintainer info-downgrade

Real-world pattern: owner `atilcan65` and GitHub Actions bot `github-actions[bot]` are common actors for legitimate label changes (sprint planning, board sync, retrospective cleanups). Treating them as hostile strips would create alert noise. The actor check downgrades to ℹ️ info-level log, retaining observability without spam.

### Why same PR for both Layer 6 retrofit + Layer 7

Sister-pattern alignment + concurrency-group unification (R1 mitigation) is significantly cleaner in a single PR:
- TD-067b's existing `concurrency-group: label-check-${{ github.event.pull_request.number }}` becomes `label-check-${{ github.event.pull_request.number || github.event.issue.number }}` — one-line YAML change
- TD-067b's Layer 6 step gets `<!-- adr-0070-closed-diagnostic -->` (unchanged) + Layer 7 gets `<!-- adr-0071-open-diagnostic -->` (new)
- TD-067b's d-test `d068-td067-combined.sh` (7 TCs) STAYS GREEN as regression guard (R6 mitigation)
- TD-067c's d-test `d067c-open-time-label-strip.sh` (≥5 TCs) lands alongside

---

## Consequences

### Positive outcomes

- ✅ **Open-time label-strip observability** — forward-action diagnostic catches regression class that TD-067b's closed-event cannot
- ✅ **Sister-pattern alignment** — TD-067b + TD-067c share primitives, concurrency group, d-test framework
- ✅ **Sprint 26 closure** — completes the TD-067 cluster (TD-067 + TD-067b + TD-067c)
- ✅ **4 evidence instances mitigated** — future instances fire diagnostic comment within 30s, restoration becomes observable
- ✅ **Re-trigger conditions RESOLVED** — Sprint 26 scope activated per arch cmt 4927095731 + Issue #941
- ✅ **Pre-staged artifacts preserved** — 3 clarifications + 3 suggestions from arch review cmt 4927052273 + 4927243051 carried verbatim

### Negative tradeoffs

- ⚠️ **Workflow file scope** — adds ~150-200 LoC YAML to 858+ line workflow file; R6 mitigation via surgical modification + TD-067b d-test regression guard
- ⚠️ **Owner squash gate** — `.github/workflows/` is human-only territory (file ownership matrix); requires owner squash per ADR-0031
- ⚠️ **Issue event surface** — Issue events have a different concurrency group key shape; R1 mitigated by parameterized form
- ⚠️ **`synchronize` false-positive risk** — R2 mitigated by no-op diff gate; d-test TC4 must verify
- ⚠️ **Dependency on d068 + d067c d-tests both GREEN** — combined test surface 12+ TCs; R6 mitigation via d068 d-test regression guard
- ⚠️ **Phantom cmt cross-ref** — Issue #941 body + orch cmt 4927121862 reference non-existent cmt 4927190526 instead of 4927095731 (R7 mitigation via arch review per Issue #430 + Issue #682)

### Follow-up tickets to file

- [ ] **FU-1**: **S25-001 (impl PR, Sprint 25+ carryover)** MUST include d068-td067-combined.sh 7 TCs as regression guard — verify in d-test step output
- [ ] **FU-2**: **STORY-S25-002 (Sprint 25+ carryover)** d-test (tester authored, RED-first per ADR-0044) MUST land before **S25-001 impl** (sister-pattern to S25-002 → S25-001 sequence)
- [ ] **FU-3**: After PR merges, file separate `sister-fix-td-067b-parameterized-concurrency` PR if same-PR sister-fix isn't possible (reversibility fallback)
- [ ] **FU-4**: Future Sprint 27+ investigation track: root-cause confirmation for the strip mechanism (architectural hypothesis a/b/c still unconfirmed). Out of scope for this ADR.

---

## 9-Lens pre-publish checklist (per ADR-0045, all 10 attested in design doc §9-Lens checklist)

- **(a) Data flow** — ✅ OK, traced in design doc §High-level diagram
- **(b) Runtime preconditions** — ✅ OK, self-hosted runner + GITHUB_TOKEN + PROJECT_TOKEN (existing, no new secrets)
- **(c) Canonical entry point** — ✅ OK, step-level `if:` gate is the ONLY entry; no side-channels
- **(d) Silent-skip risk** — ✅ OK, structured silent_skip log path per ADR-0045 lens d (R2 mitigation)
- **(e) Idempotency** — ✅ OK, marker-based bot comment dedup; concurrency group parameterized; no state mutation
- **(f) Observability** — ✅ OK, 4 structured log paths (triggered, baseline-match, deviation-detected, maintainer-actor) + 3 metric counters + 4 trace spans
- **(g) Security & privacy** — ✅ OK, no PII; SHA-pinned actions; workflow token surface unchanged; per ADR-0027 §Threat model
- **(h) SHA-pin** — ✅ OK, `actions/github-script@f28e40c7f34bde8b3046d885e986cb6290c5673b` (same as TD-067b Layer 6 + existing Layer 1-5 usage)
- **(i) Platform hard constraints** — ✅ OK, 8 sub-categories per ADR-0043 — `path:`, `runs-on`, `permissions`, `timeout`, `concurrency`, `if:`, `secrets`, platform sandbox (no raw `docker run` / `ssh` outside `actions/*` ecosystem)
- **(j) Auto-generated file refs + live-state verification** — OK per ADR-0045 lens j; label-check.yml is hand-maintained (verified via `git log --follow`), no auto-gen refs to enumerate

---

*Adopted as Project doctrine at 2026-07-09T16:30Z (Sprint 26 Kickoff cycle ~#5094). Sister-pattern to ADR-0070 (closed-event axis). Implementation contract: `docs/designs/TD-067c-open-time-design.md`. Doctrinal home: Issue #931 (TD-067c P1, Sprint 26 candidate, status:ready as of 2026-07-09T16:28:04Z).*