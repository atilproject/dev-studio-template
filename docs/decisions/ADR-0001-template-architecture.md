# ADR-0001: Template Architecture — Single-Repo, Placeholder Parameterization, gh-Distribution

- **Status**: Proposed
- **Date**: 2026-06-29
- **Deciders**: @architect (doctrine spec), @product-manager (sponsor — Sprint 21 ratification chain owner), @developer (init script impl — S21-003 + S21-004), @tester (d070-template-render d-test sign-off per ADR-0044 RED-first), @atilcan65 (owner squash gate per Issue #627 + file ownership matrix)
- **Closes**: Issue #627 (Sprint 21 kickoff), Sprint 21 STORY-S21-016 (Sprint 21 E8 ADR-0001 template-architecture)
- **Sister-patterns**: ADR-0012 (4-cat label invariant), ADR-0014 (PROJECT_TOKEN secret + secret-canary workflow), ADR-0016 (public-by-default), ADR-0045 (9-Lens pre-publish gate), ADR-0049 (d-test framework — d070-template-render sister-pattern), ADR-0055 (Cadence Rule 1 atomic — this ADR + INDEX.md in same PR), RETRO-014 §6 (Sprint 19 SKIPPED + Sprint 20 PROJECT CLOSE sequencing), Issue #113 (label-authority doctrine — labels > body), Issue #238 (no-standby doctrine)

> **Doctrinal home note**: This is the **canonical home** for the template architecture decision that closes Sprint 21 STORY-S21-016. **Why ADR-0001 not ADR-0061**: ADR-0001 was reserved (gap number in the ADR registry as of 2026-06-29 — no `ADR-0001-*.md` file exists; lowest-numbered ADR is ADR-0002 Autonomy Loop). Per file ownership matrix, `docs/decisions/` is @architect territory; the gap is a canonical numbering opportunity, not a placeholder. **Naming**: "Template Architecture" reflects the **single canonical ADR for the AtilCalculator → Multi-Agent Dev Studio Template transition**. Future template-arch changes (template-pull, multi-template marketplace, version bumping) are sibling ADRs (Sprint 22+).

## Context

### Sprint 21 mandate — Multi-Agent Dev Studio Template

Sprint 21's mandate (per Issue #627 + owner directive 2026-06-29, PR #626 squash @ `a5e0942`): ship a **`gh repo create --template` ready Multi-Agent Dev Studio Template** with onboarding target ≤60min from clone to first standup. The template is the bootstrap for all future projects in the dev-studio ecosystem (AtilCalculator is one such project; the template is the source of truth for new projects).

### AtilCalculator as canonical template (Q4 ratified)

Per `OPEN-QUESTIONS.md` Q4 (ratified 2026-06-29T02:22Z, arch RECOMMENDS (a) + owner squashed): **AtilCalculator IS the template**. The current state of AtilCalculator (5-agent dev-studio operational, ADR-0002..ADR-0060 doctrine, 40+ scripts, workflow YAML, label invariant) becomes the snapshot that ships as the template. New projects fork/clone + run `dev-studio-init.sh` to replace placeholders with their own values.

### Architectural gap (no canonical doctrine for template)

As of 2026-06-28, **no ADR documents the template architecture decisions**. The template is being built ad-hoc (per Sprint 21 stories S21-001..S21-025) without a canonical home for:
- Single-repo vs monorepo — distribution topology decision
- Parameterization strategy — placeholder vs env vs build-time codegen
- Secrets strategy — where secrets live, how init script handles them
- Distribution strategy — `gh repo create --template` vs copier vs cookiecutter

Without this ADR, downstream contributors (Sprint 21 + Sprint 22+ template-pull + Sprint 23+ marketplace) lack the doctrinal anchor. STORY-S21-016 AC1 mandates `docs/decisions/ADR-0001-template-architecture.md` covering these 4 dimensions.

### Sprint 21 ratification chain (already complete)

The 5 arch-actionable OPEN-QUESTIONS items (Q4, Q11, Q8, Q9, Q13) were arch-validated in PR #626 cmt 4828413749 (cycle 904) and PM-recorded verbatim in commit `c28d17b` (cycle 907). Owner ratification Q1/Q2/Q3 happened via PR #626 squash merge at `a5e0942` (2026-06-29T05:42:51Z). **All pre-conditions for this ADR are met.**

## Decision

Adopt **§Template Architecture** with 5 canonical components:

### §1 — Single-repo template (not monorepo, not separate-repo)

**Decision**: **Single repo** ships as the template. AtilCalculator's existing repo IS the template (Q4 (a) ratified).

**Topology**:
```
atilcan65/dev-studio-template (the template repo, future)
        ↓ gh repo create --template
<new-project-repo> (a clone with placeholders rendered)
```

**Rationale**:
- **Current state**: AtilCalculator is the de-facto template (`TEMPLATE-README.md` extensive, ~70% of template work done per `proposed-scope.md`).
- **Drift risk** (RISK-REGISTER R2 P1): Splitting creates two sources of truth that must be kept in sync. Single-repo eliminates drift by construction.
- **Architecture pattern match**: ADR-0017 (tech stack) + ADR-0010 (per-project watchers) are both single-repo doctrine. ADR-0001 follows the same pattern.
- **No scaling pressure**: Multi-project orchestration is Sprint 23+ candidate (out of scope per `proposed-scope.md` §"Not this sprint's goal"). Monorepo would pre-pay architecture cost for a problem we don't have.

**Rejected alternatives**:
- **Monorepo** (single repo, multiple project sub-dirs): complex init script (must know which sub-project is "this" project), no value when projects are independent.
- **Separate-repo** (AtilCalculator + dev-studio-template as siblings): double maintenance burden, two sources of truth for doctrine (R2 P1 doctrine drift).

### §2 — Placeholder parameterization (not env vars, not build-time codegen)

**Decision**: **`{{...}}` placeholders + init script replacement** for parameterization.

**Mechanism**:
1. Template repo carries `{{PROJECT_NAME}}`, `{{HUMAN_OWNER_NAME}}`, `{{REPO_URL}}`, `{{AGENT_NAME}}`, `{{TELEGRAM_BOT_TOKEN}}`, `{{PROJECT_TOKEN}}` etc. as literal placeholders in all text files (markdown, YAML, scripts, code).
2. `dev-studio-init.sh` (S21-003) renders placeholders on first run, asking user for each value via interactive prompt (or `--non-interactive` flag with env vars).
3. `.tmpl` extension on script files marks files that need parameter-aware substitution (e.g., `notify.sh.tmpl` → `notify.sh` after render).
4. Idempotency: re-running init on a half-rendered project **recovers** (does not stop on first error), logs `silent_skip` per ADR-0045 lens d.

**Rationale**:
- **Clarity**: placeholders are visible in code review (no hidden env var dependency).
- **Audit**: `dev-studio-init.sh` + parameterization audit script (S21-004) catches any `AtilCalculator` / `atilcan65` leaks (sister-pattern to secret-canary workflow per ADR-0014).
- **YAGNI**: env var substitution (Option B) requires every consumer to know the env var namespace; build-time codegen (Option C) requires a build step the template doesn't otherwise need.
- **Init script idempotency** (Q4 arch caveat): running twice = same result. Recovery on partial render is per ADR-0045 lens d (no silent skip).
- **Best-effort with smoke-test gate** (Q13 arch CONCURS (b)): init script is best-effort, S21-022 smoke-test is the end-of-init validation gate.

**Rejected alternatives**:
- **Env vars** (every consumer reads `process.env.PROJECT_NAME`): invisible to code review, env var namespace coupling, secrets in env vars = risk.
- **Build-time codegen** (e.g., `template-renderer.py` runs in CI): adds a build step, requires CI integration, hidden from contributor.

### §3 — Per-project init prompt (secrets strategy)

**Decision**: **`dev-studio-init.sh` prompts for secrets on first run**; secrets never live in the template repo (only placeholders).

**Mechanism**:
1. Init script prompts: "Enter Telegram bot token (or paste from TELEGRAM-SETUP.md):" — user pastes, script writes to `gh secret set TELEGRAM_BOT_TOKEN` via `gh` CLI.
2. Init script prompts: "Enter PROJECT_TOKEN (GitHub PAT with `repo + project` scope):" — user pastes, script writes to `gh secret set PROJECT_TOKEN`.
3. Single PAT per project (Q8 arch CONCURS (a)) — matches ADR-0014 PROJECT_TOKEN pattern.
4. **Init script MUST NOT touch `TELEGRAM-SETUP.md` secrets** (Q8 arch caveat) — that's project-level, not template-level.
5. **Init script MUST fail loud on `ghp_*` pattern in template files** (RISK-REGISTER R10 P0 secret leakage) — first step: scan for `ghp_*`, fail if found.

**Rationale**:
- **Secret-canary workflow** (`.github/workflows/secret-canary.yml`) catches leaks on PR — sister-pattern to R10 P0 mitigation.
- **Pre-commit hook** checks for `ghp_*` patterns — dev lane territory.
- **Init script first step: secret scan** — defense in depth (template never ships a real secret).
- **Single PAT** (Q8 ratified) matches ADR-0014 (single PROJECT_TOKEN, `repo + project` scope).
- **No telemetry across clones** (Q11 ENDORSES (b) — owner ratified) — per RETRO-013 minimalism doctrine, observability = structured logs + trace spans + counters, NOT telemetry hook.

**Rejected alternatives**:
- **Secrets in `.env` file committed**: leaks on every clone, defeats the purpose.
- **Per-agent PAT** (Q8 (b)): more setup burden, no per-agent attribution benefit at template scope.

### §4 — `gh repo create --template` distribution (not copier, not cookiecutter)

**Decision**: **GitHub-native template distribution** via `gh repo create --template atilcan65/dev-studio-template <new-project-name>`.

**Mechanism**:
1. Owner marks `atilcan65/dev-studio-template` as a GitHub template repo (Settings → Template repository checkbox).
2. User runs `gh repo create --template atilcan65/dev-studio-template my-new-project --public --clone`.
3. User runs `cd my-new-project && bash scripts/dev-studio-init.sh` (renders placeholders, prompts for secrets, runs smoke test).
4. User runs `git push` to publish the rendered repo.
5. User's first standup wakes the 5 agents (orchestrator auto-creates label hygiene + board sync per ADR-0013).

**Rationale**:
- **Native GitHub feature**: no external tooling dependency, GitHub handles versioning + clone mechanism.
- **Discoverability**: template appears in GitHub's "Use this template" button — zero friction for new users.
- **Free + public** (ADR-0016 ratified): public-by-default doctrine applies to the template repo itself (template is public, clones are public-by-default per ADR-0016).
- **Onboarding target ≤60min**: matches the "from clone to first standup" success metric.

**Rejected alternatives**:
- **Copier** (`copier copy gh:atilcan65/dev-studio-template my-new-project`): more features (template updates, multi-template) but extra dependency, smaller community, fewer GitHub-integrated features.
- **Cookiecutter** (`cookiecutter gh:atilcan65/dev-studio-template`): Python-specific, less GitHub-native, more boilerplate than copier.
- **Custom installer**: reinventing `gh repo create --template`, no value.

### §5 — Cross-references to sister ADRs

Per AC3, this ADR cross-references:

- **ADR-0012 (Required Label Set)** — every issue/PR in the template carries 4-cat label invariant (`type:*` + `status:*` + `agent:*` + `cc:*`). The label-check workflow (`.github/workflows/label-check.yml`) is part of the template.
- **ADR-0014 (PROJECT_TOKEN secret)** — single PAT per project, `repo + project` scope, used by `status-label-to-board.yml` for Projects v2 sync. Init script prompts for this PAT.
- **ADR-0016 (Public-by-default)** — new projects bootstrap as public repos (default `--public` flag on `gh repo create --template`). Cost driver = GitHub Actions minutes; ADR-0016 doctrine applies to clones.
- **ADR-0002 (Autonomy Loop)** — every clone carries the autonomy loop doctrine (`.claude/CLAUDE.md` + soul files for 5 agents + `scripts/agent-watch.sh`).
- **ADR-0045 (9-Lens pre-publish gate)** — every PR in the template carries 9-Lens coverage on architect verdicts.
- **ADR-0049 (d-test framework)** — every clone ships with d-test framework; d070-template-render d-test verifies init script idempotency + placeholder coverage.

Per AC2, this ADR is referenced from `TEMPLATE-README.md` (Quick Start section) and `CLAUDE.md` (Doctrine section). Those references are created as part of Sprint 21 stories S21-008 (CLAUDE.md at project root) + S21-019 (TEMPLATE-README.md).

## Rationale

### Why this decision now (Sprint 21 ratification chain complete)

The 5 arch-actionable OPEN-QUESTIONS (Q4/Q11/Q8/Q9/Q13) were ratified in PR #626 cmt 4828413749 + owner squash at `a5e0942` (2026-06-29). All pre-conditions for this ADR are met. STORY-S21-016 AC1 mandates this ADR exists before S21-016 closure. Sprint 21 wave 2 (S21-013..S21-018) depends on this ADR (per `proposed-scope.md` §Wave dependencies).

### Why single-repo over monorepo

Boring tech wins. The dev-studio ecosystem is one-team-many-projects, not one-org-many-projects. Monorepo would pre-pay architecture cost for a problem we don't have (Sprint 23+ multi-project orchestration is the candidate trigger for monorepo). YAGNI per heuristics.

### Why placeholders over env vars / build-time codegen

Visibility in code review > invisible substitution. Auditable > opaque. Per `proposed-scope.md` "70% of template work done" — the placeholder convention is already established in AtilCalculator's existing template drafts (S21-001, S21-002 work). This ADR codifies the existing pattern, not invents a new one.

### Why per-project init prompt over committed secrets

Secrets in template = guaranteed leak on every clone. Per-project init prompt is the only safe pattern. Single PAT per project (Q8 ratified) matches existing AtilCalculator architecture (ADR-0014 PROJECT_TOKEN).

### Why `gh repo create --template` over copier / cookiecutter

Native GitHub feature, zero friction for new users, no external tooling dependency. Onboarding target ≤60min requires minimal ceremony. Copier + cookiecutter are good tools but over-engineered for Sprint 21 scope.

## Consequences

### Positive outcomes

1. **Drift elimination** (R2 P1 mitigation) — single source of truth for doctrine, scripts, workflows. AtilCalculator and clones share the same `.claude/CLAUDE.md` + ADR library + script suite.
2. **Onboarding target ≤60min** — `gh repo create --template` + init script + smoke test is the canonical "from clone to first standup" path.
3. **Auditable template** — every file carries `{{...}}` placeholders, init script + parameterization audit (S21-004) catches leaks.
4. **Sister-pattern with existing architecture** — single-repo + ADR-0017 tech stack + ADR-0010 minimal infra + ADR-0014 PROJECT_TOKEN = consistent architecture across the project family.
5. **Open-questions ratification chain preserved** — Q4/Q11/Q8/Q9/Q13 arch-validated + caveats integrated into S21-003/004/020/022/023 AC.

### Negative tradeoffs

1. **Init script complexity** — `dev-studio-init.sh` (S21-003) + parameterization audit (S21-004) + smoke test (S21-022) is a 3-component pipeline. Mitigation: best-effort with smoke-test gating (Q13 arch CONCURS (b), YAGNI per heuristics).
2. **Single PAT per project** (Q8 (a) ratified) — no per-agent attribution. Mitigation: agent-watch + bot logs preserve attribution via GitHub artifacts (issue labels, PR comments).
3. **No template updates yet** — clones are static snapshots until Sprint 22+ template-pull. Mitigation: Sprint 21 → Sprint 22 hand-off (Q10 owner decision) prioritizes template-pull.
4. **Init script = best-effort** — failure mode is "log markers + recover on rerun", not "atomic rollback". Mitigation: S21-022 smoke test is the end-of-init validation gate.

### Follow-up tickets to file

- **Sprint 21 STORY-S21-016** (this ADR's home) — drafted, awaiting owner squash gate.
- **d070-template-render d-test** (S21-018, ADR-0049 sister-pattern) — verifies init script idempotency + placeholder coverage.
- **Sprint 22 STORY-S22-001 (template-pull)** — auto-sync doctrine updates to existing clones. Sister-pattern to this ADR's distribution strategy.
- **Sprint 23 STORY-S23-001 (multi-project orchestrator)** — candidate trigger for monorepo architecture (out of scope this sprint).

## Alternatives considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **A. Single-repo + placeholders + init prompt + gh template (CHOSEN)** | Matches existing AtilCalculator state; no drift; auditable; native GitHub feature; ADR-0014 sister-pattern | Init script complexity (S21-003 + S21-004 + S21-022 3-component pipeline); no template updates until Sprint 22+ | ✅ CHOSEN — file ownership matrix correctness + Q4 (a) ratified |
| B. Monorepo | One repo, multiple project sub-dirs | Complex init script (must know "this" project); pre-pays architecture for Sprint 23+ problem | ❌ YAGNI |
| C. Separate-repo (AtilCalculator + dev-studio-template siblings) | Clean separation | Double maintenance; two sources of truth (R2 P1 doctrine drift) | ❌ drift risk |
| D. Env var substitution | Familiar pattern | Invisible to code review; env var namespace coupling; secrets in env vars | ❌ visibility + secrets risk |
| E. Build-time codegen | Reproducible | Build step adds CI integration; hidden from contributor | ❌ over-engineered |
| F. Copier | More features (template updates, multi-template) | External dependency; smaller community; less GitHub-native | ❌ out of scope (Sprint 22+ candidate) |
| G. Cookiecutter | Python-specific | Less GitHub-native; more boilerplate than copier | ❌ out of scope |
| H. Per-agent PAT (Q8 (b)) | Better attribution | More setup burden; no per-agent attribution benefit at template scope | ❌ Q8 (a) ratified |

## Cross-references

### Doctrinal anchors

- **Issue #113** — label-authority doctrine (agent/cc labels are authoritative; body text may be stale)
- **Issue #238** — no-standby doctrine (no self-justified pauses; WIP=0/2 means queue empty by computation)
- **Issue #430** — PM-side §Pre-citation cross-check (verify-before triangle, ratified)
- **Issue #470** — PM-side §Timing window (verify-before triangle, ratified)
- **Issue #627** — Sprint 21 kickoff (this ADR closes the kickoff + S21-016)
- **ADR-0002** — Autonomy Loop (template carries `.claude/CLAUDE.md` + soul files + `scripts/agent-watch.sh`)
- **ADR-0010** — Per-Project Watchers (single-repo doctrine match)
- **ADR-0012** — 4-cat label invariant (every issue/PR in template carries 4-cat labels; AC3 cross-ref)
- **ADR-0013** — Status → Board Sync (template ships `status-label-to-board.yml`)
- **ADR-0014** — PROJECT_TOKEN secret (single PAT per project; init prompt; AC3 cross-ref)
- **ADR-0016** — Public-by-default (clones default `--public`; template itself public; AC3 cross-ref)
- **ADR-0017** — Tech stack (template inherits Python 3.11+ / pytest / ruff / mypy / typer / Decimal)
- **ADR-0044** — RED-first TDD (tester d070-template-render d-test sign-off)
- **ADR-0045** — 9-Lens pre-publish gate (every PR carries 9-Lens on architect verdicts)
- **ADR-0049** — d-test framework (d070-template-render sister-pattern, AC3 cross-ref)
- **ADR-0055** — Cadence Rule 1 atomic — this ADR + INDEX.md row in same PR
- **ADR-0060** — §AC mapping verification doctrine (cross-lane "verify-before" triangle completion)

### Sprint 21 ratification chain

- **PR #625** — Sprint 18 close-out + RETRO-014 (Sprint 19 SKIPPED, Sprint 20 PROJECT CLOSE) — squash @ `e4bfa3e`
- **PR #626** — Sprint 21 PM-drafted full scope (25 stories, 12 epics, ~63 SP) — squash @ `a5e0942`
- **PR #628** — current/plan.md pointer refresh — Sprint 21 ACTIVE — owner commit `90df05e`
- **Issue #627** — Sprint 21 kickoff issue — closed (status:done) post-PR-626-squash
- **cmt 4828413749** — arch input on Q4/Q11/Q8/Q9/Q13 (cycle 904)
- **cmt 4828433480** — PM peer ACK (cycle 907, all 5 verdicts accepted + 4 caveats integrated)
- **commit `c28d17b`** — PM curator recorded arch input verbatim (cycle 907)

### Sprint 21 sister stories (this ADR's downstream)

- **S21-001** (P0) — Inventory audit (`docs/sprints/sprint-21/INVENTORY.md`)
- **S21-002** (P0) — License finalization (MIT default per Q1 ratified)
- **S21-003** (P0) — `dev-studio-init.sh` (parameterization, this ADR §2 + §3 implementation)
- **S21-004** (P0) — Parameterization audit (placeholder coverage, this ADR §2 validation)
- **S21-008** (P1) — `CLAUDE.md` at project root (per AC2: this ADR referenced from CLAUDE.md)
- **S21-016** (P1) — **this ADR** (template architecture)
- **S21-018** (P1) — d070-template-render d-test (per AC3: ADR-0049 sister-pattern)
- **S21-019** (P1) — TEMPLATE-README.md (per AC2: this ADR referenced from TEMPLATE-README.md)
- **S21-020** (P1) — ONBOARDING.md (fresh fixture dir, PM-as-validator per Q9 ratified)
- **S21-022** (P1) — CI smoke-test gating (best-effort init + smoke-test gate per Q13 ratified)
- **S21-023** (P1) — Fresh-clone validation (≥2 fresh clones per Q9 ratified)
- **S21-024** (P1) — `.template-version` file (deferred per Q4 ratified (a) — no `.template-version` needed)

### 9-Lens attestation (per ADR-0045)

Per architect.md §9-Lens Review Checklist, this ADR is a doctrine-only ADR (no runtime/impl changes). Applicable lenses:

- **(a) Data flow**: ✅ N/A — doctrine-only, no runtime data path
- **(b) Runtime preconditions**: ✅ N/A — doctrine-only
- **(c) Canonical entry**: ✅ — `docs/decisions/ADR-0001-template-architecture.md` is the canonical home for template architecture (this ADR claims the gap number)
- **(d) Silent-skip risk**: ✅ — §2 specifies init script MUST log `silent_skip` per ADR-0045 lens d (Q13 arch caveat integrated)
- **(e) Idempotency**: ✅ — §2 specifies init script idempotency (Q4 arch caveat integrated; running twice = same result)
- **(f) Observability**: ✅ — §3 specifies per-project init prompt + secret-canary workflow; no telemetry per Q11 ENDORSES (b) (RETRO-013 minimalism preserved)
- **(g) Security & privacy**: ✅ — §3 specifies per-project init prompt (secrets never in template) + secret-canary workflow + pre-commit hook + init script `ghp_*` scan (R10 P0 mitigation)
- **(h) Workflow YAML SHA pin**: ✅ — §3 references `secret-canary.yml`; SHA-pin enforcement is sister-pattern TD-028 / ADR-0027 §Threat model (deferred to owner per file ownership matrix)
- **(i) Platform hard constraints**: ✅ N/A — doctrine-only; downstream workflows (S21-011) must respect 8 sub-categories per ADR-0043
- **(j) Auto-generated file refs**: ✅ — §2 specifies `.tmpl` extension; d070-template-render d-test verifies placeholder coverage

— @architect, 2026-06-29T05:45+03:00, ADR-0001 Template Architecture codification (closes Issue #627 + Sprint 21 STORY-S21-016), sister-pattern to PR #595 (ADR-0059) + PR #598 (RETRO-012) + PR #612 (verdict-by Discipline) for arch design + ADR + INDEX atomic per ADR-0055 Cadence Rule 1