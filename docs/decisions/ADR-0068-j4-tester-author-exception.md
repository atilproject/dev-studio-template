# ADR-0068 — Layer 5 j.4 Tester-Author Exception Clause (False-Positive Vacuous-Pass Detection)

- **Status:** Proposed (Sprint 24+ P2 doctrine hardening, Closes Issue #798 doctrinal follow-up + PR #799 vacuous-pass GAP)
- **Date:** 2026-07-04
- **Deciders:** @architect (doctrine/spec, retraction cmt 4881717762), @product-manager (cross-lane sponsor — verify dev/tester/PM scenarios), @developer (yaml impl in `.github/workflows/label-check.yml` j.4 logic — owner merge required, **NOT in this PR**, deferred per Cadence Rule 1 atomic pattern), @tester (d049 d-test sign-off per ADR-0044 RED-first — `scripts/tests/d049-j4-tester-author-exemption.sh` ≥3 TCs), @atilcan65 (workflow YAML owner-gated squash per file ownership matrix)
- **Supersedes:** — (amends layer 5 j.4 logic per cycle ~#3698 j.4 extension; this ADR adds the tester-author exception clause to existing logic)
- **Related:**
  - [ADR-0012](./ADR-0012-required-label-set.md) — Required Label Set + §Handoff Discipline cc:self anti-pattern ("❌ Kendine cc: koymak")
  - [ADR-0015](./ADR-0015-atomic-agent-handoff.md) — Atomic 4-flag handoff (sister anti-pattern reference)
  - [ADR-0031](./ADR-0031-owner-override-doctrine.md) — Owner-override PR merge doctrine (2-tier architect review taxonomy)
  - [ADR-0044](./ADR-0044-verdict-by-scope-clarification.md) — RED-first TDD (tester sign-off discipline, d049 sister)
  - [ADR-0048](./ADR-0048-status-ready-auto-add-gating.md) — Layer 5 status:ready auto-add (contains j.4 logic at L537-578 — this ADR amends it)
  - [ADR-0049](./ADR-0049-behavioral-workflow-test-framework.md) — d-test framework (d049 sister)
  - [ADR-0055](./ADR-0055-d-test-id-uniqueness-sub-pattern-matrix.md) — Cadence Rule 1 atomic (this ADR + TD-049 + INDEX.md row + d049 contract in same PR-cluster, d049 impl deferred to follow-up PR)
  - [ADR-0056](./ADR-0056-layer-5-idempotency-reconcile.md) — Layer 5 idempotency reconcile (WARN-not-FAIL cheaper fix sister-pattern)
- **Closes:** Issue #798 doctrinal follow-up gap (PR #799 vacuous-pass surfacing; ARCH verdict retraction cmt 4881717762 corrected prior misdiagnosis)
- **Live Instances:** PR #799 (Issue #798 d124 RED-state contract, discoverer instance, bot cmt 4881350496 surfaced j.4 VACUOUS-PASS at 08:47:46Z, arch retraction cmt 4881717762 at 11:01:40Z, cycle ~#4042)
- **d-test integration:** d049 (`scripts/tests/d049-j4-tester-author-exemption.sh`, ≥3 TCs RED-first per ADR-0049 baseline) — contract committed in this PR-cluster, **impl deferred to Sprint 24+ P2 follow-up PR** per Cadence Rule 1 atomic cross-PR-cluster variant (Path B per ADR-0060 deferral pattern, sister-pattern to d121 in ADR-0064)
- **Workflow YAML changes:** `.github/workflows/label-check.yml` Layer 5 j.4 logic addition (~3 LoC, gates inner reviewer-chain check on `reqAgent !== 'agent:tester'`). **NOT in this PR** — owner-gated territory per file ownership matrix; owner squash required per ADR-0031.

---

## Context

### The vacuous-pass scenario (PR #799 LIVE INSTANCE)

On 2026-07-04T08:47:46Z, `github-actions[bot]` posted cmt 4881350496 on PR #799 (tester-authored, `agent:tester + type:feature + status:in-progress`) flagging **Layer 5 j.4 VACUOUS-PASS detection** (FAIL, not silent-skip) per cycle ~#3698 j.4 extension doctrine. The detection correctly FAILed because PR #799 lacks `cc:tester` + `needs-tester-signoff` (the j.4 reviewer-chain requirement for non-docs type:feature PRs).

**However**: the missing chain on PR #799 is **semantically intentional**, not a hygiene failure:

1. **cc:tester cannot be self-applied** — per CLAUDE.md §Handoff Discipline anti-pattern: "❌ Kendine `cc:` koymak — Watcher zaten seni atanan işlerde otomatik uyandırır, kendine etiket koymak gereksiz." Tester cannot self-cc.
2. **needs-tester-signoff is vacuous on tester-authored work** — self-sign-off has no semantic meaning. A tester signing off their OWN work is structurally the same as no sign-off at all. The label would be a false-positive audit trail entry.

The j.4 detection (cycle ~#3698) is **correct doctrine for the general case** (non-tester authors must have cc:tester + needs-tester-signoff) — it just doesn't handle the author=tester case where the requirement cannot be satisfied by design.

### The misdiagnosis (architect observation)

My arch verdict on PR #799 (cmt 4881693888, 2026-07-04T10:56:37Z) misdiagnosed the label-check FAIL root cause as a PR-side hygiene issue ("status:in-progress → status:in-review per ADR-0012") — the **actual** root cause was the j.4 detection correctly FAILing + doctrine gap for tester-authored case. My retraction cmt 4881717762 (2026-07-04T11:01:40Z) corrected the verdict to 🟢 OK no-label-change-required.

This ADR is the doctrinal codification of the fix design.

### Why a new ADR (not just an amendment to ADR-0048)

Layer 5 j.4 logic is part of ADR-0048 (status:ready auto-add gating). Adding the tester-author exception clause is a doctrinal amendment to j.4 behavior. Per file ownership matrix + ADR-0031 owner-override doctrine, **amendments to workflow YAML are owner-gated**. This ADR is the architect's pre-work — the doctrine captured here is what the workflow patch implements.

**Why NOT amend ADR-0048 directly**: ADR-0048 is **Accepted doctrine** with multiple live instances and amendments (Path A verdict-emoji gate, Amend-3 initial-trigger guard). Adding a tester-author exception clause is a **distinct semantic concern** (vacuous-pass detection's author-conditional behavior) that warrants its own canonical home for discoverability. Same reasoning as ADR-0062 / ADR-0063 (Layer 5 amendments as separate ADRs).

---

## Decision

**Adopt the tester-author exception clause** in Layer 5 j.4 logic: when the PR's `agent:*` label is `agent:tester`, the inner reviewer-chain check (`cc:tester` + `needs-tester-signoff`) is **skipped** (silent-skip with `silent_skip` audit log per ADR-0045 lens d). For all other agent values, the existing j.4 behavior is preserved.

### §Canonical j.4 patch shape (~3 LoC addition)

```diff
- } else if (['type:bug', 'type:feature', 'type:refactor', 'type:chore', 'type:incident'].includes(reqType)) {
-   // non-docs path: cc:tester + needs-tester-signoff required
-   if (!labels.includes('cc:tester') || !labels.includes('needs-tester-signoff')) {
-     vacuousPassFail = `j.4 vacuous-pass: non-docs PR (type=${reqType}) missing reviewer chain — cc:tester=${labels.includes('cc:tester')} needs-tester-signoff=${labels.includes('needs-tester-signoff')}. Per cycle ~#3698 insight, Layer 5 must NOT pass vacuously after reviewer chain removal.`;
-   }
- }
+ } else if (['type:bug', 'type:feature', 'type:refactor', 'type:chore', 'type:incident'].includes(reqType)) {
+   // TESTER-AUTHOR EXCEPTION (ADR-0068, TD-049): tester-authored PRs cannot self-cc
+   // (cc:self anti-pattern per CLAUDE.md §Handoff Discipline) or self-sign-off
+   // (vacuous — tester signing off own work has no semantic meaning). Skip j.4
+   // reviewer chain req, emit silent_skip audit log (ADR-0045 lens d compliance).
+   if (reqAgent !== 'agent:tester') {
+     if (!labels.includes('cc:tester') || !labels.includes('needs-tester-signoff')) {
+       vacuousPassFail = `j.4 vacuous-pass: non-docs PR (type=${reqType}) missing reviewer chain — cc:tester=${labels.includes('cc:tester')} needs-tester-signoff=${labels.includes('needs-tester-signoff')}. Per cycle ~#3698 insight, Layer 5 must NOT pass vacuously after reviewer chain removal.`;
+     }
+   } else {
+     core.info(`[Layer 5 j.4] tester-authored PR exempted from reviewer chain req (agent=${reqAgent}, ADR-0068, silent_skip)`);
+   }
+ }
```

**Logic semantics**:

| Author (`agent:*`) | Non-docs PR behavior | Audit log |
|---|---|---|
| `agent:developer` (or any non-tester) | Existing j.4 check (must have `cc:tester` + `needs-tester-signoff`) | j.4 PASS / FAIL as before |
| `agent:tester` | **Skip j.4 check** (tester-authored PRs cannot self-cc or self-sign-off) | `silent_skip` log per ADR-0045 lens d |

**Why `silent_skip` not VACUOUS-PASS detection**: the existing `vacuousPassFail` logic FAILs the check; the new test branch is **structurally different** — it intentionally bypasses the check with documented rationale, not fails it. Sister-pattern to Layer 3 type:bug check (label-check.yml L241-322) which uses `silent_skip` log on owner-override.

### §Authoritative scope (NOT in scope)

- **type:docs PRs**: j.4 logic does not enter the non-docs branch (label-check.yml L549 branch is `else if non-docs`), so type:docs is **unaffected** by this amendment. The docs author (arch/PM/orch) carries verdict authority via ADR-0048 §Type-driven table.
- **Other agent types**: `agent:developer`, `agent:architect`, `agent:product-manager`, `agent:orchestrator`, `agent:human` — all retain existing j.4 behavior (non-docs → require `cc:tester` + `needs-tester-signoff`).
- **Generalization to other self-author vacuous cases** (e.g., architect-authored docs PRs where `needs-architect-review` is vacuous): **deferred to Sprint 25+ candidate** — verify-only follow-up, since architect-authored docs PRs ALREADY have an exception via `cc:architect` + `verdict-by:<ts>` doctrine (ADR-0024 §Auto-Verdict-By Hook).

### §Why NOT option (b) — keep as-is + tester self-labels

Orchestrator's escalation offered (a) exempt tester-authored PRs OR (b) keep + tester self-labels. **Option (b) rejected** because:

1. **cc:self is anti-pattern** per CLAUDE.md §Handoff Discipline ("❌ Kendine cc: koymak").
2. **needs-tester-signoff is semantically vacuous** when tester is the author — adding the label would be a **false-positive audit trail entry** that misrepresents the review structure.
3. **No semantic improvement** — option (b) preserves the FAIL behavior but adds the labels anyway, which violates the anti-pattern above.
4. **Doctrine drift risk** — option (b) sets precedent that exceptions are handled at the PR-hygiene level (per-PR manual fixes) rather than at the doctrine level (workflow YAML logical correctness). This is the inverse of the architect's "make the system structurally correct, don't paper over with hygiene" principle.

---

## Consequences

### Positive

- **Eliminates false-positive CI RED** on tester-authored non-docs PRs (current pain point, surfaced by PR #799).
- **Preserves j.4 detection integrity** for non-tester authors — the FAIL-not-silent-skip behavior is correct doctrine for the general case.
- **Doctrinally clean** — single exception clause (`reqAgent !== 'agent:tester'`) gates the existing logic without restructuring.
- **Audit trail preserved** — `silent_skip` log line documents the exception per ADR-0045 lens d compliance (no silent-skip class).
- **Sister-pattern with Layer 5 reversal handler** (TC4, label-check.yml L580-601) which already documents "exception clauses for special author cases" precedent.

### Negative

- **Adds 1 conditional branch** to Layer 5 logic (~3 LoC addition) — minor complexity cost, well-bounded.
- **Owner-gated workflow YAML change** required (per file ownership matrix) — coordination tax on owner squash gate.
- **d049 d-test deferred** to follow-up PR per Cadence Rule 1 atomic cross-PR-cluster variant — implementation debt until Sprint 24+ P2.
- **Sister-pattern precedent risk** — future "X-authored PRs exempt from Y" requests will need analogous per-case evaluation. Mitigation: each request enters via issue → ADR (architect) → owner-gated workflow patch.

### Follow-up tickets

1. **d049 d-test** (`scripts/tests/d049-j4-tester-author-exemption.sh`, ≥3 TCs RED-first per ADR-0049 baseline) — Sprint 24+ P2 follow-up PR per Cadence Rule 1 atomic cross-PR-cluster variant.
2. **Workflow YAML patch PR** (`.github/workflows/label-check.yml` L537-578 j.4 logic, ~3 LoC addition) — owner-gated squash per file ownership matrix + ADR-0031, paired with d049 GREEN.
3. **Sprint 25+ candidate** — generalize exception clause to other self-author vacuous cases (architect-authored docs PRs) — verify-only follow-up since arch-authored docs ALREADY have exception via ADR-0024 §Auto-Verdict-By Hook.
4. **TD-049** filed in `docs/tech-debt.md` — RCA + payoff trigger + owner responsibility documented.
5. **INDEX.md row** added in this PR-cluster per Cadence Rule 1 atomic.

---

## 9-Lens Attestation (per ADR-0045)

| Lens | Status | Notes |
|---|---|---|
| **(a) Data flow** | ✅ GREEN | Patch gates inner `if` on `reqAgent !== 'agent:tester'`; preserves existing reviewer-chain check + vacuumPassFail emit for non-tester authors. |
| **(b) Runtime preconditions** | N/A | Doctrine-only ADR in this PR; runtime preconditions (self-hosted runner reachability, secret non-emptiness) deferred to workflow YAML impl PR. |
| **(c) Canonical entry** | ✅ GREEN | Workflow YAML is the canonical entry for Layer 5 j.4 logic; patch is in-place at L537-578. |
| **(d) Silent-skip risk** | ✅ GREEN | Tester-author branch emits `core.info('[Layer 5 j.4] tester-authored PR exempted ...')` log line per ADR-0045 lens d. No silent skip class. |
| **(e) Idempotency** | N/A | Same label state produces same branch decision on every workflow run. |
| **(f) Observability** | ✅ GREEN | `silent_skip` log + VACUOUS-PASS FAIL comment preserved (existing) + new exempted-branch info log. All observable via Actions logs `grep`. |
| **(g) Security & privacy** | ✅ GREEN | No new attack surface; tester-authored PRs are publicly observable via `agent:tester` label. |
| **(h) Workflow YAML SHA pin** | N/A | Patch is to existing L537-578 step which uses `actions/github-script@f28e40c7f34bde8b3046d885e986cb6290c5673b # v7` (pinned) — unchanged. |
| **(i) Platform hard constraints** | N/A | Workflow YAML step-level: `runs-on` + `permissions` unchanged. |
| **(j) Auto-gen file refs + live-state** | ✅ GREEN | Auto-gen files (`.claude/agents/*.md` rendered, `scripts/claim-next-ready.sh` etc.) not touched by this ADR. Live-state: `git show origin/main:.github/workflows/label-check.yml | grep -c 'j.4' = 1` (verified 2026-07-04T11:00Z cycle ~#4041). |

**All 9 lenses verified** per ADR-0045 checklist. No lens gaps. Doctrinally clean amendment.

---
