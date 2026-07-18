# ADR-0035 — Layer 3 CI gate: open-only fire (Issue #227 re-fire gap fix)

**Status:** Proposed
**Date:** 2026-06-21
**Supersedes:** (partial) PR #220 Layer 3 step trigger condition
**Related:** ADR-0012 (§Type-driven invariants — Layer 3 mandate), Issue #213 (TEST-WAKE-ENFORCE), Issue #227 (re-fire gap bug filing), PR #220 (MERGED-with-override aftermath), ADR-0031 (Owner-Override Doctrine)

---

## Context

PR #220 (Layer 3 CI gate, MERGED 2026-06-21T20:58:56Z, sha `43252a1`) added the `type:bug` PR requirement for `cc:tester` + `needs-tester-signoff` at open. The merge was an **owner-override per ADR-0031**: PM posted a 🔴 BLOCK verdict (comment 4763243123) flagging that the step fires on **every label change**, not just on `opened`. Owner merged anyway with the rationale "test in prod, fix in next PR" — this ADR is the **audit-trail follow-up** closing the re-fire gap.

### Live repro (predicted, will hit first type:bug PR after #220 merge)

| Time | Action | Layer 3 status |
|---|---|---|
| t+0s | Developer opens `type:bug` PR with `cc:tester` + `needs-tester-signoff` | ✅ pass (labels present) |
| t+N min | Tester posts 🟢 APPROVED, **atomically removes** `cc:tester` + `needs-tester-signoff`, adds `status:ready` | ❌ FAIL (labels absent) |
| t+N+1 min | Workflow re-fires on the label change | ❌ FAIL remains |
| Result | PR is `status:ready` but CI RED. Owner cannot merge without bypass. |

### Why this matters now

- The **first `type:bug` PR after PR #220 merge will hit this** — predictable failure
- Tester sign-off is the **standard happy path** for `type:bug` PRs (per ADR-0009 §Handoff Discipline)
- Owner-override clause in PR #220 is **documentation-only** — CI gate doesn't parse PR body
- **Silent failure mode**: tester signs off, walks away, CI red. Next person discovers it with no obvious cause.

## Decision

**Add `if: github.event.action === 'opened'` to the Layer 3 step in `.github/workflows/label-check.yml`**, so the type-driven invariant check fires only at PR open, not on subsequent label changes.

```yaml
# Pseudo-diff for .github/workflows/label-check.yml
- name: Layer 3 — type:bug requires cc:tester + needs-tester-signoff
  if: github.event.action == 'opened'   # ← NEW LINE: open-only fire
  uses: actions/github-script@v7
  env:
    MARKER: "<!-- adr-0012-type-driven -->"
  with:
    script: |
      # ... unchanged from PR #220
```

### Why open-only is correct (not a band-aid)

The semantic of "type:bug PR must have cc:tester + needs-tester-signoff at open" is a **birth-time invariant** (ADR-0012 §Type-driven invariants: "at open"). It is NOT a steady-state invariant. Once the PR is opened correctly, the workflow has done its job; subsequent label changes are governed by Handoff Discipline (ADR-0009), not by the CI gate.

| Lifecycle phase | Layer 3 fires? | Rationale |
|---|---|---|
| `opened` | ✅ Yes | Birth-time check: cc:tester + needs-tester-signoff must be present |
| `reopened` | ❌ No | Reopened state implies the PR was previously correct; re-check is redundant |
| `labeled` (any subsequent change) | ❌ No | Handoff Discipline governs; CI gate stays out of the way |
| `unlabeled` | ❌ No | Tester sign-off removes both labels atomically — this is the **expected** steady-state, not a violation |
| `synchronize` (new commits) | ❌ No | Commits don't change label state; no need to re-validate |

## Rationale

### Why Option 1 over the others

| Option | Description | Pros | Cons | Verdict |
|---|---|---|---|---|
| 1 | `if: github.event.action === 'opened'` only | Simplest; matches the "at open" doctrine; ~1 line | Loses the ability to catch late label removal by malicious actor (acceptable per Handoff Discipline) | **Accepted** |
| 2 | Skip if `status:ready` is present | Preserves re-fire capability for non-ready PRs | Race condition: tester atomically adds `status:ready` and removes `cc:tester` — workflow might still catch mid-flight | Rejected — race-prone |
| 3 | Skip if tester APPROVED verdict comment is present | Most precise | Requires comment parsing in CI workflow (~10 lines); brittle | Rejected — over-engineered |
| 4 | Replace `needs-tester-signoff` with `tester-not-signed-off` | Inverted lifecycle | Same fundamental problem: lifecycle still triggers on label change | Rejected — doesn't fix |

### Why this is doctrine-grade (ADR), not a hotfix

- The PR #220 Layer 3 mandate is **architectural** (ADR-0012 §Type-driven invariants); its lifecycle semantics are part of the doctrine
- The fix is **breaking** for the "type:bug PR opened without `cc:tester`" case — but that case is already a violation, so no regression
- The fix has **owner-override implications** (per ADR-0031): owner-override clause in PR #220 is now correct as-written (CI doesn't parse PR body, but doesn't re-fire either, so owner-override is the **only** path forward — explicit, not silent)
- The fix affects **all future type:bug PRs** + closes the **PM BLOCK audit-trail obligation** from the PR #220 override

Hence ADR-0035, not a hotfix PR.

## Consequences

### Positive

- **Tester sign-off flow works correctly** on type:bug PRs: remove cc:tester + needs-tester-signoff atomically → CI stays green
- **Owner-override is the only escape hatch**: explicit (per ADR-0031), not silent CI failure
- **PR body parser still unnecessary**: ADR-0012 §Type-driven invariants §Owner-override clause remains documentation; CI doesn't need to parse
- **No new failure modes introduced**: the only case the workflow would have caught after open is "label was wrong at open but added later" — which is the developer's correction, not a violation

### Negative

- **Late label-removal by mistake is no longer caught by CI**: e.g., if developer accidentally removes `cc:tester` mid-PR, the CI gate won't catch it. Mitigation: developer self-discipline + reviewer awareness + ADR-0009 §Handoff Discipline (which says removing cc:* before sign-off is a violation regardless).
- **One more `if:` condition in label-check.yml**: minor CI surface increase. Mitigation: documented + tested.

### Out of scope

- **PR body parser for owner-override audit trail**: explicitly rejected per ADR-0012 §Owner-override (documentation-only by design). This ADR doesn't reopen that decision.
- **Generalizing to other type-driven invariants**: not needed; Layer 3 is the only type-driven invariant per ADR-0012 §Type-driven invariants table. Layer 1 + Layer 2 are already correct.
- **Reverting PR #220**: not warranted; PR #220 is correct for the open case. Only the re-fire semantics need fixing.

## Implementation handoff

Per Issue #227 owner table (PM's recommendation):

- **@architect** (this ADR + RCA confirmation): 0.5 SP ✅ (this PR)
- **@developer** (`if:` condition add + d026 regression): 0.5 SP (separate PR)
- **@tester** (d026 sign-off): 0.25 SP (separate PR)
- **Total**: 1.25 SP

### d026 regression test contract (developer-owned)

5 test cases (modeled on existing label-check.yml CI behavior):

1. **Open a `type:bug` PR with `cc:tester` + `needs-tester-signoff`** → Layer 3 fires, passes (✅)
2. **Open a `type:bug` PR WITHOUT `cc:tester` or `needs-tester-signoff`** → Layer 3 fires, fails (❌) with `<!-- adr-0012-type-driven -->` comment
3. **On an open `type:bug` PR, remove `cc:tester`** (simulating tester sign-off) → Layer 3 does NOT fire (no re-check), workflow stays green
4. **On an open `type:bug` PR, remove both `cc:tester` AND `needs-tester-signoff` atomically + add `status:ready`** → Layer 3 does NOT fire, workflow stays green
5. **Reopen a `type:bug` PR** (action: `reopened`) → Layer 3 does NOT fire (the `if:` filter excludes reopen)

### Sprint 4 impact

- Sprint 4 commitment: 24.0 SP (post ADR-0034) → **24.75 SP** (+0.5 architect, +0.5 dev, +0.25 tester for Issue #227)
- Buffer: 10.25-20.25 SP (still in range)
- Sprint 4 P0 chain: previous P0s closed + Issue #228 (P0) + Issue #227 (P1, but if first type:bug PR is imminent, escalate to P0)

### Owner-override audit trail (per ADR-0031)

This ADR formalizes the **PM BLOCK → owner override → follow-up ADR** pattern observed on PR #220:

- PM BLOCK verdict (comment 4763243123) is the **audit trail record**
- Owner override rationale is implicit ("merge and follow up")
- This ADR (ADR-0035) is the **follow-up closing the override**
- Pattern is now codifiable for future owner-override cases (per ADR-0031 §Consequences)

## Pending

- Owner (@atilcan65) approves ADR-0035 (Proposed → Accepted)
- Developer opens impl PR for the `if:` condition add + d026 regression
- Tester signs off on d026
- Owner merges all PRs
- PR #220 BLOCK verdict can be **resolved** with a closing comment linking ADR-0035

— @architect, 2026-06-21T22:10:00Z
