# d-test INDEX — RETRO-008 §11 registry (tmpl local)

> **Sister-pattern home:** RETRO-008 §11 (d-test persistence), ADR-0049 (d-test framework), ADR-0044 (TDD RED contract).
> **Spec origin:** STORY-S28-003 AC4 forward-port (`scripts/tests/d983-s28-003-forward-port-parity.sh` registration).
> **Purpose:** Persistent registry of d-tests specific to STORY-S28-003 forward-port parity. Pre-existing d-tests (d015, d024, d025, d027, d028, d029, d031, d032, d033, d034, d046, d047, d068b, dreg, e2e-pilot, faz5-smoke, state-schema-smoke) are tracked locally but their full INDEX rows live in `AtilCalculator/scripts/tests/INDEX.md` (the originating sister-pattern project) — see calc INDEX for sister coverage.

## d983 — STORY-S28-003 forward-port parity ✅ ACTIVE

| Field | Value |
|---|---|
| **Story** | [STORY-S28-003 #983](https://github.com/atilproject/dev-studio-template/issues/...) *(closes on PR merge — fill post-merge)* |
| **Source-of-truth sister** | `AtilCalculator/scripts/tests/INDEX.md` d983 row |
| **Test file** | `scripts/tests/d983-s28-003-forward-port-parity.sh` |
| **TCs** | **5 TCs (RED-first sister-pattern to ADR-0049 ≥5 invariant):** TC1 tmpl `claim-next-ready.sh` declares `--wip-count-only` flag (Issue #552 dual mechanism — calc-specific); TC2 tmpl `claim-next-ready.sh` has `WIP_COUNT_ONLY` structural handling; TC3 tmpl `claim-next-ready.sh` LOC ≥ calc's (forward-port never strips — Sister Story SemVer invariant); TC4 tmpl `agent-watch.sh` has Event Model v4 marker `issue_comment_mention` (ADR-0017 sister-invariant); TC5 tmpl `agent-watch.sh` has Event Model v6.2 marker `issue_assigned_any_status` (Issue #113 silent-drop closure) |
| **Sister-pattern** | `d031-claim-next-ready.sh` (claim-next-ready base Layer 2 fake-gh factory — DIRECT sister, same `scripts/claim-next-ready.sh` interface); `d052-agent-watch-hardening.sh` (agent-watch hardening — sister scope, parallel tc pattern); ≥2 sister-pattern coverage per ADR-0049 §Sister-pattern met (d031 + d052 = 2 members) |
| **Run** | `bash scripts/tests/d983-s28-003-forward-port-parity.sh` |
| **Cadence Rule 1 atomic** | Single-commit cluster: `scripts/claim-next-ready.sh` (+270 LOC) + `scripts/agent-watch.sh` (+1039 LOC) + `scripts/tests/d983-s28-003-forward-port-parity.sh` (new, 135 LOC) + `scripts/tests/INDEX.md` (new, this entry) |

## d081 — STORY-S28-007 Auto-Verdict-By hook port ✅ ACTIVE

| Field | Value |
|---|---|
| **Story** | [STORY-S28-007 #988](https://github.com/atilproject/AtilCalculator/issues/988) *(closes on PR merge — fill post-merge)* |
| **Source-of-truth sister** | `atilproject/AtilCalculator/scripts/peer-poke.sh` (commit 981a9c1d, 6284B, PR #296 reference impl + ADR-0024 amendment §Path 2) |
| **Test file** | `scripts/tests/d081-auto-verdict-by-hook.sh` |
| **Scope (Path A per Issue #991 verdict)** | tmpl port of `peer-poke.sh` wrapper script + Auto-Verdict-By hook. Path 1 (Layer 5 YAML hook in `.github/workflows/label-check.yml`) NOT in this test — architect-owned territory per file ownership matrix. |
| **TCs** | **5 TCs (RED-first per ADR-0044 ≥3 baseline):** TC1 peer-poke.sh.tmpl file exists + executable (6284B parity-check vs calc source); TC2 verdict-by + add-label pair invocation present (`_pair_verdict_by` function + `gh (issue\|pr) edit --add-label`); TC3 atomic pairing doctrine — `labels_to_add="cc:${role} ${verdict_by_label}"` single-line concat + `gh edit ... $labels_to_add` atomic invocation (per ADR-0015 §Sıra zorunlu + ADR-0024 §Path 2); TC4 `VERDICT_BY_DEFAULT_HOURS=24` default deadline (env-var override allowed); TC5 silent-skip idempotency on verdict-by:<ts> already present (no double-deadline overwrite, per ADR-0024 §3 + §4) |
| **Sister-pattern** | `d296-peer-poke-helper.sh` (calc-side, source-of-truth — argument shape contract); `d081-auto-verdict-by-hook.sh` (calc-side, identical contract); ≥2 sister-pattern coverage per ADR-0049 §Sister-pattern met (d296 + d081 calc-side = 2 members) |
| **Run** | `bash scripts/tests/d081-auto-verdict-by-hook.sh` |
| **Cadence Rule 1 atomic** | Single-commit cluster: `scripts/peer-poke.sh.tmpl` (new, 6284B ported from `atilcan65/AtilCalculator/scripts/peer-poke.sh` 981a9c1d) + `scripts/tests/d081-auto-verdict-by-hook.sh` (new, ~150 LOC) + `scripts/tests/INDEX.md` (this entry) |
| **Cross-references** | Issue #988 (claim), Issue #991 (design-drift + verdict — Path A approved), ADR-0024 amendment §Path 2 (Auto-Verdict-By hook contract), ADR-0015 (atomic handoff doctrine), ADR-0044 (RED-first TDD), PR #296 (calc source-of-truth peer-poke.sh impl) |

---

## s29-005 — STORY-S29-005 verify-portage script ✅ ACTIVE

| Field | Value |
|---|---|
| **Story** | [STORY-S29-005 #1017](https://github.com/atilcan65/AtilCalculator/issues/1017) |
| **Source-of-truth sister** | `AtilCalculator/docs/sprints/sprint-29/00-plan.md` §S29-005 + `AtilCalculator/docs/sprints/sprint-28/02-template-launcher-audit-2026-07-13.md` §4.6 (recipe source) |
| **Test file** | `scripts/tests/s29-005-verify-portage.sh` |
| **Production file** | `scripts/verify-portage.sh` (new, ~280 LOC, sister-pattern to dev-studio-init.sh + e2e-pilot.sh) |
| **TCs** | **8 TCs (RED-first per ADR-0044 ≥5 baseline):** TC1 script exists at canonical path (AC1); TC2 bash -n syntax check passes; TC3 --help exits 0 + prints usage (sister-pattern to dev-studio-init.sh); TC4 --dry-run exits 0 without real gh repo create/delete calls (AC3 idempotent print-mode); TC5 --dry-run --json output is valid JSON with `category_gaps` dict (AC4); TC6 header documents `# Exit codes:` section with ≥6 codes (AC6); TC7 idempotency — two consecutive --dry-run runs both exit 0 (AC2); TC8 trap-based cleanup handler wired (`trap` + `cleanup()` function, AC1 step 5) |
| **Sister-pattern** | `e2e-pilot.sh` (rendering workflow + idempotency note, sister-pattern #1); `dev-studio-init.sh` (helper-function conventions + --dry-run + --help flag, sister-pattern #2); `d031-claim-next-ready.sh` (atomic + idempotent patterns, Layer 2 sister); `d095-post-org-migration-clone-urls.sh` (AtilCalculator URL hygiene, Sprint 22 PIVOT origin); `d983-s28-003-forward-port-parity.sh` (S28-003 cross-tmpl sister — first sNN-pattern d-test in this INDEX); ≥2 sister-pattern coverage per ADR-0049 §Sister-pattern met (e2e-pilot + dev-studio-init = 2 members) |
| **Run** | `bash scripts/tests/s29-005-verify-portage.sh` |
| **Cadence Rule 1 atomic** | Single-commit cluster: `scripts/verify-portage.sh` (new, ~280 LOC) + `scripts/tests/s29-005-verify-portage.sh` (new, 8 TCs) + `scripts/tests/INDEX.md` (this entry) |
| **Cross-references** | Issue #1017 (S29-005 tracker), Issue #1020 (cross-repo scope Q, RESOLVED 2026-07-13T09:00:16Z Option A — pattern ratified end-to-end by PR #4 + this PR), docs/sprints/sprint-29/00-plan.md §S29-005, ADR-0044 (RED-first TDD doctrinal home), ADR-0049 (d-test framework, ≥5 TCs baseline), ADR-0055 §1 Cadence Rule 1 atomic, Sister-PR: atilproject/dev-studio-launcher#4 (S29-003 cross-repo workstream precedent) |
| **Sprint 29 cross-repo workstream pattern** | This is the SECOND cross-repo PR (after launcher#4) following Issue #1020 Option A: design lives in AtilCalculator (issue tracker #1017), impl lands here (dev-studio-template) with body anchor `Refs atilcan65/AtilCalculator#1017`. Consumer: S29-014 (orchestrator, sprint-end verification re-runs verify-portage.sh to produce concrete gap numbers). |

---

## Path-resolution decision (STORY-S28-003 open question owner: developer)

> **Decision:** Keep the literal `atilproject/AtilCalculator` references in
> `scripts/agent-watch.sh` line 96 (`# fallback ("atilproject/AtilCalculator")`)
> as a **template placeholder**. Projects cloned from tmpl override via:
>
> 1. `GITHUB_REPO=owner/name` env var (highest precedence), OR
> 2. `gh repo view --json nameWithOwner` auto-detection (works in CI), OR
> 3. `git remote get-url origin` parse (no API calls — works offline), OR
> 4. Hardcoded fallback (only triggers when 1-3 all fail — extremely rare).
>
> Rationale: the literal is downstream-render-stable (init.sh does not edit
> script content) and serves as a visible marker for projects to grep+replace
> post-clone. Calc continues to use the same literal (no drift, sister-pattern
> maintained). Future-proofing option (`${GITHUB_REPO:-atilproject/dev-studio-template}`)
> was considered but deferred — would change behavior for existing tmpl-script
> consumers and requires its own d-test per ADR-0044 RED-first.

## s29-004 — STORY-S29-004 status-label-to-board disabled ✅ ACTIVE

| Field | Value |
|---|---|
| **Story** | [STORY-S29-004 #1016](https://github.com/atilcan65/AtilCalculator/issues/1016) |
| **Source-of-truth design** | [PR atilcan65/AtilCalculator#1026](https://github.com/atilcan65/AtilCalculator/pull/1026) — `docs/designs/STORY-S29-004-design.md` (path a — DISABLE via `if: false`, owner-ratified by merge) |
| **Test file** | `scripts/tests/s29-004-status-label-to-board-disabled.sh` |
| **Production file** | `.github/workflows/status-label-to-board.yml` (modified — `if: false` added to `sync-status` job + attribution comment) |
| **TCs** | **7 TCs (RED-first per ADR-0044, design narrowed from ≥5 baseline because verification surface is narrow: 1 file, 1 boolean state):** TC1 file exists at canonical path (AC2: not deleted, path a preserves file); TC2 sync-status job has job-level `if: false` literal (AC2); TC3 YAML parses + `jobs.sync-status.if == False` semantically (drift defense); TC4 `runs-on: ubuntu-latest` preserved (S29-001 sister-pattern: not stripped here); TC5 STORY-S29-004 attribution comment present (regression pin); TC6 workflow name + `on:` triggers unchanged; TC7 permissions block (3 lines) preserved |
| **Sister-pattern** | `s29-005-verify-portage.sh` (Sprint 29 cross-repo workstream pattern, identical issue-tracker-in-calc / impl-in-tmpl shape, ADR-0055 §1 Cadence Rule 1 atomic precedent); `d015-dev-idle-prevention.sh` (TC pattern, pass/fail/section idiom); `d983-s28-003-forward-port-parity.sh` (≥2 sister-pattern coverage per ADR-0049); ≥2 sister-pattern coverage met (s29-005 + d015 = 2 members) |
| **Run** | `bash scripts/tests/s29-004-status-label-to-board-disabled.sh` |
| **Cadence Rule 1 atomic** | Single-commit cluster: `.github/workflows/status-label-to-board.yml` (modified, +10 LOC comment + `if: false`) + `scripts/tests/s29-004-status-label-to-board-disabled.sh` (new, ~150 LOC, 7 TCs) + `scripts/tests/INDEX.md` (this entry) |
| **Cross-references** | Issue #1016 (story), PR atilcan65/AtilCalculator#1026 (design, merged 2026-07-13T13:01:58Z), `docs/sprints/sprint-28/02-template-launcher-audit-2026-07-13.md` §3.1 + §6.2 B-06 (audit origin), ADR-0013 (status-label → board sync), ADR-0014 (PROJECT_TOKEN), TD-075 + F-08 + F-10 (silent-RED defense family), RETRO-023 (Issue #1024 — cross-repo workstream codification) |
| **Sprint 29 cross-repo workstream pattern** | Issue tracked in `atilcan65/AtilCalculator` (#1016), impl lands here (`atilproject/dev-studio-template`). PR body anchors `Refs atilcan65/AtilCalculator#1016`. Consumer: S29-014 (orchestrator) verifies CI hygiene post-merge. Sister: S29-001 (Issue #1013, same shape, follows this PR). |

---

## s29-001 — STORY-S29-001 workflow self-hosted 4-tuple ✅ ACTIVE

| Field | Value |
|---|---|
| **Story** | [STORY-S29-001 #1013](https://github.com/atilcan65/AtilCalculator/issues/1013) (load-bearing critical per owner directive #5) |
| **Source-of-truth design** | [PR atilcan65/AtilCalculator#1021](https://github.com/atilcan65/AtilCalculator/pull/1021) — `docs/designs/STORY-S29-001-design.md` (229 lines, 9-Lens per ADR-0045, owner-ratified by merge 2026-07-13T13:01:50Z) |
| **Test file** | `scripts/tests/s29-001-workflow-self-hosted.sh` |
| **Production files** | `.github/workflows/{ai-pr-review,ci,cross-repo-close,label-check,label-cleanup,secret-canary,status-label-to-board}.yml` — 7 files modified, 8 jobs migrated (ci.yml has 2 jobs), `runs-on:` 4-tuple. `.github/workflows/deploy.yml.tmpl` NOT modified (AC2 preserved). |
| **TCs** | **8 TCs (RED-first per ADR-0049 ≥5 baseline):** T1 all 7 target files exist (AC1); T2 all 8 runs-on occurrences are 4-tuple, 0 ubuntu-latest (AC1); T3 ci.yml has both jobs on 4-tuple (design R-2 two-job ambiguity); T4 deploy.yml.tmpl preserved at `runs-on: self-hosted` (AC2 no regression); T5 exactly 2 distinct runs-on values across `.github/workflows/` (AC3 verification); T6 [DEFERRED] SHA-pin regression (TD-028 sister workstream, out of S29-001 scope per design R-3); T7 all 7 files parse as valid YAML (drift defense); T8 concurrency + permissions + secrets blocks preserved in sample files (R-6) |
| **Sister-pattern** | `s29-004-status-label-to-board-disabled.sh` (parallel sprint PR, same cross-repo workstream shape — design in calc, impl in tmpl); `d015-dev-idle-prevention.sh` (TC pass/fail/section idiom); `d983-s28-003-forward-port-parity.sh` (≥2 sister-pattern coverage per ADR-0049); ≥2 sister-pattern coverage met (s29-004 + d015 = 2 members) |
| **Run** | `bash scripts/tests/s29-001-workflow-self-hosted.sh` |
| **Cadence Rule 1 atomic** | Single-commit cluster: 7 × `.github/workflows/{name}.yml` (each 1 line `runs-on:` migrated) + `scripts/tests/s29-001-workflow-self-hosted.sh` (new, ~210 LOC, 8 TCs) + `scripts/tests/INDEX.md` (this entry) |
| **Cross-references** | Issue #1013 (story), PR atilcan65/AtilCalculator#1021 (design, merged 2026-07-13T13:01:50Z), `docs/sprints/sprint-28/02-template-launcher-audit-2026-07-13.md` §5.2, ADR-0030 (self-hosted-runner LAN deploy), ADR-0049 (d-test framework), ADR-0045 (9-Lens pre-publish), TD-075 (silent-RED sister — d-test must be wired, see R-1), RETRO-023 (Issue #1024 — cross-repo workstream codification) |
| **Sister PR** | [dev-studio-template#72 (S29-004)](https://github.com/atilproject/dev-studio-template/pull/72) — squashed 2026-07-13T14:20:32Z (sha 6d9d3f8). PR #73 (this) rebased post-#72-merge at 2026-07-13T14:50Z: status-label-to-board.yml now has BOTH `if: false` (from #72) AND 4-tuple runs-on (from #73); if:false is no-op-as-runs-on-moot, but keeps file consistent. INDEX.md d-test entries: s29-004 added by #72, s29-001 added by #73 (this rebase appends s29-001 at end; orchestrator suggested "adjust ordering/IDs as needed" — kept chronological append for minimal-diff rebase). d-test s29-004-status-label-to-board-disabled.sh T4 updated: was `runs-on: ubuntu-latest` literal check, now `runs-on:` key present (any value); if:false makes the specific value irrelevant for S29-004 invariant. |
| **Sprint 29 cross-repo workstream pattern** | Issue tracked in `atilcan65/AtilCalculator` (#1013), impl lands here (`atilproject/dev-studio-template`). PR body anchors `Refs atilcan65/AtilCalculator#1013`. Consumer: S29-014 (orchestrator) verifies CI minutes-burn reduction post-merge. Sister: S29-004 (Issue #1016, same shape, parallel PR). |

---

## s29-008 — STORY-S29-008 forward-port 7 universal scripts ✅ ACTIVE

| Field | Value |
|---|---|
| **Story** | [STORY-S29-008 #1033](https://github.com/atilcan65/AtilCalculator/issues/1033) (Sprint 29 Wave 2, P1, dev lane — scripts/ owner per file ownership matrix) |
| **Source-of-truth design** | [Sprint 29 W2 plan §S29-008](https://github.com/atilcan65/AtilCalculator/blob/main/docs/sprints/sprint-29/00-plan.md) — AC1-AC4 explicit list per arch v3 §G S29-008 revision |
| **Test files** | `scripts/tests/s29-008-{audit-project-refs,cross-repo-scan,proactive-board-scan,agent-watch-verdicts,lint-notify-invocations,strip-cascade-labels,init-template-repo}.sh` (7 d-tests, 5 TCs each per ADR-0049 ≥3 baseline) |
| **Production files** | `scripts/{audit-project-refs,cross-repo-scan,proactive-board-scan,agent-watch-verdicts,lint-notify-invocations,strip-cascade-labels,init-template-repo}.sh` — 7 universal scripts ported from AtilCalculator. Project-specific scripts (`run-server.sh`, `ops/apply-vm-hardening.sh`) NOT ported per AC2. |
| **TCs (per d-test, 7 tests × 5 TCs = 35 TCs total)** | **TC1**: script exists at canonical path + executable (AC1); **TC2**: `bash -n` syntax check passes (AC2); **TC3**: `--help` exits 0 with usage info (AC3); **TC4**: idempotency — two consecutive `--help` runs yield identical exit code (AC4); **TC5**: path parameterization — atilcan65 absent or `${ORG}` env var present (AC3). Per-script: verdict patterns (agent-watch-verdicts), 4-cat labels (proactive-board-scan), 6 role names (lint-notify), cascade-prone labels (strip-cascade), placeholder substitution (init-template-repo), AGENT_CROSS_REPOS env var (cross-repo-scan), `${ORG}` env var (audit-project-refs). |
| **Sister-pattern** | `d105-audit-project-refs.sh` (AtilCalculator sister — same audit-project-refs surface); `d049-cross-repo-scan.sh` (AtilCalculator — ADR-0047 Part 2); `d062-proactive-board-scan-workstream.sh` (AtilCalculator — board anomaly sweep); `d039-lint-notify-invocations.sh` (AtilCalculator — Issue #320); `s29-005-verify-portage.sh` (template sister — S29-005 verify-portage portage pattern); `s29-001-workflow-self-hosted.sh` + `s29-004-status-label-to-board-disabled.sh` (template sisters — Sprint 29 Wave 1 cross-repo pattern precedent). ≥2 sister-pattern coverage met (d105 + s29-005 = 2 members). |
| **Run** | `bash scripts/tests/s29-008-{audit-project-refs,cross-repo-scan,proactive-board-scan,agent-watch-verdicts,lint-notify-invocations,strip-cascade-labels,init-template-repo}.sh` |
| **Cadence Rule 1 atomic** | Single-commit cluster: 7 × `scripts/<name>.sh` (each ~95-250 LOC ported from AtilCalculator + path parameterization) + 7 × `scripts/tests/s29-008-<name>.sh` (new, ~140-180 LOC each, 5 TCs each) + `scripts/tests/INDEX.md` (this entry). Total ~16 files in single commit cluster. |
| **Path parameterization (AC3)** | `atilcan65` → `${ORG:-atilproject}` (canonical org for dev-studio-template); `AtilCalculator` → `${PROJECT_NAME:-AtilCalculator}` env var pattern in audit-project-refs.sh. Override per downstream: `ORG=myorg PROJECT_NAME=MyProject bash scripts/<name>.sh`. Sister-pattern: d095 post-org-migration-clone-urls.sh (Sprint 22 PIVOT). |
| **Cross-references** | Issue #1033 (story), `docs/sprints/sprint-29/00-plan.md` §3.Wave 2 / S29-008 (415 lines, 4 ACs, arch v3 §G corrected count), ADR-0012 (4-cat invariant — 4-cat sister-pattern in d-tests), ADR-0044 (RED-first TDD), ADR-0049 (d-test framework ≥3 baseline), ADR-0055 §1 (Cadence Rule 1 atomic), ADR-0057 (`Refs #N` cross-repo anchor), RETRO-023 (Issue #1024 — cross-repo workstream codification) |
| **Sprint 29 cross-repo workstream pattern** | Issue tracked in `atilcan65/AtilCalculator` (#1033), impl lands here (`atilproject/dev-studio-template`). PR body anchors `Refs atilcan65/AtilCalculator#1033`. Consumer: S29-014 (orchestrator) verifies parity ≥90% (33 → 38-40 scripts) post-merge. Sister: S29-009 (#1034 — 3 sub-dirs), S29-011 (#1036 — ISSUE_TEMPLATE parity), all P1/P2 dev-lane. S29-007 (#1032) BLOCKED on S29-006 ADR port (ADR-0055 §Cadence Rule 1 atomic — base ADR before amendments). |
