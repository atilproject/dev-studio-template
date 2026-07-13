# ADR-0050: Pre-merge 4-cat Verification (d053) — Programmatic Enforcement of ADR-0012 Invariant

- **Status**: Proposed
- **Date**: 2026-06-26
- **Deciders**: @architect + @developer (impl) + @tester (sign-off) + @human-owner (`.github/workflows/` territory)
- **Closes**: RETRO-007 watchlist entry #3 (§Pre-merge 4-cat verification), Sprint 13 P1 critical path
- **Sister-patterns**: ADR-0012 (4-cat invariant), ADR-0015 (atomic 4-flag handoff), ADR-0049 (3-layer d-test defense), d046/d048/d050b/d051/d052 sister-family

## Context

Sprint 12 produced **6 arch-related workflow regressions in 24 hours** (close.md §Doctrinal carry-forwards #3):

| Issue | Layer | Root cause | 4-cat gap |
|---|---|---|---|
| #436 | Layer 5 | `context.event.action` TypeError | None (workflow bug, not 4-cat) |
| #439 | Layer 4 | Same TypeError, sister-bug | None (workflow bug) |
| #441 | Layer 4 | Closing backtick dropped, JS SyntaxError | None (workflow bug) |
| #448 | Layer 5 | `addLabel` (singular) → `addLabels` (plural) | None (workflow bug) |
| #459 | Layer 1 (soul file) | orchestrator.md §Dispatch Discipline missing RETRO-005 #26 cite | None (doctrinal, not 4-cat) |
| **PR #450** | **PR-level 4-cat** | **d-test PR with type:bug + agent:developer, but missing needs-tester-signoff at squash time** | **4-cat gap caught at squash, not at PR open** |

**Pattern**: the existing `.github/workflows/label-check.yml` (ADR-0012) catches **presence** of 4-cat labels (does each category exist?), but does NOT catch **doctrinal correctness** (does the label combination match the PR type/agent expectations?). PR #450's `type:bug` + missing `needs-tester-signoff` was technically 4-cat valid (4 labels present), but doctrinally wrong (type:bug without tester sign-off is a coverage gap).

**Architectural verdict gap (RETRO-006/007 cluster)**: My 9-Lens review on PR #434, PR #438 v2, PR #450 all missed the 4-cat gap because label-check.yml reported "all 4 categories present" (PASS) at the workflow level, masking the doctrinal type:bug → needs-tester-signoff rule.

## Decision

Adopt a **d-test (d053) for pre-merge 4-cat verification** that programmatically enforces **doctrinal correctness** of the 4-cat invariant, complementing the existing label-check.yml (which enforces **presence**).

### Scope

- **Trigger**: PRs touching `.github/workflows/**`, `.claude/**`, or `scripts/tests/d053-*`
- **Method**: bash script + `gh api` queries against the PR's labels
- **Output**: explicit PASS/FAIL with detailed violations + line refs
- **Exit codes**: 0 (PASS), 1 (FAIL with violations)
- **CI integration**: triggered in `Lint & Test` workflow on `paths:` matching trigger files
- **Local run**: `bash scripts/tests/d053-pre-merge-4-cat-verification.sh <PR_NUMBER>`

### Doctrinal checks (Layer 2 — beyond label-check.yml presence checks)

| Check | Rule | Violation example | Sister-pattern |
|---|---|---|---|
| **C1** | `type:bug` PRs MUST have `needs-tester-signoff` | PR #450 (caught at squash) | ADR-0012 Layer 3 |
| **C2** | `type:bug` PRs MUST have `cc:tester` | Same as C1 | ADR-0012 Layer 3 |
| **C3** | `status:ready` PRs MUST have `cc:human` (owner squash gate) | PR #458 v1 (caught manually) | ADR-0048 §Type-driven table |
| **C4** | `type:docs` PRs touching `.claude/` MUST have `agent:architect` OR `agent:product-manager` (soul-amend lane) | None observed | PR #458 sister |
| **C5** | `type:docs` PRs touching `scripts/` MUST NOT have `agent:tester` (out-of-lane, sister to C4) | None observed | Issue #412 sister |
| **C6** | PRs with multiple `agent:*` labels are dual-owned (RETRO-007 §Dual agent:* labels doctrine) | Issue #414 (PM + arch) | RETRO-007 watchlist |
| **C7** | `type:incident` PRs MUST have `priority:P0` | None observed | ADR-0012 §Priority matrix |
| **C8** | `status:in-review` PRs MUST NOT also have `status:ready` (mutual exclusion) | None observed | ADR-0012 future work |
| **C9** | Closes-anchor strict format (uppercase C + line 1 + NO trailing text) | PR #462 v1 (caught by arch 🟡 OBS) | RETRO-007 watchlist #5 |

**C1-C9 = 9 doctrinal checks**, each with sister-pattern citation. Future checks (C10+) added via ADR amendment (sister-pattern d048 TC evolution pattern).

## Rationale

### Why a d-test (not a workflow file or label-check.yml amendment)

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **d-test in scripts/tests/** (this ADR) | Local + CI run, detailed violations, exits with code, sister-pattern d046/d048/d050b/d051/d052 family | New d-test to maintain | ✅ Adopt |
| Extend `.github/workflows/label-check.yml` | Single source of truth | label-check.yml is GH Action (not bash), runs only on label events (not PR open), bot comment only (not exit code) | ❌ Rejected |
| New `.github/workflows/pre-merge-4-cat.yml` | Dedicated workflow file | `.github/workflows/` is human-only territory per CLAUDE.md §File ownership matrix, more friction | ❌ Rejected |
| Pre-commit hook (`.git/hooks/`) | Catches at commit time | Local only, doesn't catch PRs from external contributors | ❌ Rejected |

### Why 9 checks (not more, not fewer)

- **C1-C2** (type:bug + tester): highest-value catch, observed in PR #450 squash-time gap
- **C3** (status:ready + cc:human): owner squash gate, observed in PR #458 v1
- **C4-C5** (soul/lane boundaries): lane discipline enforcement, sister-pattern Issue #412
- **C6** (dual agent:* labels): RETRO-007 doctrine codification
- **C7** (type:incident + P0): priority matrix enforcement
- **C8** (status mutual exclusion): ADR-0012 future work, low-priority but easy to check
- **C9** (closes-anchor strict format): RETRO-007 watchlist #5, observed in PR #462 v1

9 checks = balance between coverage (catches all observed regressions) and maintenance burden (each check needs implementation + test).

### Why trigger on `.github/workflows/`, `.claude/`, `scripts/tests/d053-*`

- `.github/workflows/`: 5 of 6 Sprint 12 regressions touched workflows → high signal
- `.claude/`: soul amend lane (Sprint 12 P1 cluster) → high signal
- `scripts/tests/d053-*`: d-test evolution (TC additions) → catch self-regression

## Consequences

### Positive

- **Catches PR #450-class regressions at PR open** (not squash): saves 5-15 min per catch
- **Programmatic vs comment-based**: d-test exits with code, blocks CI, forces fix
- **Sister-pattern to 5-soul d-test family**: d046/d048/d050b/d051/d052 + d053 = consistent testing framework
- **Architect review burden reduced**: 9-Lens sub-check (k) JS syntactic + d053 doctrinal checks → arch reviews diff + ADR alignment, not label discipline

### Negative

- **+1 d-test (d053, ~100 LoC)** to maintain
- **+1 CI integration** (Lint & Test workflow paths trigger)
- **9 checks = 9 places to evolve** as doctrine evolves (ADR-0012 amendments → d053 TC updates)
- **`.github/workflows/` territory** for the CI integration = human-only merge per CLAUDE.md §File ownership matrix (architect + tester draft, owner merges)

### Sprint boundary

- `docs/decisions/ADR-0050-*.md` (this file) = **architect** lane
- `scripts/tests/d053-pre-merge-4-cat-verification.sh` = **developer + tester** joint (impl + d-test)
- `.github/workflows/lint-and-test.yml` (paths update) = **human-only** territory (architect + tester draft, owner merges per file ownership matrix)
- Issue #463 (arch draft, awaiting owner Sprint 13 scope ratification) = **PM** lane

## §Security (ADR-0027 threat model)

### Threat: gh API rate limit exhaustion via d053 polling

**Attack vector**: d053 polls `gh api` for PR labels on every CI run. If CI runs 100+ times/day on PRs touching trigger paths, rate limit could exhaust.

**Mitigation**: d053 reads labels from `$GITHUB_EVENT_PULL_REQUEST_LABELS` env var (set by GitHub Actions on PR events), NOT via `gh api`. No API calls during CI run. Local runs use `gh api` but are rare (≤1/day per agent).

**Residual risk**: Negligible. d053 is read-mostly (labels are public on PRs).

### Threat: d053 false positives blocking legitimate PRs

**Attack vector**: malicious PR author crafts labels to trigger d053 FAIL, blocking legitimate work.

**Mitigation**: d053 violations are EXPLICITLY listed in CI output. Owner-override path: edit `.github/workflows/lint-and-test.yml` to add `continue-on-error: true` for d053 step (sister-pattern label-check.yml owner-override for type:bug).

**Residual risk**: Low. Owner override is documented and reversible.

## §Implementation guide (ADR-0046 pattern)

### Sprint 13 P1 work breakdown

1. **ADR-0050 (this file) — 0.5 SP — architect**: ✅ Drafted
2. **d053 d-test impl — 0.5 SP — developer**: TODO: `scripts/tests/d053-pre-merge-4-cat-verification.sh` with 9 TCs (C1-C9), bash + gh API + jq
3. **d053 tester sign-off — 0.5 SP — tester**: TODO: review d053 impl, verify TCs match ADR-0050 spec, sign off via PR comment
4. **CI integration — 0.5 SP — architect + tester joint**: TODO: update `.github/workflows/lint-and-test.yml` paths trigger + d053 step invocation, owner merges (human-only territory)
5. **Issue #463 sprint commitment — 0.0 SP — PM**: TODO: PM opens Sprint 13 kickoff issue, scope ratification, links d053 work

**Total Sprint 13 P1**: 2.0 SP (arch 0.5 + dev 0.5 + tester 0.5 + integration 0.5)

### Acceptance criteria

- **AC1**: ADR-0050 Accepted (this file)
- **AC2**: `scripts/tests/d053-pre-merge-4-cat-verification.sh` implements all 9 TCs (C1-C9)
- **AC3**: `gh api repos/.../pulls/<N>` returns 9 PASS for PRs with valid 4-cat, FAIL with explicit violation list otherwise
- **AC4**: `.github/workflows/lint-and-test.yml` triggers d053 on `paths: .github/workflows/**, .claude/**, scripts/tests/d053-*`
- **AC5**: RED-first TDD: d053 TCs RED before d053 impl merged (sister-pattern ADR-0044)
- **AC6**: Issue #463 created + Closes anchor on PR for d053 impl

### Future evolution

- **C10+**: doctrinal checks added as doctrine evolves (e.g., C10 = `priority:P0` PRs require arch verdict comment, sister-pattern PR #450 retrospective)
- **d053 v2**: behavioral check (not just label presence) — sister-pattern d050b (workflow_dispatch + mock PR payload). Deferred to Sprint 14+.

## Alternatives considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **d-test (this ADR)** | Local + CI, exit code, detailed violations, sister-pattern family | New d-test to maintain | ✅ Adopt |
| Extend `.github/workflows/label-check.yml` | Single source of truth | Label-event only (not PR open), bot comment only, sister-pattern to existing pull_request_target self-test limitation | ❌ Rejected |
| Pre-commit hook | Local-only | No PR catch (external contributors) | ❌ Rejected |
| Move all label logic to Python | Avoids bash | Massive refactor, breaks sister-pattern, no benefit | ❌ Rejected |
| Static lint + content-anchor only | Cheapest | Misses 4-cat violations (Issue #440-class), misses RETRO-007 §Dual agent:* labels doctrine | ❌ Rejected |

## Open questions

- [ ] **Q1**: Should d053 also check **PR title format** (conventional commits scope)? Sister-pattern Issue #440 cascade where 4 PRs used `feat(scope):` without AC ref. Deferred to C11+ if needed.
- [ ] **Q2**: Should d053 C1/C2 allow owner-override for `type:bug` PRs? (label-check.yml allows it per ADR-0012 §Owner override). Recommend: yes, mirror label-check.yml pattern.
- [ ] **Q3**: CI integration — `paths:` trigger only, or also `pull_request_target` event? Recommend: paths only (avoids pull_request_target self-test limitation per close.md D-deviation).
- [ ] **Q4**: d053 polling — read labels from env var (no API) or always poll (consistency)? Recommend: env var for CI, `gh api` for local (graceful degradation).

## References

- ADR-0012 (4-cat invariant, base doctrine)
- ADR-0015 (atomic 4-flag handoff)
- ADR-0027 (threat model)
- ADR-0044 (TDD RED-first)
- ADR-0046 (load-bearing ADR §Implementation Guide pattern)
- ADR-0048 (Layer 5 status:ready auto-add gating)
- ADR-0049 (3-layer d-test defense, d050b framework)
- RETRO-007 watchlist entry #3 (§Pre-merge 4-cat verification)
- Sprint 12 close.md §Doctrinal carry-forwards #3
- PR #450 (type:bug + missing needs-tester-signoff squash-time catch)
- PR #458 (5-soul §Dispatch Discipline amend, sister-pattern to d053 trigger paths)
- PR #462 (closes-anchor strict format catch, sister-pattern to C9)
- d046, d048, d050b, d051, d052 (d-test sister-family)

— @architect, 2026-06-26T19:48Z, ADR-0050 Pre-merge 4-cat Verification (P1 critical path, RETRO-007 watchlist entry #3, Sprint 13 P1)