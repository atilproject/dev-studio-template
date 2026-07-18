# ADR-0044 — Verdict-By:* SLA Scope Clarification (TDD RED exclusion)

- **Status:** Proposed (2026-06-24)
- **Date:** 2026-06-24
- **Author:** @architect
- **Supersedes:** none (extends ADR-0024 §Scope applicability with TDD RED exclusion clause)
- **Related:** ADR-0024 (stale-verdict watchdog schema), ADR-0041 (event model v8 verdict_posted kind), ADR-0042 (orchestrator role §verdict-by SLA monitoring), TD-006 (umbrella TD, partially resolved), Issue #319 (this ADR's trigger), Issue #313 (tester doctrinal gap, MERGED PR), Issue #317 (sister incident), PR #313 (TDD RED contract test)

## Context

ADR-0024 §Schema additions establishes the convention: "when an agent adds `cc:<peer>` to a PR, they MUST also add `verdict-by:<ts>` in the same atomic flip." The SLA watchdog (`scripts/agent-watch.sh` `query_stale_verdict` per ADR-0024 §Watchdog logic) fires `stale_verdict` events when the deadline passes without state change.

**Observed doctrinal gap** (per Issue #319 §Problem, tester-flagged in PR #313 21:03Z comment):

TDD RED contract PRs — tests authored + 0/N RED verified, **no impl yet** — are incorrectly subjected to the `verdict-by:<ts>` SLA. The SLA semantics assume **impl-awaiting-verdict** (review SLA). TDD RED PRs are **contract-awaiting-impl** (different lifecycle stage):

| PR state | `cc:<peer>` semantics | SLA semantics |
|---|---|---|
| **Impl-awaiting-verdict** (normal PR review) | Peer expected to post verdict | "verdict overdue" → stale_verdict event |
| **TDD RED contract-awaiting-impl** | Tester peer set on contract test, but no impl to review | "contract overdue" → **wrong wake**, owner acts unilaterally |

The TDD RED PR's actual closure mechanism is **supersede-via-impl-PR** (per #307 → #314 example): when the GREEN impl PR merges, it supersedes the RED contract PR. The contract PR is the **gate**, not the deliverable — there is no "verdict" to post on it until impl lands.

**Observed incidents**: PR #313 (tester authored d036 regression test, TDD RED, owner acted unilaterally to land), PR #317 (similar).

## Decision

**The `verdict-by:<ts>` SLA scope excludes TDD RED contract-only PRs.** A PR is a TDD RED contract-only PR if **both** of the following hold:

1. **Test-only diff**: the PR's changed files consist exclusively of files under `tests/` directory OR files matching test naming patterns (e.g., `test_*.py`, `*_test.py`, `*Test.java`, `*.test.ts`, `*.spec.ts`). No changes to `src/` or other production code paths.
2. **`contract:tdd-red` label** OR **CI status: RED on all test cases** OR **commit message contains `RED:` / `TDD-RED:` / `(TDD RED)` markers**.

When the SLA watchdog (`scripts/agent-watch.sh` `query_stale_verdict`) encounters such a PR:

- **Skip** `verdict-by:<ts>` SLA check entirely (no `stale_verdict` event)
- **Skip** `missing_expectation` warning if `cc:<peer>` is present without `verdict-by:<ts>` (the convention's purpose is to enforce SLA, and SLA is exempted)
- **DO** still emit `stale_verdict` for the GREEN impl PR when it lands (the impl PR is the verdict-bearing artifact)

### `contract:tdd-red` label (new)

| Label | Format | Meaning | Set by | Removed by |
|---|---|---|---|---|
| `contract:tdd-red` | static | Marks PR as TDD RED contract (tests authored, impl absent) | Author of PR (tester in current workflow per RETRO-005 #4) | Merged GREEN impl PR (auto-removal by `gh pr edit` in scripts/agent-watch.sh) OR author manually |

The label is **declarative** (author opts in). The label is **enforced** by the watchdog scope rule above. CI does not auto-set the label — that's the author's responsibility when authoring a contract test PR.

### Scope rule (canonical)

```
if pr has `contract:tdd-red` label:
    skip verdict-by SLA check (no stale_verdict, no missing_expectation)
elif pr diff is test-only AND CI is RED on all TCs:
    skip verdict-by SLA check (same)
else:
    apply verdict-by SLA check (stale_verdict + missing_expectation as per ADR-0024)
```

The `elif` clause catches authors who forget the `contract:tdd-red` label but whose PR is still TDD RED (defense in depth). The CI status check requires reading the PR's check runs, which is already part of `gh pr list --json` extensions.

### Interaction with ADR-0041 (verdict_posted event)

ADR-0041 introduces the `verdict_posted` event kind (Phase 0 = `scripts/agent-watch-verdicts.sh` standalone, MERGED; Phase 1 = `agent-watch.sh` v8 native extension, dev pending). The verdict_posted event fires when a peer posts a verdict comment on a PR.

**Question**: should verdict_posted also be exempt for TDD RED contract PRs?

**Answer**: NO. `verdict_posted` is the **positive-direction** twin of `stale_verdict` (per ADR-0041 §Sister to ADR-0024): it captures "verdict was posted" not "verdict is overdue". If a tester peer posts a verdict on a TDD RED contract PR (e.g., "contract looks correct, awaiting impl GREEN"), that IS a valid verdict signal — the contract PR is reviewable for its test cases. The verdict_posted event should still fire (and wake the author).

Only `stale_verdict` (the SLA-pressure direction) is exempted, not `verdict_posted` (the signal-direction).

### Interaction with ADR-0021 (docs PR convention)

ADR-0021 already exempts `type:docs` PRs without `## Peer review rationale` section from `stale_*` wakes. The TDD RED exclusion is a **second exemption** layered on top:

- `type:docs` + no rationale → no wake (ADR-0021)
- `type:feature` + `contract:tdd-red` → no wake (this ADR-0044)
- `type:feature` + normal impl PR → wake if verdict overdue (ADR-0024)

The two exemptions are orthogonal and compose cleanly.

## Rationale

**Why exclude TDD RED contract PRs from SLA pressure:**

1. **Semantic mismatch**: `verdict-by:<ts>` is a "review SLA" timer. TDD RED PRs have no review deliverable until impl lands — the SLA is measuring something that doesn't exist yet.
2. **Owner unilateral action pattern**: observed in PR #313 (owner acted unilaterally because SLA fired on contract PR with no impl to review). This is a deadlock-breaker hitting the wrong deadlock — the SLA is firing on a non-actionable peer queue, so owner is forced to act without proper verdict.
3. **Supersede-via-impl-PR pattern is the real closure**: TDD RED PRs close when their GREEN impl PR lands (per #307 → #314 example). The contract PR is a gate, not a deliverable. The SLA timer measures the wrong artifact.

**Why a new ADR (not an amendment to ADR-0024):**

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **A) Amend ADR-0024 §Scope applicability** | Single ADR to reference | Conflates schema (ADR-0024) with scope (this concern); harder to discover; couples unrelated decisions | ❌ Rejected — separation of concerns |
| **B) New ADR-0044** (chosen) | Clear separation: ADR-0024 = schema, ADR-0044 = scope | One more ADR file | ✅ **Adopted** — schema vs scope are distinct concerns, and discoverability improves when scope changes don't touch schema |
| **C) Inline in scripts/agent-watch.sh code comment** | Zero docs overhead | Doctrine buried in code; not reviewable as PR; can't ack via ADR workflow | ❌ Rejected — ADRs are the doctrine-tracking mechanism per CLAUDE.md |

### Alternatives considered

- **D) Suppress SLA for ALL PRs authored by `@tester`** — over-broad: testers author both contract PRs (TDD RED) and impl PRs (e.g., test infra changes). The discrimination is by PR type, not author.
- **E) Require `contract:tdd-red` label to be CI-auto-set** — pushes label-setting burden onto CI, but CI doesn't know "this PR is a TDD RED contract" vs "this PR has failing tests because of a regression". Author declaration is more reliable.
- **F) Use existing `needs-tester-signoff` label to detect TDD RED** — `needs-tester-signoff` is set by the PR author when they want tester review. TDD RED PRs have `needs-tester-signoff` set (tester is the peer), but so do many non-TDD-RED impl PRs. The label is not discriminating.
- **G) No SLA on PRs with only test files (without `contract:tdd-red`)** — author might accidentally omit `contract:tdd-red`; the `elif` clause (CI RED on all TCs) catches this. Both are needed for defense in depth.

## Consequences

### Positive

- **Closes doctrinal gap** for TDD RED contract PRs — SLA timer no longer fires on non-actionable peer queues
- **Reduces tester-pinged incidents** — acceptance criterion in Issue #319: "Tester-pinged incidents drop from 1-2/sprint to 0/sprint"
- **Supersede-via-impl-PR pattern remains the closure mechanism** — no regression in the established workflow
- **Clean separation of concerns** — ADR-0024 (schema) + ADR-0044 (scope) can evolve independently
- **Discovery via Issue #319 + Issue #313** — tester-driven doctrinal feedback loop, not architect-imposed

### Negative / risks

- **Script change complexity** — `query_stale_verdict` needs to read `contract:tdd-red` label + check PR diff + check CI status. Estimated ~30 LoC + 1-2 d-tests per Issue #319 §Owner.
- **Author discipline** — `contract:tdd-red` is author-set; relies on author declaring correctly. The `elif` (CI RED on all TCs) is defense in depth.
- **Label lifecycle** — `contract:tdd-red` needs auto-removal when GREEN impl PR lands. Orchestrator script change must handle this (similar to PR-close label cleanup per `.github/workflows/label-cleanup.yml`).
- **Test infra confusion** — what if a PR is a test-only change to test infrastructure (e.g., adding a new d-test helper)? Such PRs aren't TDD RED — they're impl PRs that happen to only touch tests. The label declaration disambiguates.

### Neutral

- No new ADRs required (this ADR is the scope clarification)
- No changes to ADR-0024 schema (separation preserved)
- No changes to ADR-0041 verdict_posted event (scope exemption applies only to SLA direction, not signal direction)
- No changes to ADR-0021 docs PR convention (orthogonal exemption)

## Implementation

1. **This PR (architect-authored)**: file ADR-0044, update `docs/decisions/INDEX.md` row
2. **Owner-gated follow-up** (if soul amendment needed for `contract:tdd-red` doctrine — owner-only territory per file ownership matrix): update `.claude/agents/tester.md` §Standard Workflows to reference `contract:tdd-red` label set on TDD RED contract PRs
3. **Orchestrator handoff** (Sprint 7 P2): update `scripts/agent-watch.sh` `query_stale_verdict` per §Scope rule. Implement label lifecycle (auto-remove `contract:tdd-red` on GREEN impl PR merge). **Ownership split** (per orchestrator.md §Hard Rules + CLAUDE.md §File ownership matrix, scripts/ = developer territory): doctrinal spec owner = @orchestrator (the §Scope rule if/elif/else logic + Issue #319 §Owner doctrinal ownership); code owner = @developer (scripts/agent-watch.sh + d-test). Sister-pattern: #296 / PR #383 (peer-poke.sh — orchestrator-owned spec, dev-owned impl).
4. **Developer companion** (Sprint 7 P2): d-test for `contract:tdd-red` exemption scenarios — 3 TCs (TDD RED + label → no wake, TDD RED + CI RED → no wake, normal PR + verdict overdue → stale_verdict fires)

## Acceptance criteria

- [ ] ADR-0044 merged to main
- [ ] Issue #319 closed (this ADR is the doctrine deliverable)
- [ ] `scripts/agent-watch.sh` updated with TDD RED exclusion (dev-owned code, Sprint 7 P2; per §Implementation step 3 ownership split)
- [ ] d-test for exemption scenarios passes (Sprint 7 P2)
- [ ] Tester-pinged incidents drop from 1-2/sprint to 0/sprint (validation period: Sprint 7)
- [ ] No regression in normal impl-awaiting-verdict SLA enforcement
- [ ] Supersede-via-impl-PR pattern remains the closure mechanism for TDD RED PRs

## References

- Issue #319 (this ADR's trigger, architect-owned)
- Issue #313 (tester doctrinal gap, MERGED via PR)
- Issue #317 (sister incident)
- Issue #312 (P0 RCA — verdict-missed, closed by ADR-0041 Phase 0)
- ADR-0024 (stale-verdict watchdog schema — `verdict-by:<ts>` + `stale_verdict` event)
- ADR-0041 (event model v8 — `verdict_posted` kind, Phase 0/1 split)
- ADR-0042 (orchestrator role — verdict-by SLA monitoring)
- PR #313 (d036 regression test, TDD RED contract that triggered the doctrinal gap)
- PR #317 (sister incident)
- RETRO-005 candidate #4 — PM status:ready flip discipline (sister doctrinal lesson)
- File ownership matrix: CLAUDE.md §File ownership matrix (`.claude/` = human only, ADR = architect-owned)
- Issue #307 → PR #314 example: supersede-via-impl-PR closure pattern

## See also

- **ADR-0046** (Sprint 9 P1, PR #409 in-review) — Load-Bearing ADR §Implementation Guide Pattern. Companion to this ADR; provides §A literal jq filter, §B ownership-split decision tree, §C companion-ADR template. Cited because this ADR is load-bearing and ADR-0046 codifies the intent-vs-literal precision standard discovered in RETRO-005 #19 (Issue #388 audit).

---

🤖 Architect ADR draft @ 2026-06-24T16:42Z — Sprint 7 P2 candidate, drafted during Sprint 6 wait time