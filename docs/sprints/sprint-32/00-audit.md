# Sprint 32 Audit — dev-studio-template & dev-studio-launcher Finalize

> **Date**: 2026-07-18
> **Author**: @orchestrator (cycle ~#3218, post-REPRIME)
> **Trigger**: Owner directive 2026-07-18T10:01+0300 — "Sprint 32 sadece bu iş olacak, 1 sprintte tamamlıcaz"
> **Status**: DRAFT — pending owner read. NO action taken (no commit, no PR).
> **Method**: gh REST API + gh repo view, no fabrication; if unknown, "bilmiyorum" stated explicitly.

---

## TL;DR — Top 6 gaps blocking "dev-studio-template is finalized"

> **Owner infrastructure note (per directive 2026-07-18T10:30+0300)**: Owner runs self-hosted runner pool at **192.168.1.197 with 8 active runners**, currently serving AtilCalculator. Same pool will be wired to template-launched private projects; GitHub-hosted runner will be set to inactive. **Therefore self-hosted runner is NOT a Sprint 32 gap** — it is owner-managed infrastructure. Template repo's `gh api actions/runners` showing 0 = owner will register when needed.

| # | Gap | Severity | Where |
|---|---|---|---|
| 1 | **Label Check workflow FAILED on main** (commit d9af223, 2026-07-17T20:59:25Z) — issue #123 missing `agent:*` + `cc:*` (4-cat invariant violation). **NOTE**: Issue #123 label-fix CANCELLED by owner directive 2026-07-18T10:30+0300. Sprint 32 will create NEW issues with proper labels instead. | P0 | template main |
| 2 | **`scripts/orchestrator-gap-scan.sh` ABSENT from template** (calc has 8514 bytes since 2026-07-14) | P0 | template scripts/ |
| 3 | **Orchestrator soul file Δ = +5500 bytes in calc** (template is 7071, calc is 12571) — Cadence Rule 2 + RETRO-018 + RETRO-027 amendments missing from template | P0 | template `.claude/agents/orchestrator.md.tmpl` |
| 4 | **Architect soul file Δ = +1440 bytes in calc** (template 4377, calc 5817) — recent amendments missing | P1 | template `.claude/agents/architect.md.tmpl` |
| 5 | **Template README.md.tmpl + LABEL-TAXONOMY.md + TEMPLATE_NOTES.md have stale `atilcan65` refs** — URL hygiene fix (launcher b1355be, 2026-07-13) not propagated | P1 | template docs |
| 6 | **Template CHANGELOG.md is frozen at v1.0.1 (2026-07-09)** — 12+ commits after tag with no new release; main is ahead of tag by ~1.5 weeks of work | P1 | template CHANGELOG.md |

---

## Q1 — Is dev-studio-template ready to open any private project in atilproject org?

**Bilmiyorum kesin olarak, ama elimdeki verilere göre: HAYIR, hazır değil.**

### What I checked
- **Repo visibility**: dev-studio-template = `PUBLIC` (correct per ADR-0016 default)
- **Latest tag**: `v1.0.1` (sha `43592c2`, tagged around 2026-07-09)
- **Latest commit on main**: `d9af223` (2026-07-17T20:54:51Z) — **main is 12+ commits AHEAD of tag v1.0.1** with no new tag
- **Open issues**: 0, **Open PRs**: 0 — repo is "feature-frozen" but the existing CI is RED on main
- **Most recent CI run on main** (2026-07-17T20:54:54Z, sha `d9af223`):
  - CI: ✅ success
  - Lint & Test (d-tests): ✅ success
  - Label Cleanup: ✅ success
  - Label Check: ❌ **failure** (Issue #123 missing `agent:` + `cc:` — 4-cat invariant violation)
  - Deploy to production: ❌ failure (likely no self-hosted runner)
  - Status Label → Board Sync: skipped (no project token or no events)
  - Cross-repo-close: skipped

### Test execution status
- 49 d-test files exist in `scripts/tests/` — I did NOT execute them all (would take time, would touch repo state). Last CI run said ✅ success on `Lint & Test (d-tests)` so tests are passing.
- d-test INDEX.md exists. **DİKKAT**: d-test ID convention `(d\d+-slug\.sh)` enforced per ADR-0049.

### What's missing for "private repo launch ready"
1. ❌ Self-hosted runner registered on template (0/0 — see Q3)
2. ❌ Template Label Check is RED on main (violation needs fix)
3. ❌ Template main is ahead of tag v1.0.1 (release train broken)

---

## Q2 — Were all AtilCalculator scripts/processes/doctrines/agents/methods transferred to template? How do we verify?

**Kısa cevap: BÜYÜK ORANDA HAYIR. ~40+ gap var. Bunların hepsi Sprint 32'de kapatılmalı.**

### Verification method

Already exists in template: **`scripts/verify-portage.sh`** (the 60% portage gap re-verifier). It was added during Sprint 28 to make this audit re-runnable. **Last full run: bilmiyorum** — would need to check the auto-claim log or run it. I did NOT run it now (it creates scratch repos in /tmp, touches GitHub API). Per "no action without owner reading", I'm reporting what `gh api` shows statically.

### Static surface comparison (calc vs template)

| Surface | AtilCalculator | Template | Δ |
|---|---|---|---|
| `scripts/*.sh` top-level | 45 files | 44 files | calc has +1 |
| `scripts/install/*.sh` | 3 files | 4 files (+ `systemd/`) | template has +1 |
| `scripts/ops/*.sh` | 1 (`apply-vm-hardening.sh`) | 0 | calc-only (VM hardening) |
| `scripts/post-squash/` | 2 files | 2 files | SAME |
| `scripts/kickoff/` | 5 files (rendered .txt) | 5 files (.txt.tmpl) | expected diff |
| `scripts/tests/` d-test count | 50+ (cut off in listing) | 49 files | calc has more calc-specific d-tests |
| `docs/decisions/` ADR files | 71 files (incl. amendments) | 31 files | **TEMPLATE MISSING ~40 ADRs** |
| `.claude/agents/orchestrator.md.tmpl` | 12571 bytes | 7071 bytes | **Δ +5500 bytes in calc** |
| `.claude/agents/architect.md.tmpl` | 5817 bytes | 4377 bytes | **Δ +1440 bytes in calc** |
| `.claude/agents/{pm,developer,tester}.md.tmpl` | ~identical | ~identical | no recent delta |
| `.claude/CLAUDE.md(.tmpl)` | 25144 bytes | 18749 bytes | Δ +6395 bytes in calc |
| `.github/workflows/*.yml` | 11 files | 11 files (+ `deploy.yml.tmpl`) | expected diff |
| `.github/ISSUE_TEMPLATE/*.yml` | 6 files | 6 files (+ `config.yml.tmpl`) | expected diff |

### Concrete gaps — TEMPLATE MISSING (calc has, template doesn't)

#### P0 — Doctrine-critical
1. **`scripts/orchestrator-gap-scan.sh`** — Issue #235 doctrine, 8514 bytes, locally verified. ABSENT from template. (calc was modified 2026-07-14, cycle ~#2852 timestamp)
2. **Orchestrator soul file amendments** — 5500 bytes of doctrine (Cadence Rule 2 retroactive-close precondition, Issue #414 dispatch discipline, RETRO-018 W6 branch-ownership matrix, KAPI hotfix, etc.) MISSING from template
3. **Architect soul file amendments** — 1440 bytes missing
4. **`docs/decisions/ADR-0057-closes-anchor-guard.md`** — exists in template
5. **Missing ADRs in template** (list may be incomplete, full diff needed):
   - `ADR-0001-template-architecture` (template-specific, should be in template!)
   - `ADR-0007-label-cleanup-and-revert-doctrine`
   - `ADR-0034`, `ADR-0035`, `ADR-0037`, `ADR-0038-amendments`, `ADR-0039`, `ADR-0041`, `ADR-0043`, `ADR-0044`, `ADR-0045`, `ADR-0048-amendments`, `ADR-0049-amendments`, `ADR-0051`, `ADR-0053`, `ADR-0054`, `ADR-0055`, `ADR-0056`, `ADR-0058`, `ADR-0061`, `ADR-0062`, `ADR-0063`, `ADR-0064`, `ADR-0065`, `ADR-0067`, `ADR-0068`, `ADR-0069`, `ADR-0070`, `ADR-0071`
   - **CRITICAL**: I have not classified each as "doctrine (template-relevant)" vs "calc-specific". Sprint 32 architect task.

#### P0 — Self-hosted runner (see Q3 below)

#### P1 — Stale docs / refs
6. **`README.md.tmpl`** references `atilcan65/dev-studio-template` URL — STALE post-URL-hygiene fix (launcher PR #4, b1355be 2026-07-13)
7. **`.github/LABEL-TAXONOMY.md`** references `atilcan65/AtilCalculator` URL — STALE
8. **`TEMPLATE_NOTES.md`** has 4 `atilcan65/AtilCalculator` refs — STALE
9. **Template `ci.yml`** is JS-only (no Python detection), while calc's ci.yml has both Python+Node detection. Template ci.yml is also less hardened (uses `actions/checkout@v4` tag, not SHA-pinned).
10. **Template `CHANGELOG.md`** is frozen at `[Unreleased]` section that ends mid-Sprint 28. No Sprint 29-31 entries.

#### P1 — Tooling gaps
11. **`scripts/install/dev-studio-install-env.sh`** — Telegram env-provisioning helper (PR #114, merged 2026-07-15 in template, calc still MISSING this file — `ls scripts/install/` shows only 3 files in calc, 4 in template)
12. **`scripts/install/systemd/`** subdir + `dev-studio-watcher@.service.tmpl` — present in template, absent in calc (calc needs forward-port)

### Concrete gaps — CALC MISSING (template has, calc doesn't)
- All 4 are forward-port of Sprint 29+ template changes that never propagated to calc working tree:
  - `scripts/install/dev-studio-install-env.sh`
  - `scripts/install/systemd/dev-studio-watcher@.service.tmpl`
  - (also 2 more I haven't enumerated — full audit needed)

### How we verify "last time"
- `scripts/verify-portage.sh` exists in template (Sprint 28). Running it = full render + diff + gap report.
- Run command: `bash scripts/verify-portage.sh --report /tmp/portage-sprint-32.txt`
- Alternative: `bash scripts/verify-portage.sh --dry-run --json` for machine-readable output.
- **Sister-pattern: ADR-0050** (pre-merge 4-cat verification) + **ADR-0059** (cluster-squash inventory) — already enforced as doctrine.

---

## Q3 — Is self-hosted runner migration 100% complete?

**OWNER-MANAGED — NOT a Sprint 32 agent task. Status: complete from owner's side.**

### What I checked via `gh api repos/<repo>/actions/runners`

| Repo | Registered self-hosted runners (gh API count) |
|---|---|
| `atilproject/AtilCalculator` | 1 ✅ |
| `atilproject/dev-studio-template` | 0 (owner will wire when launching projects) |
| `atilproject/dev-studio-launcher` | 0 (owner will wire when launching projects) |
| Org-level runners (`/orgs/atilproject/actions/runners`) | 8 total |

### Per owner directive 2026-07-18T10:30+0300

- **Owner infrastructure**: 192.168.1.197 LAN host with **8 active self-hosted runners**, currently serving AtilCalculator via `runs-on: [self-hosted, Linux, X64, atilproject]` 4-tuple
- **For template-launched private projects**: same pool will be reused (GitHub-hosted runner will be set to inactive after self-hosted wired in)
- **Template repo's `actions/runners` count = 0** is expected — owner registers per-repo as needed; the runner pool is shared infrastructure, not per-repo resource
- **Orchestrator MUST NOT ping owner for runner setup** (owner owns this fully; per file ownership matrix `.github/workflows/` is human-only territory)

### Implications for Sprint 32
- Sprint 32 gap-closure work does NOT block on runner registration
- New template-launched private repos can immediately use the owner's pool
- Any 4-tuple change (e.g. switching runner OS) needs owner coordination (architect designs, owner executes)

---

## Q4 — If template is "complete", what else might need to be added?

**Bu soruyu cevaplamak için template'in "tamamlanmış" halini tanımlamamız gerek.** Şu an elimde 3 ayrı tamamlanmışlık tanımı var:

### Definition A — "Calc-equivalent feature parity" (en geniş)
Template has every feature in calc. Gap list = Q2 above (~40+ items). Sprint 32 work.

### Definition B — "Self-sufficient for new project bootstrap" (orta)
Template can stand up a new project from scratch (labels + workflows + agent files + PROJECT_TOKEN + CI green). Gaps:
- Self-hosted runner on template (Q3)
- Label Check fix (Q2)
- Tag v1.0.1 → v1.1.0 release
- Update CHANGELOG, README, TEMPLATE_NOTES

### Definition C — "v1.0.1 minimal viable" (en dar)
Template can scaffold a project with public visibility. Today, technically yes, but with the caveats above.

### Proposed additions per definition

#### Definition A additions (recommended — Sprint 32 scope)
- **Port `orchestrator-gap-scan.sh`** (P0)
- **Sync orchestrator + architect soul files** (P0)
- **Sync ~40 missing ADRs** (after triage — calc-specific vs doctrine)
- **Update template ci.yml** to support Python detection (P1)
- **SHA-pin all `actions/*` references in template workflows** (P1, defense-in-depth per ADR-0027 §Threat model)
- **Forward-port calc → template** (any calc-only scripts that ARE doctrine-relevant)

#### Definition B additions (Definition A subset)
- All Definition A gaps AS THEY RELATE to template (i.e. only doctrine-relevant, not calc-specific)
- Tag a v1.1.0 release after Definition A work

#### Definition C additions (Definition B minimum)
- Tag the current state as v1.1.0 (with fix-forward of Label Check + README URL hygiene)
- Document the gaps in CHANGELOG/Unreleased

### Things NOT to add to template (calc-specific)
- `pyproject.toml.tmpl` with `name = "atilcalc"` — already correct (uses `{{PROJECT_NAME}}` template var, currently rendered as `atilcalc` for default. Calc needs different render)
- `src/atilcalc/*` — calc-specific
- ADRs 0017, 0018, 0019, 0022, 0023 — calc tech-stack/front-end/API/persistence/frontend-architecture
- `scripts/run-server.sh` — calc FastAPI launcher
- `scripts/s29-002-tag-move.sh` — Sprint 29-specific

### Things to add to template (NOT currently there)
- `scripts/install/systemd/dev-studio-watcher@.service.tmpl` — present in template already (calc missing)
- Sister-pattern: check if calc-only `scripts/orchestrator-gap-scan.sh` should be ported TO template (yes per Q2)
- `scripts/orchestrator-status-flip.sh` — already in template ✅
- Templates for `docs/decisions/INDEX.md.tmpl` — exists in template (good)
- Templates for `docs/ARCHITECTURE-*.md` — not sure, needs check
- Template for `.claude/commands/` — currently has 2 (`sprint-start.md.tmpl`, `standup.md.tmpl`); calc has 0 (?). Needs triage.

---

## Q5 — Is dev-studio-launcher still ready?

**BÜYÜK ORANDA EVET, ama 3 gün geride ve 2 güncelleme ihtiyacı var.**

### Launcher state
- **Latest release**: v0.3.0 (sha `b0d820d`, 2026-06-17) — 1 month old
- **Latest commit on main**: `13f7c89` (2026-07-15T11:56:10Z) — S29-013 self-hosted 4-tuple patch
- **3 days behind template** — template last push 2026-07-17, launcher last push 2026-07-15
- **All 4 PRs MERGED, 0 open issues, 0 open PRs** — clean state
- **Has no CI configured** — `gh api actions/runs` returned empty for launcher
- **Tests**: `tests/d001-launcher-self-hosted-runner-patch.sh` exists; no CI integration visible

### What's needed for launcher "ready"
1. ❌ **Self-hosted runner registered on launcher** (currently 0)
2. ❌ **No CI workflow file on launcher** — no automated test running on launcher's main
3. ⚠️ **Launcher last release v0.3.0 is 1 month stale** — does launcher know about v1.0.1 template? Bilmiyorum without reading `new-project.sh` in full
4. ⚠️ **Launcher doesn't pin a specific template version** — `gh repo create --template atilproject/dev-studio-template` always pulls from `main` (no `--template-tag` flag in `gh` CLI for this purpose IIRC, but verify)

### Concrete actions for launcher Sprint 32
- Add `.github/workflows/ci.yml` + `.github/workflows/lint-and-test.yml` to launcher (mirror template's, with d001 d-test as the d-test job)
- Add CI integration for `tests/d001-launcher-self-hosted-runner-patch.sh` (ADR-0044 RED-first pattern)
- Bump version to v0.4.0 after fixes
- Add explicit "TESTED with template v1.1.0" badge in README once template v1.1.0 ships

### Sister-pattern with template
- Launcher constant `RUNNER_4TUPLE_LABEL_PATTERN="[self-hosted, Linux, X64, atilproject]"` is the SSOT for the 4-tuple (architect verdict Q1 cycle 5934). If we change the label set, BOTH template and launcher must update together.

---

## Q6 — Document: detailed steps to set up new project with template

**TODO. I will produce this AFTER owner approves the audit. Plan:**
- File path: `docs/new-project-steps.md` (in template repo, NOT calc)
- Format: copy-pasteable commands per step, with "what could go wrong" notes
- Sections (planned):
  1. Prerequisites (gh auth, jq, git, tmux, systemd user)
  2. Get PROJECT_TOKEN PAT
  3. `git clone` launcher (one-time)
  4. Run `new-project.sh <name> [--private]`
  5. Verify render with `dev-studio-init.sh --dry-run` then real
  6. Seed labels with `bootstrap-labels.sh`
  7. Set up Telegram (optional, install-env helper)
  8. Set up systemd timer (install-systemd.sh)
  9. Register self-hosted runner (manual, owner task)
  10. First Vision Intake issue (manual, owner task)
  11. Start tmux agents (dev-studio-start.sh start)
  12. Verify with first d-test run

**Not done yet — owner approval pending.**

---

## Q7 — Was 1.0.1 update actually propagated via "Use this template"?

**Bilmiyorum. Static analysis suggests main is AHEAD of tag but I have no evidence either way about the "Use this template" propagation.**

### What I can verify
- **Template main**: `d9af223` (2026-07-17T20:54:51Z) — latest commit
- **Tag v1.0.1**: `43592c2` — points to ~1.5 weeks older commit
- **CHANGELOG.md v1.0.1 entry**: dated 2026-07-09, mentions PR #62 (TD-068b fix) only
- **GitHub's "Use this template" button**: pulls from `main` by default, NOT from tag. So whoever clicked the button AFTER 2026-07-09 got main (with v1.0.1 + later commits) — but the resulting project would NOT match the "v1.0.1 release" badge.

### What I CANNOT verify (no log access)
- When the owner clicked "Use this template" (if ever) — would need browser history or a downstream repo created from template
- **Best evidence**: dev-studio-template-smoke (private, last push 2026-07-10) — created AFTER v1.0.1 tag. Could verify if it has commits newer than tag.
- **`runner-test`** (private, last push 2026-06-29) — created BEFORE v1.0.1 tag, so it would NOT have v1.0.1 content even with re-pull

### Recommendation
1. **Verify with `gh repo view atilproject/dev-studio-template-smoke --json defaultBranchRef,pushedAt`** — if smoke repo's HEAD is at or after 43592c2 (v1.0.1 tag sha), then YES the template update propagated correctly. (Already verified: pushedAt 2026-07-10 is after 2026-07-09, but I haven't checked the HEAD sha)
2. **Inspect smoke repo's `git log --oneline | head -20`** to see if v1.0.1-era commits are present

### Action needed for Sprint 32
- Cut a `v1.1.0` tag on template main, post all Sprint 32 gap-fixes
- Update CHANGELOG to reflect v1.1.0 changes
- Verify smoke repo is at v1.1.0
- (Optionally) Update launcher `TEMPLATE_REPO` constant to optionally pin to v1.1.0

---

## Sister-pattern / doctrine alignment

- **ADR-0012** (4-cat invariant): Template main IS violating this on Issue #123. Fix in Sprint 32.
- **ADR-0013** (status label → board sync): Status label workflow ran "skipped" on template — board may not be set up for template. Check.
- **ADR-0014** (PROJECT_TOKEN PAT): Per-launcher readme, needed at first run. Template uses default GITHUB_TOKEN which can't mutate Projects v2.
- **ADR-0016** (public-by-default): Template is PUBLIC ✅. New private project requires `--private` flag on launcher.
- **ADR-0027** (secrets, smoke test + rollback): deploy.yml uses this. Template has deploy.yml.tmpl + deploy.yml rendered.
- **ADR-0027 §Threat model** (SHA pin actions): Template's `ci.yml` uses `@v4` (not SHA-pinned). VIOLATION.
- **ADR-0030** (self-hosted runner LAN deploy): Template deploy.yml has 4-tuple. But no runner on template → workflow fails.
- **ADR-0031** (owner override doctrine): For Sprint 32, all final merges need owner approval (template has `cc:human` enforcement via label-check, but if labels are missing, check fails).
- **ADR-0033** (auto-ping dual-channel): Template's `agent-wake.sh` and `notify.sh` have the dual-channel wiring per ADR-0066 Fix 4b. ✅
- **ADR-0045** (9-Lens pre-publish): All template workflows have lens (h)+(i) coverage in comments. ✅ in code review, but **CI doesn't enforce 9-Lens**.
- **ADR-0049** (d-test framework): Template has 49 d-tests, INDEX.md, ≥5 TCs pattern. ✅
- **ADR-0050** (pre-merge 4-cat verification): Template label-check is broken (RED on main). ❌
- **ADR-0057** (closes anchor strict format): Template has this ADR. Sister-pattern with calc.
- **ADR-0059** (cluster-squash batch lag detection): Template has `scripts/post-squash/cluster-lag-detector.sh` + d-test. Post-Squash Cluster-Lag Detector workflow FAILED on PR #125 + PR #124 — needs investigation.
- **ADR-0061** (Claude Code --agent flag removal): Template has this ADR. ✅
- **ADR-0066** (tmux-wake Fix 4b): Template has this ADR + agent-wake.sh Fix 4b port (matches calc byte-for-byte). ✅

### Doctrines MISSING from template (calc has, template doesn't)

I have NOT done a full diff. The list above is from spot-check. Sprint 32 architect task = full diff.

---

## Sprint 32 proposed plan (DRAFT — pending owner approval)

### Scope (1 sprint = 2 weeks, 10 working days)

#### Day 1-2: Discovery (architect + orchestrator)
1. **Run `scripts/verify-portage.sh`** — full portage report (4 critical paths)
2. **Diff every ADR in calc vs template** — classify each as doctrine-relevant (port to template) or calc-specific (don't port)
3. **Diff every soul file in calc vs template** — list missing amendments
4. **Diff every script in calc vs template** — list missing scripts
5. **Diff every CI workflow** — list hardening gaps (SHA pin, Python detection, etc.)

#### Day 2-3: ~~Owner-only infrastructure~~ (REMOVED per directive 2026-07-18T10:30+0300 — owner-managed, not Sprint 32 scope)

#### Day 3-6: Gap closure (architect + developer + tester)
9. **Port `scripts/orchestrator-gap-scan.sh` to template** (1 PR)
10. **Sync orchestrator + architect soul files** (2 PRs: 1 per role)
11. **Port doctrine-critical ADRs** (N PRs, batch-squash per ADR-0059)
12. **Update template ci.yml + label-check.yml + lint-and-test.yml** — Python detection, SHA pin
13. **Forward-port calc → template** — `install-env.sh`, `install/systemd/`, etc. (2 PRs)
14. ~~**Fix Issue #123 labels**~~ (CANCELLED per directive 2026-07-18T10:30+0300 — Sprint 32 creates NEW issues with proper labels instead)
15. **Fix stale `atilcan65` refs** in template docs (1 PR)

#### Day 6-8: Launcher updates (developer)
16. **Add CI workflow to launcher** — `.github/workflows/ci.yml` + `lint-and-test.yml`
17. **CI-integrate `tests/d001-launcher-self-hosted-runner-patch.sh`** (ADR-0044 RED-first)
18. **Bump launcher to v0.4.0** with changelog

#### Day 8-9: Documentation (PM + orchestrator)
19. **Write `docs/new-project-steps.md`** in template (full 12-step guide)
20. **Update template CHANGELOG.md** to v1.1.0
21. **Cut tag v1.1.0 on template main**
22. **Update template README.md.tmpl** to reference atilproject URLs
23. **Verify with smoke repo** — re-bootstrap from v1.1.0, run e2e

#### Day 9-10: Verification + close
24. **Full d-test sweep on template** — all 49+ d-tests GREEN on main
25. **Re-run `scripts/verify-portage.sh`** — expect 0 gaps
26. **Sprint 32 close** — RETRO-032.md, update Issue tracker
27. **New project bootstrap dry-run** — actually create a private repo using launcher + verify all features work

### Exit criteria (DoD per CLAUDE.md)
- All ACs pass automated tests (49+ d-tests on template)
- Code merged to `main` via PR with human approval
- CI is green on `main` post-merge (all 11 workflows)
- Docs updated (CHANGELOG, README, new-project-steps)
- Project card moved to Done by orchestrator
- New project bootstrap dry-run successful

### Sister-pattern risks
- **Sprint 31 cluster-squash precedent** (cycle ~#2944): 3-PR batch in 15-sec window. Sprint 32 may need cluster-squash for ADRs (depends on count).
- **Cadence Rule 2** (RETRO-027): if gap closure reveals "fix exists in calc but no PR", must follow retroactive-close precondition (PR-persistence + Closes anchor).
- **Issue #123 label violation**: orchestrator must self-correct per doctrine (4-cat invariant) — explicit action item.
- **Cross-repo workstream** (RETRO-023): Sprint 32 work is 2-repo (template + launcher). Both repos need sprint:current label + cc:human pattern.

---

## What I did NOT do (per "no action without owner reading")

- ❌ Did NOT open any PR (pre-update; audit file now ready for PR to template)
- ❌ Did NOT commit any file
- ❌ Did NOT modify any workflow
- ❌ Did NOT run `scripts/verify-portage.sh` (creates scratch repos)
- ❌ Did NOT register self-hosted runners (owner task; not needed — already managed)
- ❌ Did NOT triage the 40+ missing ADRs in detail (architect task in Sprint 32 Day 1-2)
- ❌ Did NOT write `docs/new-project-steps.md` (waiting on Sprint 32 plan mode)

---

## Owner sign-off questions — RESOLVED 2026-07-18T10:30+0300

1. ✅ **Open PR for audit file → TEMPLATE** (`docs/sprints/sprint-32/00-audit.md` in `atilproject/dev-studio-template`)
2. ✅ **Enter plan mode** for Sprint 32 plan refinement (after audit PR opened)
3. ✅ **Dispatch team AFTER plan mode done** (per "Plan mode işin bittikten sonra dispatch edeceksin")
4. ✅ **No owner-ping for self-hosted runner** — owner has 8-runner pool at 192.168.1.197 wired and ready; GitHub-hosted will be set to inactive after self-hosted wired in
5. ✅ **Issue #123 label fix CANCELLED** — Sprint 32 will create new issues with proper labels per ADR-0012 birth contract

### Pending: Sprint 32 GO signal
Per owner's "ben go verince sprint 32 ile başlayacak", still waiting for explicit GO before Sprint 32 execution starts. Audit PR + plan mode is the preparation phase, not execution.

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)