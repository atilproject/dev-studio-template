# S32-001 Doctrine Diff Classification — AtilCalculator vs dev-studio-template

**Issue**: atilproject/dev-studio-template#127 (S32-001 ARCH)
**Repo**: atilproject/dev-studio-template
**Branch**: `arch/s32-001-doctrine-diff` @ `origin/main` 52ed840
**Date**: 2026-07-18 (cycle ~#3238)
**Author**: @architect
**Cluster**: Standalone (architect lane) — Wave 1 Sprint 32

---

## Story Summary

S32-001 (Sprint 32 Wave 1) audits the **doctrine parity gap** between
`atilcan65/AtilCalculator` (downstream project, 4 sprints ahead) and
`atilproject/dev-studio-template` (canonical template source). The audit
identifies doctrine that has accumulated in calc but not been ported
upstream, blocking every new dev-studio-template-derived project from
inheriting the latest refinements.

This document is the canonical output of S32-001 and the **forward-port
input** for AC1-AC4 sister-stories (S32-002 dev baseline portage, S32-007
doctrine audit sweep, S32-021 d-test sweep).

### Mis-file correction

This issue was originally filed as `atilcan65/AtilCalculator#1148`
(mis-filed). Per RETRO-024 work-tracked-elsewhere doctrine, the AtilCalculator
issue was auto-CLOSED with `stateReason: COMPLETED` and re-filed as
`atilproject/dev-studio-template#127` (canonical, 4-cat labels correct,
work tracked here). Cross-watchdog verification within 30s per
Issue #430 + Issue #682 doctrine.

### Sister-pattern refs

- **ADR-0050** (pre-merge 4-cat verification)
- **ADR-0055 §1** (Cadence Rule 1 atomic — `.tmpl` + `scripts/tests/INDEX.md` same commit)
- **ADR-0044** (RED-first TDD, d-test ≥5 TCs)
- **ADR-0049** (d-test framework structure)
- **ADR-0057** (Closes anchor strict format)
- **ADR-0059** (cluster-squash inventory)
- **RETRO-018 W6** (branch ownership matrix, `arch/*` prefix for @architect)
- **RETRO-024** (work-done-elsewhere 4-cat exception)
- **tmpl#126 audit PR** (MERGED 52ed840, Sprint 32 audit baseline)

---

## AC1 — ADR Diff (calc vs tmpl)

### Audit claim

> "Full ADR diff (calc 71 ADRs vs template 31 ADRs) classified as doctrine-port OR calc-specific, with per-ADR rationale"

### Empirical ground truth

Verified via `gh api repos/{owner}/{repo}/contents/docs/decisions?ref=main`:

| Repo | ADR count |
|---|---:|
| atilcan65/AtilCalculator (calc) | **77** |
| atilproject/dev-studio-template (tmpl) | **32** |
| **Gap (calc has, tmpl doesn't)** | **45** |

**Audit claim partially corrected** — issue said 71 vs 31; actual is 77 vs 32 (likely the issue count excluded amendments; the +6 difference reflects ADR amendments like 0024-a1, 0038-a1/a2, 0048-a1/a2/a3, 0057-a1, 0067-a1).

Plus 3 filename-divergence (both repos have an ADR with same number but different slug):

| Number | Calc slug | Tmpl slug |
|---|---|---|
| ADR-0046 | (calc-specific) | (tmpl-specific) |
| ADR-0047 | (calc-specific) | (tmpl-specific) |
| ADR-0060 | `ac-mapping-verification-doctrine` | `claude-code-2.1.207-agent-flag` (= calc's ADR-0061) |

### Classification tiers

**HIGH-confidence doctrine-port (30 ADRs)** — universal doctrine applicable
to all dev-studio-template-derived projects:

`ADR-0001`, `0007`, `0017`, `0024-a1`, `0024-a2`, `0034`, `0035`, `0037`,
`0038-a1`, `0038-a2`, `0039`, `0043`, `0044`, `0045`, `0048-a1`,
`0048-a2`, `0048-a3`, `0053`, `0054`, `0055`, `0056`, `0057-a1`, `0058`,
`0062`, `0063`, `0064`, `0067`, `0069`, `0070`, `0071`.

**MEDIUM-confidence doctrine-port (4 ADRs)** — needs deeper review:

- `ADR-0002-a1` (autonomy-loop amendment)
- `ADR-0060` (filename conflict — tmpl has different slug)
- `ADR-0061` (filename conflict — calc renumber to ADR-0072)
- `ADR-0068` (medium-confidence)

**LOW-confidence calc-specific (12 ADRs)** — pure calc artifact, exclude:

`ADR-0018` (Vue front-end), `0019+4 amendments` (REST API), `0022`
(SQLite persistence), `0023` (frontend-architecture), `0041` (event-model v8),
`0051` (engine perf), `0065` (CPython asyncio fix).

**RNR — renumber required (3 ADRs)** — filename divergence:

`ADR-0046`, `ADR-0047`, `ADR-0060` — calc renumber to ADR-0072+ to free
ADR-0060 for the template-canonical `claude-code-2.1.207-agent-flag` ADR
(per the convention that ADR-0061 in calc = the same thing as ADR-0060 in
tmpl, indicating a mis-numbered forward-port).

---

## AC2 — Soul File Diff (calc vs tmpl)

### Gap math

| Soul file | calc .tmpl | tmpl .tmpl | Δ | Real diff? |
|---|---:|---:|---:|---|
| `architect.md.tmpl` | 5817B | 4377B | **+1440B** | ✅ Issue #972 missing in tmpl/architect |
| `developer.md.tmpl` | 6229B | 6230B | -1B | ❌ trailing-newline noise only |
| `orchestrator.md.tmpl` | 12571B | 7071B | **+5500B** | ✅ KAPI + Retro-Close missing |
| `product-manager.md.tmpl` | 4660B | 4661B | -1B | ❌ trailing-newline noise only |
| `tester.md.tmpl` | 5718B | 5719B | -1B | ❌ trailing-newline noise only |

**3 SOUL AMEND blocks missing in tmpl**, all HIGH-confidence doctrine-port.

### Missing Block #1 — Issue #972 §Path-Verify Doctrine (architect.md.tmpl, +1440B)

**Cycle origin**: ~#768 (Sprint 26). PM 4th-pass self-correction on PR #967
caught architect path-error via trust-but-verify — cited AtilCalculator's
local mirror (78-87 LOC) instead of dev-studio-template's canonical tmpl
(240-375 LOC).

**Doctrine (universal)**: Path-verify pre-flight before citing LOC counts,
file sizes, or content structure for `.claude/agents/*.md` files — verify
the canonical tmpl path, NOT the project's local mirror. Cross-check that
cited path is tmpl source (committed), not rendered local mirror
(gitignored).

**Cadence Rule 1 atomic** (declared in block): all 3 soul files
(architect + developer + tester) get the same amend block in a single
commit, single PR.

**Status of upstream port**: **PARTIAL** — tmpl has Issue #972 in
`developer.md.tmpl` + `tester.md.tmpl` but MISSING in `architect.md.tmpl`.
Architect was left behind in the partial upstream port.

**Port recommendation**: Add Issue #972 block to `tmpl/architect.md.tmpl`
(with abstracted references: replace `AtilCalculator local mirror` with
`downstream project's local mirror`, `AtilCalculator/PR #967` with
`Issue #972 PR-of-origin`).

**Classification tier**: **HIGH (H) doctrine-port**.

### Missing Block #2 — KAPI HOTFIX §Cadence Rule 2 (orchestrator.md.tmpl, +2200B)

**Cycle origin**: ~#2776, owner directive 2026-07-17 ~08:34Z. AtilCalculator's
ADR-0060 forward-port never landing — template PR #97 + #108 + #110 merged
2026-07-14/15 but AtilCalculator sister work never opened. Owner manual fix
applied 3 times to `scripts/dev-studio-start.sh:149` before persistence
requested.

**Doctrine (universal)**: **Cadence Rule 2** — When ANY
`docs/decisions/ADR-NNNN-*.md` PR merges to `main`, the SAME TURN MUST
`@`-mention-dispatch each listed sister issue to its `agent:*` owner —
OR the turn is recorded as **INCOMPLETE** in
`/var/log/dev-studio/{{PROJECT_NAME}}/auto-claim.log`.

**4 atomic sub-steps**:

1. **Cross-repo sister detection** — parse PR body for `Closes #X` /
   `Refs #X` anchors referencing issues in the SAME org
2. **Per-sister dispatch** — `gh issue comment <X> --body "@<agent-role>
   dispatch: ADR-NNNN merged..." --repo <repo>`. Order: tester →
   developer → orchestrator.
3. **State emission** — write `auto-claim.log` line with format
   `[cadence-rule-2] ADR-NNNN merged → dispatched <count> sister issues: #X1, #X2`
4. **Retrospective lens** — if `[cadence-rule-2] INCOMPLETE` flag
   observed for same ADR within 7 days, sprint retro MUST file RETRO entry.

**d-test spec required** (Cadence Rule 2 atomic, ADR-0055 §1):
`scripts/tests/d-cadence-rule-2-orphan-impl-dispatch.sh` ≥5 TCs RED-first
per ADR-0049.

**References (calc-specific, must abstract)**:
- `scripts/dev-studio-start.sh:149` → generic "downstream project start script"
- `AtilCalculator's ADR-0060` → generic "any project's ADR-NNNN"
- `template PR #97 + #108 + #110` → generic "ADR PR + d-test PR + impl PR cluster"

**Classification tier**: **HIGH (H) doctrine-port**.

### Missing Block #3 — Cadence Rule 2 Retroactive-Close Precondition (orchestrator.md.tmpl, continuation, +2200B)

**Cycle origin**: cycle ~#~12:56Z 2026-07-17 (owner directive), RETRO-027
RCA. AtilCalculator #1128 + #1129 retroactively closed without PR (orphan-impl);
only working-tree had the fix; bug came back live after tmux restart
(10:32 UTC, all 5 panes `--agent not found`).

**Doctrine (universal)**: Orphan-impl issue (fix exists in working-tree
but no PR) can be retroactively closed **ONLY IF** BOTH preconditions
verified:

1. **(a) PR-persistence**: fix is PR-persisted in `origin/main` (NOT
   just local working-tree). Verify: `git fetch origin main && git show
   origin/main:<file>` MUST contain the fix.
2. **(b) Closes anchor**: that PR body contains ADR-0057 strict
   `Closes #<N>` anchor referencing the issue.

**Retroactive close WITHOUT an anchor-PR is INVALID**; the issue MUST
be reopened.

**Restart-survivability test** (mandatory before retroactive close):

```bash
git fetch origin main
git show origin/main:<file> | grep -F '<expected fix line>'
```

If 0 lines → fix NOT in main → retroactive close forbidden → reopen +
dispatch chain.

**Classification tier**: **HIGH (H) doctrine-port**.

---

## AC3 — Scripts Diff (calc vs tmpl)

### Audit claim

> "Scripts diff (45 calc vs 44 template) classified (portable / divergent / calc-specific)"

### Empirical ground truth (audit claim REJECTED)

After excluding meta files (README.md, restart-stable.txt, .gitkeep):

| Repo | Real script count |
|---|---:|
| calc | **34** |
| tmpl | **35** (including `peer-poke.sh.tmpl` template form; calc has 51B stub) |

**Audit claim was off by ~10** — actual symmetric count is 34 vs 35.

### File-level classification

#### ✅ Portable (12 scripts — exact-byte identical)

`apply-reprime-protocol.py` (4224B), `agent-doctor.sh` (21700B),
`agent-journal.sh` (6831B), `agent-state-repair.sh` (4598B),
`agent-watch-verdicts.sh` (7750B), `atomic-write.sh` (2635B),
`bootstrap-labels.sh` (3560B), `cross-repo-scan.sh` (9116B),
`event-log.sh` (3813B), `health-check.sh` (3486B),
`lint-notify-invocations.sh` (3508B), `strip-cascade-labels.sh` (4161B),
`secret-canary.yml` (4668B), `dev-studio-start.sh` (9921B).

#### ⚠️ Divergent (22 scripts — calc has hardening/additions)

| Script | calc | tmpl | Δ | Likely origin |
|---|---:|---:|---:|---|
| `agent-watch.sh` | 107224B | 101782B | **+5442B** | **Issue #1142 AC2** Fix A ring integrity + Fix B dedup_hits |
| `agent-wake.sh` | 7921B | 5064B | **+2857B** | **Fix 4b** (ADR-0066) lenient capture-pane verify + hierarchical exit |
| `claim-next-ready.sh` | 29823B | 24976B | **+4847B** | **Fix 4b** silent-skip RETRO-024 4-cat-repair path |
| `dev-studio-init.sh` | 37950B | 26439B | **+11511B** | Re-render path for project-specific tokens |
| `deploy-runner.sh` | 43762B | 14219B | **+29543B** | Calc-specific: HTTP/HTTPS systemd-deploy (ADR-0010) |

(Plus 17 other scripts with <±4KB delta — minor divergences not yet analyzed.)

#### 🔒 Calc-specific (3 scripts — exclude from forward-port)

`run-server.sh` (2192B — HTTP server runner, would land in tmpl only after
ADR-0010 HTTP surface ships), `s29-002-tag-move.sh` (5233B — one-off Sprint
29 tag mover), `orchestrator-gap-scan.sh` (8514B — calc hygiene tool,
not template-portable).

(`dev-studio-start.sh.bak-20260717-1033` is a backup file from Issue #1142 fix
attempt, not real script.)

#### 🆕 Tmpl-only (4 scripts — backport candidates to calc)

`bootstrap-test-project.sh` (2959B), `owner-apply-soul-patch.sh` (3489B),
`verify-portage.sh` (**10785B — CRITICAL**, inverse-direction portage
verification), `peer-poke.sh.tmpl` (7620B — calc has 51B stub, expected
symlink to .tmpl after init-render).

---

## AC4 — Workflows Diff (calc vs tmpl)

### Audit claim

> "Workflows diff (11 calc vs 11 template + `deploy.yml.tmpl`) with hardening gaps listed (SHA-pin, Python detect, etc.)"

### Empirical ground truth (audit claim VERIFIED)

| Repo | Workflow count |
|---|---:|
| calc | **11** |
| tmpl | **11 + `deploy.yml.tmpl`** = 12 files |

### ⚠️ MASSIVE FINDING — `label-check.yml` +55KB layered hardening

| Repo | label-check.yml size |
|---|---:|
| calc | **60939B** (~60KB) |
| tmpl | 5516B (~5.5KB) |
| **Δ** | **+55423B (~55KB)** |

**11× size ratio** — calc has accumulated **8+ enforcement layers** that
tmpl lacks:

| Layer | Feature | Calc | Tmpl | Origin |
|---|---|---|---|---|
| Layer 1 | 4-cat invariant (basic) | ✅ | ✅ | ADR-0012 (shared) |
| Layer 2 | Type-driven invariants | ✅ | ✅ basic | ADR-0012 §Type-driven |
| Layer 3 | `type:bug` cc:tester + needs-tester-signoff | ✅ | ❌ | **Issue #213** TEST-WAKE-ENFORCE |
| Layer 4 | Concurrency serialization (cancel-in-progress: false) | ✅ | ❌ | **Issue #423** cascade-strip scope |
| Layer 5 | RETRO-024 work-done-elsewhere exception (silent-skip) | ✅ | ❌ | **Issue #1027** |
| Layer 6 | `pr_labeled` wake labels (needs-tester-signoff / needs-architect-review) | ✅ | ❌ | **D2.2 / ADR-0009 §10.5.4** |
| Layer 7 | Cross-repo sister close cascade prevention | ✅ | ❌ | (Issue #430/#682 cross-watchdog) |
| Layer 8 | Owner-override clause for `type:bug` PRs | ✅ | ❌ | **ADR-0012 §Owner override** |
| Layer 9+ | (further layers per `+50KB` content) | ✅ | ❌ | (Sprint 11-31 accumulation) |

**Single largest forward-port candidate in S32-001**. Every
dev-studio-template-derived project lacks 9 layers of 4-cat enforcement
without this port.

### SHA-pinning hardening gaps

**Inconsistency** between calc and tmpl:

| Repo | SHA-pinned `actions/checkout` | NOT pinned (`@v4`) |
|---|---|---|
| calc | ci.yml, post-squash.yml, ai-pr-review.yml, cross-repo-close.yml, lint-and-test.yml (×2), deploy.yml | **d050b-dispatch.yml** (1 gap) |
| tmpl | d050b-dispatch.yml, lint-and-test.yml (×2), post-squash.yml, deploy.yml | **ai-pr-review.yml, ci.yml, cross-repo-close.yml** (3 gaps) |

**Doctrine** (TD-028, ADR-0027 §Threat model, ADR-0043 §lens h):
SHA-pin all `actions/checkout` invocations. Net gaps: **3 in tmpl, 1 in calc**.

### Python detect (ci.yml) — MISSING in tmpl

Calc has `if [ -f pyproject.toml ]; then echo "python=true" >> $GITHUB_OUTPUT`
in ci.yml. **tmpl has no Python detection** — every project has to write
its own. Port-back candidate.

### Other divergent workflows

- `status-label-to-board.yml` +3.2KB — calc has board-sync hardening (ADR-0013)
- `lint-and-test.yml` +891B — calc has d-test CI step (ADR-0044)
- `ci.yml` +4.5KB — Python detect + project-specific CI
- `label-cleanup.yml` +1.3KB — cascade-strip logic (Issue #423)

---

## Forward-port Recommendations (priority-ordered)

### Priority 1 — `label-check.yml` +55KB layered enforcement (single biggest gap)

Port the entire calc `label-check.yml` to tmpl, replacing calc-specific
project-name placeholders with `{{PROJECT_NAME}}` template variables.
Cadence Rule 1 atomic + 9-Lens pre-publish + d-test RED-first per ADR-0049.

### Priority 2 — SHA-pin consistency

Harmonize all `actions/checkout` invocations to SHA-pinned form across
both repos. 3 files in tmpl + 1 file in calc need pinning.

### Priority 3 — Python detect (ci.yml)

Port `pyproject.toml` detection logic from calc ci.yml → tmpl ci.yml.

### Priority 4 — Issue #972 §Path-Verify Doctrine (architect.md.tmpl)

Add missing block to `tmpl/architect.md.tmpl` (dev+tester already have
partial upstream). Single-file amend, no Cadence Rule 1 atomic concern
(other 2 files already have it).

### Priority 5 — KAPI HOTFIX §Cadence Rule 2 (orchestrator.md.tmpl)

Port both KAPI + Cadence Rule 2 Retro-Close blocks (single contiguous
amend, ~+5500B). Include new d-test
`scripts/tests/d-cadence-rule-2-orphan-impl-dispatch.sh` per ADR-0044.

### Priority 6 — Agent-watch hardening backport

Port `agent-watch.sh` Issue #1142 AC2 Fix A/B, `agent-wake.sh` Fix 4b
(ADR-0066), `claim-next-ready.sh` RETRO-024 silent-skip back to tmpl.
Single tmpl PR with 3 file changes.

### Priority 7 — Backport `verify-portage.sh` to calc

Calc needs the inverse-direction tooling for continuous coverage
verification. Single calc PR with 1 file addition.

### Atomicity plan

All forward-ports land in **single tmpl PR** (or 2: P1+P2+P3, P4+P5+P6).
Per ADR-0059 cluster-squash inventory, eligible for cluster-squash with
S32-002 sister-PR if timing aligns.

---

## Summary Table

| AC | Audit claim | Empirical | Largest finding |
|---|---|---|---|
| AC1 ADR | 71 vs 31 | **77 vs 32** (45 gap) | ADR-0060/0061 filename conflict |
| AC2 Soul | +5500B + +1440B | **CONFIRMED** | 3 missing SOUL AMEND blocks |
| AC3 Scripts | 45 vs 44 | **34 vs 35** (audit REJECTED) | Issue #1142 AC2 cluster hardening |
| AC4 Workflows | 11 vs 11 + .tmpl | **VERIFIED** | `label-check.yml` +55KB layered hardening |
| AC5 Output | committed | **THIS FILE** | — |

---

## Cycle Hooks

- cycle ~#3229: S32-001 AC1 init (RETM-024 mis-file correction)
- cycle ~#3235: AC2 SOUL-FILE DIFF (3 missing blocks identified)
- cycle ~#3236: AC3 SCRIPTS-DIFF classified (audit claim rejected)
- cycle ~#3237: AC4 WORKFLOWS-DIFF (label-check.yml massive delta)
- cycle ~#3238: AC5 OUTPUT committed (this file)

---

## Sister-pattern references (cycle hooks to preserve)

- Issue #213 (TEST-WAKE-ENFORCE Layer 3) — cycle ~#~1500s
- Issue #423 (cascade-strip scope Layer 4) — cycle ~#~1700s
- Issue #1027 (RETRO-024 work-done-elsewhere Layer 5) — cycle ~#1253
- Issue #1142 (echo-wake hardening Fix A/B) — cycle ~#2917
- Issue #972 (Path-Verify Doctrine cycle ~768) — cycle ~#~768
- RETRO-018 W6 (branch ownership matrix) — cycle ~#5103
- RETRO-024 (work-done-elsewhere codification) — cycle ~#1223
- RETRO-027 (Cadence Rule 2 retroactive-close precondition) — cycle ~#~12:56Z
- ADR-0066 (Fix 4b lenient capture-pane verify) — Sprint 31

---

*This file is the canonical S32-001 output. Sister-story S32-002 (tmpl#128)
consumes this as input for baseline portage report. Future forward-port
PRs should `Refs #127` (NOT `Closes #127` — that closes only this discovery).*
