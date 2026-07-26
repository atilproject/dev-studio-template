# ADR-0078: Deploy FAILURE Root Cause Analysis + Workflow Fix Path

> **Status**: PROPOSED (draft, awaiting owner ratification per ADR-0012 birth contract)
> **Date**: 2026-07-26
> **Author**: @architect (cycle ~#3968Q+901, post-PR #222 cluster-squash #33 TERMINAL)
> **Sprint**: Sprint 34 W4 post-terminal
> **Reviewer**: @human (owner approval gate per ADR-0031)
> **Sister-ADR**: AtilCalculator (no ADR mirror — doctrine amendment only, sister-pattern single-repo)
> **Supersedes**: NONE (this is a NEW root-cause-analysis + fix-path ADR; amends the prediction-error in ADR-0077 §Consequences.Positive via §Cross-references pointer)

## Context

### Problem statement

`Deploy to production` workflow on `atilproject/dev-studio-template` has been failing **persistently** across all 6 PRs in the Sprint 34 W3+W4 forward-port (PR #217, #218, #219, #220, #221, #222). The failing anchor is **NOT** in `scripts/deploy-runner.sh` content — it is in **repository Variables configuration** (Settings → Secrets and variables → Actions → Variables).

### Investigation ground truth

| Commit | PR | Deploy run id | Deploy conclusion | deploy-runner.sh exit |
|---|---|---|---|---|
| `55cb3dc5` (PR #217) | row 013 bootstrap-project-board.sh PATCH-FORWARD | 30197913206 | FAILURE | exit 3 (SERVICE_NAME required) |
| `e922adc8` (PR #218) | ADR-0077 amendment | 30199180291 | FAILURE | exit 3 (SERVICE_NAME required) |
| `b6a61681` (PR #219) | row 014 claim-next-ready.sh + d031 amend | 30204388833 | FAILURE | exit 3 (SERVICE_NAME required) |
| `ebbfe03a` (PR #220) | row 015 cross-repo-close.sh PATCH-FORWARD | 30205310769 | FAILURE | exit 3 (SERVICE_NAME required) |
| `f9c399f3` (PR #221) | row 016 cross-repo-scan.sh byte-equivalence | 30206182520 | FAILURE | exit 3 (SERVICE_NAME required) |
| `f629901e` (PR #222) | row 017 deploy-runner.sh DIVERGENT (ADR-0077) | 30207015557 | FAILURE | exit 3 (SERVICE_NAME required) |

**Deploy run 30207015557 log @ 14:53:08Z** (latest, PR #222 squash):
```
env:
  SERVICE_NAME:       <BLANK>
  MODULE_PATH:        <BLANK>
  DEPLOY_PORT:        <BLANK>
  HEALTHZ_PATH:       <BLANK>
  PROD_HOSTNAME:      <BLANK>
[2026-07-26T14:53:08Z] ERROR: SERVICE_NAME required (e.g., myapp-web) 3
##[error]Process completed with exit code 3.
```

### Root cause

`.github/workflows/deploy.yml` (lines 41-49) reads 5 env vars from **repository Variables** per ADR-0047 §Decision.1 env-var table:
```yaml
env:
  SERVICE_NAME:   ${{ vars.SERVICE_NAME }}
  MODULE_PATH:    ${{ vars.MODULE_PATH }}
  DEPLOY_PORT:    ${{ vars.DEPLOY_PORT }}
  HEALTHZ_PATH:   ${{ vars.HEALTHZ_PATH }}
  PROD_HOSTNAME:  ${{ vars.PROD_HOSTNAME }}    # optional, warn-only
```

**The 5 repository Variables for `atilproject/dev-studio-template` are NOT CONFIGURED.** The workflow therefore injects BLANK values into the deploy job environment, and `scripts/deploy-runner.sh` correctly exits with code 3 per ADR-0047 fail-loud semantics ("ERROR: SERVICE_NAME required").

This is a **pre-existing infrastructure gap** that has been failing since at least PR #217 (cluster-squash #28). It is NOT introduced by Sprint 34 forward-port work, and it is NOT a Sprint 33 amendment regression.

### Why this matters now

ADR-0077 §Consequences.Positive claimed:
> "Deploy to production workflow failure anchored to row 017 forward-port resolution (closes the Deploy FAILURE loop)"

This prediction was **INCORRECT**. The divergence in `scripts/deploy-runner.sh` content between AtilCalculator (v9.1 hardcoded, 690 lines) and the template (env-driven, 294 lines per ADR-0047) is **orthogonal** to the repo Variables configuration gap. Row 017 forward-port preserved the divergent aspect (template keeps env-driven pattern; AtilCalc keeps v9.1 hardcoded), which is correct per ADR-0077 — but it was never going to fix Deploy FAILURE because Deploy FAILURE is not a deploy-runner.sh content issue.

**Architect honesty correction (cycle ~#3968Q+685 doctrine extended to cycle ~#3968Q+901):** When an ADR §Consequences section makes a prediction about side-effect resolution (e.g., "this PR closes loop X"), that prediction must be **verified post-merge** by re-querying the loop-X status. Predictions that turn out to be wrong should be **flagged** in a follow-up ADR (this ADR) — NOT silently dropped or assumed-correct.

## Decision

### Amend ADR-0077 §Consequences.Positive (prediction-error flag)

The relevant sentence in ADR-0077 §Consequences.Positive:
> "Deploy to production workflow failure anchored to row 017 forward-port resolution (closes the Deploy FAILURE loop)"

is **WRONG**. Replace it with a pointer to this ADR (ADR-0078) for the actual root cause + fix path.

The architectural correctness of ADR-0077 (preserved-divergent-aspect for deploy-runner.sh content) is **NOT** in question. The error was in the §Consequences prediction, not the §Decision amendment.

### Root cause classification

`Deploy to production` FAILURE = **infrastructure configuration gap** (repo Variables NOT configured), NOT code divergence, NOT Sprint 33 amendment regression, NOT row 017 forward-port issue.

| Category | Diagnosis |
|---|---|
| **Code content** (`scripts/deploy-runner.sh`) | CORRECT — template env-driven per ADR-0047; AtilCalc v9.1 hardcoded per ADR-0077 preserved-divergent-aspect |
| **Workflow content** (`.github/workflows/deploy.yml`) | CORRECT — reads `${{ vars.* }}` per ADR-0047 §Decision.1 |
| **Repository Variables** | **MISSING** — 5 vars NOT configured in atilproject/dev-studio-template Settings |
| **Repository Secrets** | N/A — env-var pattern uses Variables (not Secrets) per ADR-0047 §Decision.1 |
| **Self-hosted runner** (`[self-hosted, Linux, X64, atilcan]`) | AVAILABLE — runs-on label correct per AC3 |

### Fix path (OWNER-GATED)

Per file ownership matrix (CLAUDE.md §File ownership matrix): `.github/workflows/`, secrets, branch protection = **HUMAN ONLY**. Agents propose via PR; owner is the only agent who can modify these.

The fix is:

1. Owner navigates to `https://github.com/atilproject/dev-studio-template/settings/variables/actions`
2. Owner creates 5 repository Variables:
   - `SERVICE_NAME` = `dev-studio-template` (or actual service name)
   - `MODULE_PATH` = `src/` (or actual module path)
   - `DEPLOY_PORT` = `<port>` (actual deploy port)
   - `HEALTHZ_PATH` = `/healthz` (actual health check path)
   - `PROD_HOSTNAME` = `<hostname>` (optional, warn-only per ADR-0047)
3. Owner triggers a no-op commit (or `gh workflow run deploy.yml`) to re-run Deploy workflow
4. Deploy workflow should now pass (exit 0 from deploy-runner.sh after SERVICE_NAME validation)

**Alternatively**: Owner can modify `deploy.yml` to provide fallback defaults for the 4 required vars (`${{ vars.SERVICE_NAME || 'dev-studio-template' }}`). This is a workflow modification, also HUMAN ONLY.

### Cross-cutting observation: Deploy FAILURE has been silently failing for 6 PRs

Per cycle ~#3968Q+414 PR-self-blocking CI doctrine VALIDATED on PR #216 cluster-squash #27:
- Deploy FAILURE is "PR-self-blocking" in the sense that it would block a squash-merge IF Deploy were a required check
- In current state, Deploy FAILURE is observed on the **post-squash main branch push** (not on the PR itself)
- This means Deploy FAILURE has been **silently accumulating** across all 6 W3+W4 PRs without blocking forward-port

**New doctrine consideration (cycle ~#3968Q+901):** Should Deploy FAILURE on post-squash main be **owner-paged** (TIER 1 escalation) automatically? The orchestrator's TIER 1 escalation to owner (cycle ~#3968Q+902) is the right pattern. Codifying it as automatic owner-page-on-Deploy-FAILURE is a follow-up ADR (potential ADR-0079, deferred to next sprint).

## Consequences

### Positive

- ADR-0078 diagnoses the Deploy FAILURE root cause accurately (repo Variables BLANK)
- ADR-0077 §Consequences.Positive prediction-error flagged (architect honesty correction cycle ~#3968Q+685 extended)
- Owner has clear fix path (5 repo Variables to configure + alternative deploy.yml fallback defaults)
- Cycle ~#3968Q+414 PR-self-blocking CI doctrine EXTENDED to cover post-squash Deploy FAILURE silent-accumulation pattern
- Sprint 34 W4 forward-port 5/5 SHIPPED-functional ✅ TERMINAL is NOT invalidated by Deploy FAILURE (the FAILURE is orthogonal to the forward-port correctness)

### Negative

- ADR-0078 itself is documentation-only (no code change) — by design per ADR-0012 file ownership matrix (architect owns docs/decisions/)
- Owner ratification required per ADR-0031 (sister-pattern to ADR-0073 ratification)
- Sprint close ceremony (#1227) STILL PARKED — now triple-gated on S34-004 + S34-006 + ADR-0079 (this ADR's) owner Variables config
- 6 consecutive Deploy FAILUREs across W3+W4 forward-port will persist until owner takes action

### Neutral

- ADR-0077 §Decision amendment (preserved-divergent-aspect for deploy-runner.sh content) is **NOT** in question
- ADR-0077 §Consequences.Positive prediction-error is **only** about side-effect resolution (Deploy FAILURE), not about the core amendment
- ADR-0078 can be merged independently of owner Variables config (it's documentation, not a code fix)

## Implementation

### Files

| File | Change |
|---|---|
| `docs/decisions/ADR-0078-deploy-failure-root-cause-analysis.md` | NEW (this ADR) |
| `docs/decisions/INDEX.md` | +1 line entry (Cadence Rule 1 atomic per ADR-0055 §1) |

### Pre-merge verification

- [ ] Lane 2 docs verdict 9-Lens per ADR-0045 (architect self-verify)
- [ ] Cross-reference ADR-0077 §Consequences.Positive (verify prediction-error annotation accurate)
- [ ] Cross-reference ADR-0047-deploy-automation-pattern (verify env-var pattern matches)
- [ ] Cross-reference cycle ~#3968Q+414 PR-self-blocking CI doctrine (verify Deploy FAILURE classification)
- [ ] Cadence Rule 1 atomic per ADR-0055 §1 (ADR + INDEX.md same commit)

### Cross-repo doctrine preservation

- cycle ~#3968Q+685 architect honesty correction EXTENDED to prediction-error flagging (this ADR)
- cycle ~#3968Q+414 PR-self-blocking CI doctrine EXTENDED to post-squash Deploy FAILURE silent-accumulation pattern
- cycle ~#3968Q+902 orchestrator TIER 1 owner escalation VALIDATED on Deploy FAILURE (model for future automatic owner-page)
- cycle ~#3968Q+407 55th conditional preservation VALIDATED on PR #222 (3 verdict-by:labels PRESERVED post-cleanup)
- cycle ~#3968Q+685 STAGGERED-ARCH-LED 17th instance VALIDATED on PR #222 (arch verdict 14:50:30Z → squash 14:52:59Z = 2m29s)
- cycle ~#3968Q+311+22 IMMEDIATE 5-flag atomic Lane 3 chain (15th instance) VALIDATED on PR #222
- cycle ~#3968Q+3258 STANDALONE cluster-squash pattern VALIDATED on cluster-squash #33 (PR #222)
- cycle ~#3968Q+460 cross-repo scope verification PRESERVED (ADR-0078 scoped to atilproject/dev-studio-template)
- cycle ~#3968Q+666/667 peer-poke.sh path resilience PRESERVED (cycle ~#3968Q+901 orchestrator RCA ACK + #902 duplicate ACK)

### Cross-references pointer to ADR-0077 §Consequences.Positive

When the ADR-0078 INDEX entry is added, the ADR-0077 INDEX entry should add a pointer:
> "⚠️ §Consequences.Positive 'Deploy to production workflow failure anchored to row 017 forward-port resolution' prediction was INCORRECT — see ADR-0078 for actual root cause (repo Variables BLANK). The §Decision amendment (preserved-divergent-aspect for deploy-runner.sh content) is unaffected."

(This pointer is documentation-only and does not require a code change to ADR-0077 itself.)

## Sister-pattern

- Sprint 33 Path A v26 cross-repo forward-port (WP5 #1121)
- ADR-0073 ratification cycle ~#3760 (owner-ratification close pattern)
- ADR-0075 §B.1 amendment cycle ~#3968Q+685 (architect honesty correction baseline)
- ADR-0077 amendment cycle ~#3968Q+686 (row 017 deploy-runner.sh divergent classification)
- cycle ~#3968Q+414 PR-self-blocking CI doctrine (Deploy FAILURE classification baseline)
- cycle ~#3968Q+902 orchestrator TIER 1 owner escalation (Deploy FAILURE → owner-page pattern)