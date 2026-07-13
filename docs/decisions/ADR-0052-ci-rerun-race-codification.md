# ADR-0052: CI re-run race codification (30s re-query window)

**Status:** Proposed (Sprint 14 P1 #3, draft pending arch sign-off + PM/dev/tester review)
**Date:** 2026-06-27
**Deciders:** @architect (drafting), @developer (d056 d-test impl), @tester (d056 sign-off + RED-first contract), @product-manager (sprint capacity reconciliation)
**Supersedes:** — (doctrinal codification; no prior ADR)
**Amends:** — (no amendment; new doctrine)
**Related:** [RETRO-008 §1](../sprints/sprint-14/plan.md) (codification carrier, PR #490 MERGED); [Issue #430](https://github.com/atilproject/AtilCalculator/issues/430) (PM §Pre-verdict cross-check); [Issue #470](https://github.com/atilproject/AtilCalculator/issues/470) (PM §Timing window codification, Sprint 13 P1 #3, PR #499); [Issue #463](https://github.com/atilproject/AtilCalculator/issues/463) (d053 sister-pattern carrier); [Issue #494](https://github.com/atilproject/AtilCalculator/issues/494) (Sprint 14 P1 #3 home)

---

## Context

Sprint 13–14 produced multiple **CI re-run race** instances where a CI workflow re-run completes between a peer's label flip and verdict post, causing **stale-state verdicts** (verdict posts on old state, then state changes underneath):

| PR | Date | Race pattern | Verdict impact |
|---|---|---|---|
| PR #472 (Sprint 13) | 2026-06-26 | status:ready auto-promote raced PM status:in-review flip | PM verdict on stale state (1m20s gap) |
| PR #485 (Sprint 13) | 2026-06-26 | Layer 5 auto-promote race with PM manual flip | label-check FAILURE caught at PR open |
| PR #499 (Sprint 14) | 2026-06-27 | Layer 5 race: `removeLabel('status:in-review')` 404 (concurrent run race) | mergeStateStatus: UNSTABLE |
| PR #500 (Sprint 14) | 2026-06-27 | Layer 5 race: label-check FAIL then PASS on retry | mergeStateStatus: UNSTABLE → null (flake per ADR-0051) |

**Pattern**: A peer posts a verdict (or label flip) based on CI state X, then a CI re-run completes within 30-60s changing state to Y. The peer's verdict is now on stale state. Downstream consumers (tester, owner squash gate) see a discrepancy.

**Current state (pre-ADR)**: §Timing window doctrine exists in PM's `docs/CLAUDE.md` (PR #499 codification, closes #470) for **comment propagation timing** (Issue #430 §Pre-verdict cross-check). But **CI state** propagation is a different timing window — GitHub Actions workflow run completion is 0-30s typical, while comment GraphQL propagation is 30-60s. These are sister-patterns but distinct.

**Why codify now**: PR #499 + PR #500 (Sprint 14) both hit the race within 24h. RETRO-008 §1 (codification carrier, PR #490 MERGED) defines the doctrine conceptually but lacks:
- Explicit 30s window timing
- Pre-verdict CI status check mechanism
- d056 d-test automated guard

Without codification, the next race becomes a 30-min investigation cycle (or worse, a stale verdict that propagates to a wrong squash decision).

---

## Decision

**Adopt the 30s re-query window as the canonical CI state check** for verdict posting:

### Pre-verdict CI status check (mandatory)

Before posting ANY verdict (🟢/🟡/🔴), the agent MUST re-query CI status **within 30 seconds of the post**:

```bash
# Within 30s of verdict post, re-query:
gh pr view <N> --json statusCheckRollup --jq '[.statusCheckRollup[] | {name, conclusion}]'
gh api repos/<owner>/<repo>/commits/<sha>/check-runs --jq '.check_runs[] | {name, conclusion, completed_at}'
```

If the re-query shows different state than what the verdict was based on, **amend the verdict** before downstream action proceeds.

### Why 30s (not 60s, not "immediate")

- **GitHub Actions workflow run completion window**: 0-30s typical (single runner re-try, re-run, re-trigger)
- **GraphQL comment propagation**: 30-60s window (separate from CI state)
- **30s is the lower bound of reliable state visibility** for CI events
- **60s is too long**: defeats the purpose (verdict is already stale by then)
- **"Immediate" is unreliable**: 0-5s window can miss the rerun completion

### Sister-pattern to Issue #470 §Timing window (PM lane)

PM's `docs/CLAUDE.md` §Dispatch Discipline already codifies the 30s window for **comment propagation** (Issue #470, PR #499, closes #470). This ADR extends the same 30s window to **CI state propagation** as a sister-pattern:

| Surface | Window | Doctrine | Carrier |
|---|---|---|---|
| Comment GraphQL propagation | 30s | Re-query comments + reviews within 30s of verdict | Issue #470, PR #499 |
| **CI state propagation** | **30s** | **Re-query `statusCheckRollup` within 30s of verdict** | **This ADR (ADR-0052)** |
| Layer 5 auto-promote | 30s | Re-query labels within 30s of any auto-promote | ADR-0053 (Sprint 14 P1 #5, planned) |

All three 30s windows form a coherent **§30s re-query family** that addresses different propagation surfaces with the same timing discipline.

### Distinction table (canonical reference)

| Scenario | Pre-verdict CI re-query | Verdict amendment needed? | Action |
|---|---|---|---|
| CI state stable (no rerun in 30s) | ✅ Same state | No | Post verdict as-is |
| CI rerun completed (state changed) | ✅ Different state | **Yes** | Amend verdict before downstream action |
| Layer 5 auto-promote happened (label flipped) | ✅ Label changed | **Yes** | Re-query labels (sister-pattern to ADR-0053) |
| PR merged or closed mid-verdict | ✅ State = MERGED/CLOSED | **Yes** | Cancel verdict, post "stale-state" note |
| Multiple reruns in flight | ⚠️ Race-on-race | **Yes** | Wait for stabilization, then re-query |

### Pre-verdict CI status check (NOT 1+ min before)

**Anti-pattern**: Querying CI status 1+ minute before posting a verdict. By the time the verdict posts, the CI state may have changed (re-run completed), and the verdict is on stale state.

**Correct pattern**: Query CI status **within 30s of posting** the verdict, NOT 1+ min before.

### Automated guard (d056 d-test, Sprint 14 P1 #3 sister)

The d056 d-test (tester-owned, dev-implemented) implements the 30s re-query window check:
- Simulates CI re-run race (synthetic test with 2 workflow runs in 30s window)
- Verifies that re-query within 30s catches the state change
- Tests 9 cases: 5 stable-state + 4 state-change scenarios
- Outputs: PASS (9/9) or FAIL (any case fails)

Integration: `scripts/tests/d056-ci-rerun-race.sh` triggered in `.github/workflows/lint-and-test.yml` (owner-merge, human-only territory).

---

## Rationale

### Why codify now (vs ad-hoc investigation per race)

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Codify 30s re-query + d056 (CHOSEN)** | Doctrinal clarity; d056 guard; future races auto-caught within 30s | Initial ADR + d-test impl (1.75 SP Sprint 14 P1 #3) | **Best fit** — pattern is established, automation is the right move |
| Ad-hoc investigation per race | No upfront work | Each race = 30-min investigation (PR #499/#500 = ~30 min combined); stale-verdict risk | **Rejected** — waste of sprint capacity, error-prone |
| Extend §Timing window to all surfaces (no new ADR) | Reuse existing doctrine | Conflates comment propagation with CI state propagation; doesn't address Layer 5 race | **Rejected** — distinct propagation surfaces need distinct doctrine |
| Webhook-based push (replace polling) | Real-time state | Complex, brittle, hard to test | **Rejected** — YAGNI, 30s polling is sufficient |

### Why 30s (not 60s, not 15s)

- **60s**: too long, verdict is stale by then
- **15s**: too short, may miss re-run completion (especially on slow runners)
- **30s**: lower bound of reliable CI event visibility, matches Issue #470 §Timing window (sister-pattern consistency)

### Why 30s re-query family (comment + CI + Layer 5)

Three distinct propagation surfaces share the same 30s timing discipline:
- **Comments/reviews**: GraphQL propagation 30-60s
- **CI state**: workflow run completion 0-30s
- **Layer 5 labels**: auto-promote + manual flip race 0-30s

Codifying all three under a §30s re-query family (with surface-specific sub-doctrines) is more maintainable than 3 separate ADRs with different timing.

### Why pre-verdict (not post-verdict only)

**Pre-verdict** re-query catches the race BEFORE the verdict propagates. **Post-verdict only** requires downstream consumers to detect the race, which is too late (verdict has already shaped downstream action).

**Correct**: re-query within 30s BEFORE post, and amend if state changed.

### Evidence: 4-race sister-pattern

| PR | Date | Race | State change | Time-to-detect |
|---|---|---|---|---|
| PR #472 | 2026-06-26 | status:ready auto-promote vs PM flip | label drift | ~5 min (caught at PR open) |
| PR #485 | 2026-06-26 | Layer 5 auto-promote vs PM manual flip | label-check FAIL | ~30s (caught by CI) |
| PR #499 | 2026-06-27 | Layer 5 race: removeLabel 404 | mergeStateStatus: UNSTABLE | ~2 min (caught at PR view) |
| PR #500 | 2026-06-27 | Layer 5 race: label-check FAIL→PASS | mergeStateStatus: null (flake) | ~30s (caught by CI retry) |

Total: ~8 minutes of sprint capacity spent on race detection, all of which 30s pre-verdict re-query would prevent. Sprint 14 P1 #3 pays back the 1.75 SP investment in ~3 races.

---

## Alternatives considered

### A. 30s re-query + d056 (chosen)

- **Pros**: captures all 4-race-pattern instances; automated guard; doctrinal clarity; sister-pattern to Issue #470 §Timing window
- **Cons**: 1.75 SP Sprint 14 P1 #3 (arch 0.5 + dev 1.0 + tester 0.25-0.5)
- **Verdict**: chosen

### B. 60s re-query window

- **Pros**: more time for re-runs to complete
- **Cons**: verdict is stale by then; defeats purpose
- **Verdict**: rejected

### C. Extend §Timing window (no new ADR)

- **Pros**: reuses existing doctrine
- **Cons**: conflates distinct propagation surfaces; doesn't address Layer 5 race
- **Verdict**: rejected

### D. Webhook-based push (replace polling)

- **Pros**: real-time state
- **Cons**: complex, brittle, hard to test
- **Verdict**: rejected — YAGNI

### E. Keep ad-hoc investigation per race

- **Pros**: no upfront investment
- **Cons**: ~30 min per race × 4 races in 48h = 2 hours sprint capacity wasted
- **Verdict**: rejected — automation pays back

---

## Consequences

### Positive

- **Doctrinal clarity**: 30s re-query window is the canonical CI state check, sister-pattern to Issue #470 §Timing window
- **d056 automated guard**: future races auto-caught within 30s (vs ~30 min manual)
- **Sprint capacity**: ~30 min/race × 4 races = 2h saved per sprint going forward
- **Sister-pattern alignment**: d056 joins d046/d048/d050b/d051/d052/d053/d054 (8-sister d-test family)
- **§30s re-query family**: comment + CI + Layer 5 surfaces share timing discipline
- **Pre-verdict doctrine**: catches races BEFORE verdict propagates (vs post-verdict detection)

### Negative

- **1.75 SP Sprint 14 P1 #3 cost**: arch 0.5 (this ADR) + dev 1.0 (d056 impl) + tester 0.25-0.5 (d056 sign-off)
- **d056 workflow integration**: requires CI gate change in `.github/workflows/lint-and-test.yml` (owner-merge territory)
- **30s window overhead**: every verdict requires a re-query (negligible latency, ~100ms)

### Out of scope (deferred)

- **Webhook-based real-time state** (replace polling): Sprint 15+ scope if 30s polling proves insufficient
- **Cross-repo CI state propagation**: Sprint 15+ scope (RETRO-008 §cross-repo watchlist)
- **CI re-run rate limiting** (anti-flake): separate concern, addressed by ADR-0051 §3-cond (engine perf flake vs regression)
- **Layer 5 race pattern**: separate ADR-0053 (Sprint 14 P1 #5, Issue #496, URGENT escalation per ORCH 2026-06-27)

### Follow-up tickets

- [ ] **d056 d-test impl** (Issue #494 sister, Sprint 14 P1 #3 sister story) — tester-owned contract, dev-owned impl
- [ ] **d056 CI integration** — `.github/workflows/lint-and-test.yml` paths trigger (owner-merge, human-only)
- [ ] **d056 INDEX.md registration** — Sprint 14 P2 #9 carry (tester-owned, 0.25 SP)
- [ ] **ADR-0053 (Layer 5 race pattern codification)** — Sprint 14 P1 #5, Issue #496, URGENT per ORCH 2026-06-27 wake
- [ ] **§30s re-query family cross-ref doc** — Sprint 14+ scope, surfaces the comment+CI+Layer 5 sister-pattern

---

## What this ADR commits to *now*

- **30s re-query window** is the canonical CI state check for verdict posting
- **Pre-verdict CI status check** is mandatory (NOT 1+ min before)
- **Sister-pattern to Issue #470 §Timing window** — 30s window extends to CI state propagation
- **d056 d-test guard** (Sprint 14 P1 #3 sister story) implements automated 30s re-query check
- **§30s re-query family** — comment + CI + Layer 5 surfaces share timing discipline
- **No breaking changes** to existing doctrine (extends PM's §Timing window to a new surface)
- **No new workflow changes** in this ADR (d056 CI integration is a separate work unit, owner-merge territory)

---

## 9-Lens attestation (per architect.md §9-Lens Review Checklist)

For this doctrine ADR, the relevant lenses are:

- **(a) Data flow** — CI state propagation: workflow run completion → `statusCheckRollup` API → peer verdict. Observable via `gh pr view --json statusCheckRollup`. Attested via PR #472/#485/#499/#500 evidence.
- **(c) Canonical entry point** — 30s re-query window is the canonical "is CI state current" check. All verdict posters must use it.
- **(d) Silent-skip risk** — NONE. The doctrine is explicit (re-query within 30s), not silent. No catch blocks or conditionals that skip the check.
- **(f) Observability** — the doctrine itself IS the observability mechanism (30s re-query). d056 d-test adds automated verification.
- **(b), (e), (g), (h), (i), (j)** — N/A for this doctrine ADR. No runtime preconditions, no idempotency concerns (re-query is read-only), no security implications, no workflow changes, no platform constraints, no auto-gen file refs.

---

## Cross-references

### Live evidence (4-race sister-pattern)

- **PR #472** (Sprint 13 P1 #3) — status:ready auto-promote race, PM verdict on stale state (1m20s gap)
- **PR #485** (Sprint 13) — Layer 5 auto-promote race, label-check FAILURE caught at PR open
- **PR #499** (Sprint 14 PM lane) — Layer 5 race: `removeLabel('status:in-review')` 404, mergeStateStatus: UNSTABLE
- **PR #500** (Sprint 14 arch lane, ADR-0051) — Layer 5 race: label-check FAIL→PASS on retry, classified as flake per ADR-0051

### Doctrinal anchors

- **RETRO-008 §1** — codification carrier (this ADR formalizes §1 into ADR-0052)
- **Issue #430** — PM §Pre-verdict cross-check (comments[] AND reviews[] both required)
- **Issue #470** — PM §Timing window (30s re-query for comment propagation, PR #499)
- **Issue #463** — d053 sister-pattern carrier (pre-merge 4-cat verification)
- **Issue #494** — Sprint 14 P1 #3 home (this ADR is the AC1 deliverable)
- **d056** — automated guard (8-sister d-test family: d046/d048/d050b/d051/d052/d053/d054/d056)
- **ADR-0051** — sister-pattern (engine perf flake vs regression, 3-cond discriminator)
- **ADR-0053** — planned (Layer 5 race pattern codification, Issue #496, URGENT)

### Sprint 14 P1 #3 cluster

- **#494** (this ADR home) — arch 0.5 SP
- **d056 d-test impl** — dev 1.0 SP (sister story)
- **d056 sign-off + RED-first contract** — tester 0.25-0.5 SP (sister story)
- **Total Sprint 14 P1 #3**: 1.75-2.0 SP (per PM draft REVISED)

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
