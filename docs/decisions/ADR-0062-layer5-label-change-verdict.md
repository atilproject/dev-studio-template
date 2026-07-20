# ADR-0062: §Layer 5 Label-Change Event Verdict-Gate Extension

- **Status**: Accepted
- **Date**: 2026-07-19
- **Deciders**: @architect
- **Supersedes**: none
- **Related**: ADR-0048 (`status:ready` Auto-Add Gating — Path A foundation this ADR extends), ADR-0048-amendment (verdict-state-aware Path A, PR-creation only — this ADR widens its scope), ADR-0056 (Layer 5 idempotency reconcile, WARN-not-FAIL pattern proven), ADR-0012 (Required Label Set — cascade-strip Part 1 + Part 2), ADR-0044 (TDD RED discipline), ADR-0049 (d-test framework), ADR-0055 (Cadence Rule 1 atomic d-test uniqueness)
- **Ported-from**: AtilCalculator ADR-0062 (S32-027 Cadence-Rule-2-B DEFERRED renumber/port batch, Issue #164)

> **Ported-from note**: This ADR is the HYBRID port of AtilCalculator ADR-0062 (`amendment-layer-5-label-change-verdict-gate`) as part of the S32-027 Cadence-Rule-2-B DEFERRED renumber/port batch (Issue #164). All portable doctrine is preserved; calc-specific artifacts (concrete PR numbers, comment IDs, calc-PR timestamp literals, hook line-number specifics) are redacted in favor of generalized descriptions. Cycle-number lineage references (e.g. `cycle ~#NNNN`) are kept as historical provenance anchors only.

---

## Context

ADR-0048-amendment (Path A, WARN-not-FAIL) extended the Layer 5 (`status:ready` auto-add) workflow check to read the latest PR verdict emoji from the PR's `comments[]` BEFORE auto-promoting. This closed the pathology of premature `status:ready + cc:human` landing before the tester verdict was posted.

However, the Path A amendment fires only on `pull_request_target` events at `opened`/`reopened` action. It does **NOT** cover **label-change events** when the reviewer lane is transferred AFTER a verdict (e.g. a tester delivering a 🔴 verdict and transferring the lane back to the developer by flipping `cc:tester` → `cc:developer`).

### Triggering LIVE INSTANCE (RETRO carrier)

A specific PR (2026-06-29, tester triage comment in the original cycle) exhibited the pattern:

- (T+0s) PR-creation path: Layer 5 Path A verdict-emoji gate correctly REFUSED.
- (T+~4m) Label-change path: tester delivered a 🔴 CHANGES REQUESTED verdict; tester flipped labels per the dispatch doctrine to remove `needs-tester-signoff` and `cc:tester` and add `cc:developer`.
- (T+~10s after label flip) Layer 5 saw: `needs-tester-signoff` absent + `cc:developer` present → "reviewer chain complete" → auto-ADDED `status:ready` (FALSE POSITIVE — verdict was 🔴).
- (T+~12s after auto-add) The developer manually re-added `status:in-review`.
- (T+~21s after auto-add) Layer 5 cascade-strip removed `status:ready` (correct outcome, but for the wrong reason — verdict-emoji check should have been the gate, not a downstream cascade-strip).

**Net pathology**: `status:ready` was added on a 🔴-verdict PR, signaling "ready for owner merge gate" when in reality the reviewer was asking for changes. The owner could have merged broken code.

### Root cause

Layer 5's verdict-state-aware logic (ADR-0048-amendment Path A) is wired into **PR-creation events only**. When the reviewer transfers lane (🔴 verdict → `cc:<next-peer>` + remove `needs-tester-signoff`), Layer 5 sees the label change but does NOT re-check verdict state because the trigger event is `pull_request_target labeled cc:<peer>`, not PR-creation.

**Doctrine gap**: Path A's verdict-emoji check is meant to be **stateful across the PR lifecycle**, but is currently gated to a single event type.

Ported from AtilCalculator ADR-0062 as part of S32-027 Cadence-Rule-2-B (Issue #164).

## Decision

**Path C** — extend Layer 5 Path A's verdict-emoji check to fire on **all `cc:<peer>` (and the canonical wake-`needs-*` labels) label-change events**.

### Path C scope (chosen)

The verdict-emoji check (currently existing only inside the "should we auto-promote" branch of the workflow) is extracted into a **gating pre-check** that runs at the **start of Layer 5**, BEFORE any auto-add decision. The pre-check fires on:

- `labeled` / `unlabeled` events where `context.payload.label.name` starts with `cc:`
- `labeled` / `unlabeled` events for `needs-tester-signoff`
- `labeled` / `unlabeled` events for `needs-architect-review`

Pseudocode shape (portable; line numbers redacted):

```javascript
// Path C (proposed — placed after Bot-actor + status:* short-circuit):

// ------------------------------------------------------------------
// ADR-0062: verdict-emoji gate on label-change events.
// Sister-pattern: ADR-0048-amendment Path A (PR-creation only) extended
// to all cc:<peer> add/remove events. Prevents false-positive status:ready
// on tester 🔴 verdict lane transfer.
// ------------------------------------------------------------------
const onlyLabelChangeCc = (
  evtAction === 'labeled' || evtAction === 'unlabeled'
) && context.payload.label &&
context.payload.label.name &&
(context.payload.label.name.startsWith('cc:') ||
 context.payload.label.name === 'needs-tester-signoff' ||
 context.payload.label.name === 'needs-architect-review');
if (onlyLabelChangeCc) {
  // Read LATEST PR verdict emoji from comments[] (same logic as Path A)
  const { data: comments } = await github.rest.issues.listComments({ owner, repo, issue_number: number, per_page: 100 });
  let latestVerdict = null;
  const verdictRe = /🟢|🟡|🔴/g;
  for (const c of comments) {
    if (!c.user || c.user.type === 'Bot') continue;
    const m = c.body && c.body.match(verdictRe);
    if (m) latestVerdict = m[m.length - 1];
  }
  if (latestVerdict === '🔴' || latestVerdict === '🟡') {
    core.info(`[Layer 5 ADR-0062] verdict gate REFUSED on ${evtAction} ${context.payload.label.name} (latest verdict=${latestVerdict}). Skip status:ready auto-add.`);
    // Silent-skip audit (ADR-0045 lens (d) observability)
    const skipBody = [
      '<!-- adr-0062-verdict-gate-skip -->',
      '**Layer 5 verdict-gate skip (ADR-0062)**',
      '',
      `- **Trigger**: \`labeled\`/\`unlabeled\` event on \`${context.payload.label.name}\``,
      `- **Latest verdict in comments**: ${latestVerdict}`,
      `- **Action**: SKIP \`status:ready\` auto-add (verdict not 🟢)`,
      `- **PR**: #${number}`,
      `- **Workflow run**: \`${{ github.run_id }}\``,
      `- **ADR**: \`docs/decisions/ADR-0062-layer5-label-change-verdict.md\``,
    ].join('\n');
    const existing = comments.find(c => c.user && c.user.type === 'Bot' && c.body && c.body.includes('<!-- adr-0062-verdict-gate-skip -->'));
    if (existing) {
      await github.rest.issues.updateComment({ owner, repo, comment_id: existing.id, body: skipBody });
    } else {
      await github.rest.issues.createComment({ owner, repo, issue_number: number, body: skipBody });
    }
    return;
  }
}
// If latestVerdict === '🟢' or null, fall through to existing logic
```

### Decision rules

| Trigger event | Latest verdict in `comments[]` | Layer 5 verdict-gate action |
|---------------|--------------------------------|----------------------------|
| `labeled cc:<peer>` (post-verdict lane transfer) | 🔴 | REFUSE `status:ready` auto-add + silent_skip log |
| `labeled cc:<peer>` | 🟡 | REFUSE + silent_skip |
| `labeled cc:<peer>` | 🟢 | FALL THROUGH (existing logic OK — `cc:human` + `status:ready` if reviewer chain cleared) |
| `labeled cc:<peer>` | null (no verdict yet) | REFUSE + silent_skip (default-deny, sister to ADR-0048 silent_skip lens (d)) |
| `unlabeled cc:<peer>` (lane removal) | 🔴 | REFUSE + silent_skip |
| `unlabeled cc:<peer>` | 🟢 / null | FALL THROUGH (existing logic) |
| `labeled/unlabeled needs-tester-signoff` | 🔴 | REFUSE + silent_skip (tester re-rejected post-APPROVED) |
| `labeled/unlabeled needs-architect-review` | 🔴 | REFUSE + silent_skip |
| `pull_request opened/reopened` event (Path A) | (existing Path A logic preserved) | unchanged |

### Why Path C (not A/B from the carrier issue)

**Path A (explicit `verdict:*` labels)** — machine-readable labels. **Rejected for the originating P2 hardening sprint**:

- (+) Cleanest machine semantics.
- (-) Label clutter; requires agent discipline to set on every verdict comment.
- (-) ADR-0024 already mandates `verdict-by:<ts>` (clock, not content); adding `verdict:*` doubles the label schema.
- (-) Out-of-scope for the originating P2 hardening window.

**Path B (cross-event `pulls.listReviews` API call)** — `reviews[]` state check. **Rejected**:

- (+) No new label schema.
- (-) Latency: extra API call per label-change; rate-limit risk on high-traffic repos.
- (-) Reviewer state semantics (`APPROVED` / `CHANGES_REQUESTED` / `COMMENTED`) differ from comment emoji; would need a separate doctrine gap.
- (-) Reviews API can lag behind comments (Path A already uses `comments[]`).

**Path C (cc:<peer> + verdict-emoji combo gate)** — **CHOSEN**:

- (+) Minimal API calls (piggybacks on the existing `listComments` call already in the Path A branch).
- (+) Reuses existing verdict-emoji regex from Path A.
- (+) ~10 LoC js delta; sister-pattern to Path A's existing logic.
- (+) Default-deny on null (defense-in-depth).
- (+) Audit-trail marker pattern consistent with existing Layer 5 markers.
- (-) Triggers on every `cc:*` label event (modest perf; GitHub Actions budget fine).
- (-) Defaults to silent_skip on null verdict (could block legitimate flow if verdict not posted yet — but Path A already has this fallback in the PR-creation path, so behavior is consistent).

### Why now (originating P2 hardening, not later)

The RETRO-016 cluster had 4 LIVE INSTANCES in 2 days at the originating cycle. Pattern is **active, not historical**. The P2 doctrine-hardening window is the right vehicle — same workshop that closed sibling paths in the same sprint.

## Rationale

### Why extend Path A vs new gate logic

| Option | Cost | Audit trail | Path A reuse | Verdict |
|--------|------|-------------|--------------|---------|
| **A. New gate logic (separate workflow step)** | ~50 LoC | New marker | 0% | ❌ Duplicate infrastructure |
| **B. Independent re-implementation** | ~80 LoC | New marker | 0% | ❌ Maintenance burden ×2 |
| **C. Extend Path A's check to label-change (THIS)** | ~10 LoC | Reuse Path A markers | 100% | ✅ **Chosen** |
| **D. Wait for a future amendment v2** | 0 (deferred) | n/a | n/a | ❌ The pathology is still active |

### Evidence (provenance, redacted)

- A specific PR — primary LIVE INSTANCE in the original cycle (cmt IDs redacted; Layer 5 false-positive log + cascade-strip remediation).
- Sister-pattern PRs documented in RETRO-016 #1, #3, and #6 carriers at the original cycle.
- **ADR-0048-amendment Path A** — proven WARN-not-FAIL pattern in production; Path C is an extension, not a new doctrine.

### Compatibility

- ✅ Backward compatible with Path A's PR-creation gate (unchanged).
- ✅ Backward compatible with ADR-0056 idempotency reconcile (Layer 5 self-corrects on next label event).
- ✅ Backward compatible with ADR-0055 (d-test uniqueness — this ADR does NOT introduce a new d-test; it reuses the Path A TC family).

## Consequences

### Positive

- ✅ The false-positive pattern is closed; `status:ready` will NOT auto-add on 🔴-verdict lane transfers.
- ✅ Owner merge gate no longer at risk from reviewer lane-transfer false-positives.
- ✅ 9-Lens lens (b) Runtime preconditions + lens (d) Silent-skip improved (no metric = no production kept).
- ✅ Sister-pattern symmetry with Path A's PR-creation gate (consistent doctrine across event types).
- ✅ ~10 LoC implementation (within P2 hardening budget).
- ✅ Compatible with ADR-0055 Cadence Rule 1 (no new d-test; reuse existing).

### Negative (mitigated below)

- ⚠️ Extra `listComments` API call on every `cc:*` label-change event — mitigate: Layer 5 already calls `listComments` in the PR-creation branch; only on label-change events does it add one call. GitHub Actions budget is ample (~5000/hr).
- ⚠️ Default-deny on null verdict could block legitimate flow if verdict not posted yet — mitigate: Path A already exhibits this behavior in the PR-creation branch; behavior is consistent.
- ⚠️ Workflow file changes require owner merge per the file-ownership matrix — mitigate: arch drafts ADR + d-test amendment, tester signs off, owner merges the workflow file (the standard P2-hardening codification workshop flow).
- ⚠️ Per-event label-change fires could trigger false-skips if the reviewer posts the verdict AFTER the lane transfer — mitigate: silent_skip audit comment + the next label-change event re-evaluates (idempotent like ADR-0056).

### d-test integration

**Reuses the Path A d-test family** — no new d-test required (per ADR-0055 Cadence Rule 1 uniqueness):

- Path A carrier d-test — TC2 extended: add TC2.5 (label-change 🔴 false-positive).
- Path A sister-carrier d-test — unchanged.
- Future: a separate reserved runner-access regression d-test (per the originating ADR-0061 sibling).

### Sister-pattern: future prevention

- A separate upcoming ADR (Layer 4 cascade-strip + Layer 5 reversal race on tester APPROVED) is a **distinct Layer 4 doctrine gap** and gets its own ADR (out of scope here).
- RETRO-016 #1 — already closed by the Layer 5 initial-add race fix in the originating cycle.
- RETRO-016 #3 — closed by a cross-watchdog 30s gap fix in the originating cycle.

## Implementation checklist (workshop standard)

**Pre-Faz 0 (arch + tester)**:

- [ ] Path A d-test extended with the label-change 🔴 false-positive TC (tester-led, RED-first per ADR-0044).
- [ ] 3 minimum TCs: TC-X.1 (labeled `cc:*` + 🔴 verdict → skip), TC-X.2 (labeled `cc:*` + 🟢 verdict → fall through), TC-X.3 (null verdict → skip).

**Faz 0 (arch authored)**: ✅ THIS ADR (docs PR lane; sprint-gated).

**Faz 1 (dev + tester)**:

- [ ] 1.1 yaml impl in `.github/workflows/label-check.yml` (~10 LoC js; file-ownership matrix human-only → owner merges).
- [ ] 1.2 d-test TC-X.1 / TC-X.2 / TC-X.3 GREEN.

**Faz 2 (owner)**:

- [ ] 2.1 Owner squash PR + workflow file change (file-ownership matrix).

**Faz 3 (orch + all)**:

- [ ] 3.1 RETRO watchlist updated; carrier entry closed by THIS ADR.
- [ ] 3.2 Carrier issue status:done.

## Cross-refs

- ADR-0048-amendment-verdict-state-aware — Path A foundation (this ADR extends).
- ADR-0056 — Layer 5 idempotency reconcile (WARN-not-FAIL pattern proven).
- ADR-0055 — Cadence Rule 1 atomic d-test uniqueness (no new d-test).
- File-ownership matrix: `.github/workflows/` = human-only (arch + tester draft, owner merges).
- RETRO-016 cluster siblings: #1 + #3 + #6 (in the originating cycle).

— @architect, ported from AtilCalculator ADR-0062 (S32-027 Cadence-Rule-2-B, Issue #164).
