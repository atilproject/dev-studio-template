# ADR-0077: S34-002 Row 017 deploy-runner.sh Divergent Class Amendment

> **Status**: PROPOSED (draft, awaiting owner ratification per ADR-0012 birth contract)
> **Date**: 2026-07-26
> **Author**: @architect (cycle ~#3968Q+686, post-PR #217 291st-wake Lane 2 docs verdict on row 013 bootstrap-project-board.sh PATCH-FORWARD divergent class)
> **Sprint**: Sprint 34 W4 forward-port pre-stage (row 014 dispatch awaiting)
> **Reviewer**: @human (owner approval gate per ADR-0031)
> **Sister-ADR**: AtilCalculator (no ADR mirror — doctrine amendment only, sister-pattern single-repo)

## Context

### Problem statement

ADR-0075 §B.1 parity matrix classifies `scripts/deploy-runner.sh` (row 017) as **`equivalent`** class with rationale "Pure deploy helper". This classification was a **preliminary inference** at Sprint 34 W1 parity-matrix creation (cycle ~#3968Q+200 owner-directive).

During 283rd wake (cycle ~#3968Q+685), the developer agent surfaced a content-divergence finding when verifying row 012 dispatch target. Investigation revealed row 017 content is **substantively divergent**, not equivalent:

| Repo | Lines | Bytes | Pattern |
|---|---|---|---|
| AtilCalculator | 690 | 43,762 | v9.1 hardcoded SERVICE_NAME + MODULE_PATH + PORT + HEALTHZ_PATH (RCA-7/9/11/12/14 hardening baked in) |
| dev-studio-template | 294 | 14,219 | env-driven: 4 required env vars (SERVICE_NAME, MODULE_PATH, DEPLOY_PORT, HEALTHZ_PATH) per ADR-0047-deploy-automation-pattern |

Template's comment header (verbatim):
> "Sister to AtilCalculator scripts/deploy-runner.sh (v9.1) but generalized:
> - No hardcoded service name, module path, port, or healthz path
> - 4 required env vars (SERVICE_NAME, MODULE_PATH, DEPLOY_PORT, HEALTHZ_PATH)
> - 1 optional env var (PROD_HOSTNAME — warn-only validation, lens g)
> - nohup+setsid restart pattern (NOT systemctl --user) — per ADR-0047 §Decision.2"

### Trigger

PR #217 (S34-002 row 013 bootstrap-project-board.sh PATCH-FORWARD divergent) post-merge MAIN CI showed pre-existing failure on **`Deploy to production` workflow check** (cycle ~#3968Q+414 PR-self-blocking CI doctrine VALIDATED on PR #216). The failure anchor IS row 017 deploy-runner.sh — the workflow requires `SERVICE_NAME` env var per ADR-0047, but AtilCalculator's deploy-runner.sh hardcodes service paths.

Architect honesty correction (cycle ~#3968Q+685): "row 012 dispatch target was bootstrap-labels.sh (NOT deploy-runner.sh as 273rd-wake inference) — always re-query ADR-0075 §B.1 source-of-truth, not infer from prior patterns."

Orchestrator directive (cycle ~#3968Q+686, 302nd wake): "Task #134 ADR-0077 filing still in_progress — please file before rows 017 dispatch."

### Why this matters now

Without ADR-0077 amendment, row 017 dispatch will use `equivalent` lane (byte-equivalence test → byte-equivalence fail → wasted cycle + cross-repo confusion). With ADR-0077 amendment, row 017 dispatch will use `divergent` lane (PATCH-FORWARD — verify Sprint 33 amendments + env-var pattern preserved, NOT byte-equivalence test).

## Decision

### Amend ADR-0075 §B.1 row 017 classification

**Current** (cycle ~#3968Q+685 PRELIMINARY):
```
| 017 | scripts/deploy-runner.sh | equivalent | Pure deploy helper |
```

**Amended**:
```
| 017 | scripts/deploy-runner.sh | divergent  | AtilCalc has v9.1 hardcoded RCA-7/9/11/12/14 (690 lines); template env-driven per ADR-0047-deploy-automation-pattern (294 lines). Forward-port = PATCH-FORWARD, NOT byte-equivalence. |
```

### Row 017 dispatch lane (post-amendment)

| Phase | Lane | Notes |
|---|---|---|
| Dev impl | WIP lane 1 | PATCH-FORWARD: verify Sprint 33 amendments port + env-var pattern preserved |
| d-test | Lane 3 | Per ADR-0049 ≥5 TCs (Sprint 33 amendments + env-var validation) + ADR-0055 §1 atomic |
| Arch verdict | Lane 2 docs | 9-Lens per ADR-0045 — verify env-var pattern preserved (NOT a byte-equivalence test) |
| Tester sign-off | Lane 3 d-test-only | Per cycle ~#3642H |
| Owner squash | Lane ∞ | Per ADR-0031 |

### PATCH-FORWARD divergent class verification protocol (reusable for rows 014-016)

1. **MD5 byte-identical OR semantic-equivalent** check (whichever fails first wins)
2. **If MD5 differs**: identify divergence classification:
   - **equivalent**: pure refactor (comments, formatting, no semantic change) — byte-equivalence test ACCEPTABLE
   - **divergent**: semantic content differs (env-var pattern, hardcoded vs configurable, RCA hardening)
3. **For divergent class**:
   - Lane 2 docs verdict verifies env-var pattern preserved (NOT byte-equivalence)
   - d-test verifies both implementations behave equivalently under env-var input
   - Forward-port preserves the divergent aspect of canonical (AtilCalculator keeps v9.1 hardcoded; template keeps env-driven pattern)

### deploy.yml 'fail 3x pre-squash exit 3 SERVICE_NAME required' clarification

This is **CORRECT validation behavior, not bug** (cycle ~#3968Q+685):
- deploy.yml requires SERVICE_NAME env var per ADR-0047
- exit 3 = template's hardcoded failure when SERVICE_NAME is missing (fail-loud per ADR-0047)
- Pre-existing failure on `Deploy to production` workflow check is the workflow correctly validating env-var required
- Post-squash deploy.yml identical to pre-squash (impl + d-test + INDEX.md + CHANGELOG.md only)
- This will be addressed by row 017 forward-port (template → AtilCalculator deploy-runner.sh env-driven pattern port)

## Consequences

### Positive

- Row 017 dispatch uses correct PATCH-FORWARD lane (no wasted cycle on byte-equivalence failure)
- Architect honesty correction codified (cycle ~#3968Q+685 — always re-query ADR-0075 §B.1 source-of-truth, not infer from prior patterns)
- ADR-0075 §B.1 row 017 amendment provides lane-stable forward-port pattern for row 017 + rows 014-016 (Sprint 33 divergent amendments)
- Deploy to production workflow failure anchored to row 017 forward-port resolution (closes the Deploy FAILURE loop)

### Negative

- ADR-0077 itself is documentation-only (no code change) — this is by design per ADR-0012 file ownership matrix (architect owns docs/decisions/)
- Owner ratification required per ADR-0031 (sister-pattern to ADR-0073 ratification)
- Row 017 dispatch latency increase (~5min Lane 2 docs verdict extra verification for env-var pattern preservation)

### Neutral

- ADR-0075 §B.1 row 017 amendment is a **single-line classification change** (no row ordering change)
- PATCH-FORWARD divergent class protocol is reusable for row 014 (claim-next-ready.sh Sprint 33 amendments) + row 015 (cross-repo-close.sh RETRO-024) + row 016 (cross-repo-scan.sh cycle ~#3968Q+305)
- Sister-ADR pattern: AtilCalculator may file ADR-0078 (mirror) per WP5 #1121 slug-collision doctrine if needed

## Implementation

### Files

| File | Change |
|---|---|
| `docs/decisions/ADR-0077-s34-002-row-017-deploy-runner-divergent-amendment.md` | NEW (this ADR) |
| `docs/decisions/INDEX.md` | +1 line entry (Cadence Rule 1 atomic per ADR-0055 §1) |

### Pre-merge verification

- [ ] Lane 2 docs verdict 9-Lens per ADR-0045 (architect self-verify)
- [ ] Cross-reference ADR-0075 §B.1 (verify amendment is consistent)
- [ ] Cross-reference ADR-0047-deploy-automation-pattern (verify env-var pattern preserved)
- [ ] Cadence Rule 1 atomic per ADR-0055 §1 (ADR + INDEX.md same commit)

### Cross-repo doctrine preservation

- cycle ~#3968Q+685 IMMEDIATE twin-squash variant preserved
- cycle ~#3968Q+687 cross-repo push chain preserved
- cycle ~#3968Q+666/667 peer-poke.sh path resilience preserved
- cycle ~#3968Q+460 cross-repo scope verification preserved
- cycle ~#3968Q+407 conditional preservation (3 verdict-by PRESERVED doctrine)
- cycle ~#3968Q+313 lane separation preserved (docs verdict lane = architect PRIMARY)

## Sister-pattern

- Sprint 33 Path A v26 cross-repo forward-port (WP5 #1121)
- ADR-0073 ratification cycle ~#3760 (owner-ratification close pattern)
- ADR-0075 §B.1 amendment cycle ~#3968Q+685 (architect honesty correction)
- cycle ~#3968Q+414 PR-self-blocking CI doctrine (Deploy to production failure anchor)