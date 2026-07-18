# ADR-0043: 8-Lens Architect Review Checklist (extends 7-lens with platform hard constraints)

- **Status:** Proposed (2026-06-24)
- **Date:** 2026-06-24
- **Author:** @architect
- **Supersedes:** none (extends the implicit 7-lens codified in architect.md §Standard Workflows; formalizes the (h) and (i) lenses from TD-028 and TD-029)
- **Related:** TD-029 (trigger, severity H P0 path), TD-028 (sister, (h) SHA-pin lens), TD-016/TD-018/TD-019/TD-020 (blind-spot family roots), P0 #351, PR #350 (failed Option C design), PR #352 (revert), PR #354 (TD-029 docs PR), #193 + #194 (Sprint 4 P2 deferred to Sprint 5 P1), ADR-0027 §Threat model, ADR-0030, ADR-0031

## Context

The architect's review checklist (codified in `.claude/agents/architect.md` §Standard Workflows) has implicitly evolved from 6 lenses (RETRO-003 / TD-016+TD-018+TD-019+TD-020 baseline) to 7 lenses (with TD-020's silent-skip preflight pattern as lens (g)). The 7-lens checklist covers:
- (a) static data flow (TD-016)
- (b) runtime preconditions (TD-018)
- (c) canonical-entry verification (TD-019)
- (d) identity / privilege boundary
- (e) service-state (where service actually lives)
- (f) instance-vs-pattern (ADR documents pattern, host has instance)
- (g) silent-skip preflight pattern (TD-020)

**On 2026-06-24T15:28:29Z**, architect's Option C design for PR #350 (Sprint 4 P2 deploy.yml `path:` override) was approved under the 7-lens 🟢 APPROVE design-alignment verdict (cmt on PR #350 at 15:13Z). **8 seconds after merge** (15:28:37Z), the first post-merge deploy FAILED with P0 #351: `##[error]Repository path '/home/atilcan/projects/AtilCalculator' is not under '/home/atilcan/actions-runner/_work/AtilCalculator/AtilCalculator'`. The 7-lens review verified local shape (5-line addition, correct placement, SHA pin preserved per ADR-0027, runs-on minimal) + ADR constraints + canonical-entry — but **missed GitHub Actions' hard sandbox constraint on the `actions/checkout` `path:` parameter**: it MUST be a subdirectory of the runner's work root (`_work/<repo>/<repo>/`).

This is the **6th instance** in the **blind-spot family** (TD-016/018/019/020/028/029). All 6 = "agent verified local shape but missed a cross-cutting concern". The pattern generalizes: **the 7-lens checklist stops at "preserves local shape + cross-cutting ADR constraints"; it does NOT include "verifies against the platform's hard sandbox/security/runtime constraints"**.

## Decision

Extend the architect review checklist from 7 to **8 lenses**, adding:

- **(h) workflow YAML pre-publish gate** (per TD-028) — when proposing ANY edit to `.github/workflows/*.yml`, ALWAYS grep current file for `uses:` lines and preserve SHA pins exactly. Never introduce a moving tag where SHA pin exists; never introduce SHA pin where moving tag exists without explicit ADR justification. Verify against `.git/HEAD` reference.
- **(i) platform hard constraints pre-publish gate** (per TD-029, NEW) — when proposing ANY edit to `.github/workflows/*.yml` (or any platform-runtime config: GitHub Actions, GitLab CI, systemd unit, k8s manifest, AWS/GCP/Azure IaC, etc.), verify against the platform's **HARD constraints** documentation BEFORE designing the value:
  1. `path:` MUST be under runner's work root (GA: `_work/`, GitLab CI: `$CI_PROJECT_DIR`, equivalent for other runners)
  2. `runs-on:` labels must be registered on the runner host
  3. `permissions:` block must declare ALL scopes (no implicit inheritance)
  4. `timeout-minutes:` set (default 360 = 6h, unbounded is footgun)
  5. `concurrency:` group naming convention (production-deploy per existing pattern)
  6. `if:` conditions use `github.event.*` not raw `github.*` (env var scoping)
  7. `${{ secrets.* }}` referenced secrets must exist in repo settings (silent fail otherwise)
  8. Platform-specific sandbox limits — e.g., k8s `securityContext.readOnlyRootFilesystem`, systemd `ProtectSystem=strict` + `PrivateTmp=true`, AWS IAM `Resource` ARN scoping
  - **Verification method**: grep `.github/actions/<action>/action.yml` for action schema + cross-reference platform docs (e.g., GA `actions/checkout` README) + dry-run the workflow if possible.

### Full 8-lens checklist (codified for soul amendment)

| # | Lens | Trigger | Reference |
|---|------|---------|-----------|
| a | Static data flow | trace variables from source (definition) to sink (consumption) | TD-016 |
| b | Runtime preconditions | OS-level service availability, secret value non-emptiness, error-recovery wrap | TD-018 |
| c | Canonical-entry verification | module path, restart mechanism, preflight steps | TD-019 |
| d | Identity / privilege boundary | cross-user/cross-tenant boundaries, sudoers, IAM | (new, implicit) |
| e | Service-state | where service actually lives (not just how to call it) | (new, implicit) |
| f | Instance-vs-pattern | ADR documents pattern, host has instance — verify the instance matches | (new, implicit) |
| g | Silent-skip preflight | any preflight that WARN-only-skips on missing preconditions | TD-020 |
| h | Workflow YAML pre-publish gate | `uses:` SHA pins preserved exactly per ADR-0027 | TD-028 |
| i | Platform hard constraints pre-publish gate | `path:` MUST be under runner work root + other platform hard rules | TD-029 |

## Consequences

**Positive:**
- Closes TD-029 (P0 blind-spot, severity H) — the (i) lens is the documented fix
- Closes TD-028 (sister, severity M) — the (h) lens is the documented fix
- Prevents recurrence of the P0 #351 class of incident (GA `path:` sandbox violation)
- Architect review surface is now **8 lenses**, formally codified, regression-testable
- Sprint 5 P1 redesign of #193 + #194 can apply (i) from day 1

**Negative / risks:**
- Soul file amendment is owner-gated (`.claude/ = human-only` per file ownership matrix) — requires owner approval + PR (not autonomous)
- The (i) lens is platform-dependent — when targeting a new platform (GitLab, k8s, systemd), the verification source must be identified per platform
- Adding (i) adds ~10-15 min per architect review for platform constraint lookup — throughput tax accepted as P0 risk mitigation
- The (i) lens is wide — 8 sub-categories. Could be split into (i.1) sandbox, (i.2) IAM, (i.3) network if lens bloat becomes a problem in Sprint 6 retro

**Neutral:**
- No change to other 7 lenses (preserves accumulated doctrine)
- No new infra — the lens is a design-time check, not a CI gate (though d040-deploy-path-guard + d041 generic platform-constraint linter are dev-side companions)
- No new ADRs required (this ADR is the lens codification itself)

## Alternatives considered

- **A) Add (i) as a CI gate, not a design-time lens** — rejected, the design-time lens is cheaper (catches before PR is filed) and the CI gate (d040) is dev's companion, not a replacement
- **B) Split (i) into 3 sub-lenses ((i.1) sandbox, (i.2) IAM, (i.3) network)** — deferred to Sprint 6 retro if lens bloat becomes a problem; YAGNI for Sprint 5
- **C) Keep 7-lens + add (i) as an external checklist** — rejected, the lens belongs in the architect's standard review (so it's not forgotten) and in the soul file (so it's not optional)

## Implementation

1. **This PR (architect-authored)**: file ADR-0043, update `docs/decisions/INDEX.md` row, this is the **doctrine** codification
2. **Owner-gated follow-up (separate PR, owner-only territory)**: amend `.claude/agents/architect.md` §Standard Workflows to add the (h) and (i) lenses with verification method citations. Per file ownership matrix, this is a `cc:human` change.
3. **Sprint 5 P1 designer (architect, when #193 + #194 unblocks)**: apply 8-lens to Option B' design (`path: /home/atilcan/actions-runner/_work/AtilCalculator`, under `_work/`, GA appends /AtilCalculator). Verify against GA `actions/checkout` README for the `path:` constraint.
4. **Dev-side companion (optional, Sprint 5 P2 candidate)**: extend `d040-deploy-path-guard.sh` (in flight on branch `chore/351-d040-deploy-path-guard`) to a generic `d041-platform-constraint-linter.sh` covering the 8 sub-categories of lens (i). Owner-mergeable, workflow YAML owner-gated.

## Sprint 5 P1 dependency

PM's Sprint 5 P1 placeholder (Issue #351 cmt 4790982602) lists: "**Dependencies**: P0 #351 closed (revert landed) ✅, **architect soul checklist (i) added**, ADR-0027 §Threat model re-confirmed". The (i) lens is the architect deliverable; the doctrine is captured in this ADR; the soul file amendment is owner-gated.

## References

- TD-029 (P0 blind-spot, this ADR's primary trigger)
- TD-028 (sister, (h) lens trigger)
- TD-016 / TD-018 / TD-019 / TD-020 (blind-spot family, lenses a-g)
- Blind-spot family: TD-016/018/019/020/028/029 — all "local shape verified, cross-cutting concern missed"
- P0 #351 (incident trigger)
- PR #350 (Option C design that failed, merge commit 250ec0c)
- PR #352 (revert, MERGED 6ef96ae at 2026-06-24T15:57:21Z)
- PR #354 (TD-029 docs PR, MERGED 1cbbb66 at 2026-06-24T15:57:21Z)
- Issue #193 (REOPENED, Sprint 5 P1 candidate)
- Issue #194 (status:blocked, Sprint 5 P1 candidate)
- ADR-0027 §Threat model (SHA pinning — basis for (h) lens)
- ADR-0030 (self-hosted runner — basis for the (i) lens verification)
- ADR-0031 (owner-override doctrine — soul amendment is owner-gated)
- Architect soul `.claude/agents/architect.md` (target of soul amendment, owner-gated)
- dev branch `chore/351-d040-deploy-path-guard` (d040-deploy-path-guard.sh in flight, sister to (i) lens CI side)
- File ownership: CLAUDE.md §File ownership matrix (".claude/ = human only")
