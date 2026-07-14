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
| **TCs** | **6 TCs (RED-first per ADR-0044 ≥3 baseline):** TC1 peer-poke.sh.tmpl file exists + executable (6284B parity-check vs calc source); TC2 verdict-by + add-label pair invocation present (`_pair_verdict_by` function + `gh (issue\|pr) edit --add-label`); TC3 atomic pairing doctrine — `labels_to_add="cc:${role} ${verdict_by_label}"` single-line concat + `gh edit ... $labels_to_add` atomic invocation (per ADR-0015 §Sıra zorunlu + ADR-0024 §Path 2); TC4 `VERDICT_BY_DEFAULT_HOURS=24` default deadline (env-var override allowed); TC5 silent-skip idempotency on verdict-by:<ts> already present (no double-deadline overwrite, per ADR-0024 §3 + §4); TC6 `gh label view` + `gh label create --force` pre-flight guard (Issue #1070 — pre-create verdict-by:<ts> label if absent in repo catalog before `gh (issue\|pr) edit --add-label`) |
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

---

## s29-009 — STORY-S29-009 forward-port 3 scripts/ sub-dirs ✅ ACTIVE
| Field | Value |
|---|---|
| **Story** | [STORY-S29-009 #1034](https://github.com/atilcan65/AtilCalculator/issues/1034) (Sprint 29 Wave 2, P1, dev lane — scripts/ owner) |
| **Source-of-truth design** | [Sprint 29 W2 plan §S29-009](https://github.com/atilcan65/AtilCalculator/blob/main/docs/sprints/sprint-29/00-plan.md) — AC1 3 sub-dirs, AC2 systemd/ops NOT ported, AC3 README conditional |
| **Test files** | `scripts/tests/s29-009-{cluster-lag-detector,label-hygiene,branch-base-check}.sh` (3 d-tests, 5 TCs each = 15 TCs per ADR-0049 ≥3 baseline) |
| **Production files** | `scripts/post-squash/{cluster-lag-detector.sh,label-hygiene.sh}` (2 scripts) + `scripts/pre-push/branch-base-check.sh` (1 script). Sub-dir `scripts/kickoff/` already present in template as .tmpl files (5 agent reminder templates with `{{HEARTBEAT_DIR}}` placeholder substitution via dev-studio-init.sh) — per S29-009 AC1 deliverable framework, kickoff/ counted as already-ported sister-pattern. |
| **TCs (per d-test, 5 TCs each)** | **TC1**: script exists at canonical path + executable (AC1); **TC2**: `bash -n` syntax check passes (AC2); **TC3**: doctrine/contracts referenced (ADR-0059 + WINDOW_LOOKBACK_SEC + CLUSTER_SIZE_THRESHOLD for cluster-lag; RETRO-009 §3 + STALE_STATUSES_REGEX + status:done for label-hygiene; RETRO-009 §1 + chain-dep + git rebase for branch-base); **TC4**: idempotency (cluster-lag silent_skip on non-cluster exit 0; label-hygiene empty input exit 2 consistent; branch-base empty stdin exit 0); **TC5**: per-script contract (4-cat preserved for label-hygiene, git pre-push stdin+ancestor+commit-scan for branch-base, REPO env var presence for cluster-lag). |
| **Sister-pattern** | `d064-cluster-lag.sh` (AtilCalculator sister, ADR-0059 §1 d-test); `d061-label-hygiene.sh` (AtilCalculator sister, RETRO-009 §3 d-test, 9 TCs); `d060-branch-base-check.sh` (AtilCalculator sister, RETRO-009 §1 d-test, 9 TCs); `s29-005-verify-portage.sh` + `s29-008-{audit-project-refs,...}.sh` (template sisters — Sprint 29 W1+W2 cross-repo pattern precedent). ≥2 sister-pattern coverage met (d064 + d061 = 2 members). |
| **Run** | `bash scripts/tests/s29-009-{cluster-lag-detector,label-hygiene,branch-base-check}.sh` |
| **Cadence Rule 1 atomic** | Single-commit cluster: 3 × `scripts/<sub-dir>/<name>.sh` (each ~95-175 LOC ported from AtilCalculator + path parameterization on cluster-lag-detector comments) + 3 × `scripts/tests/s29-009-<name>.sh` (new, ~170-220 LOC each, 5 TCs each) + `scripts/tests/INDEX.md` (this entry). Total 7 files in single commit cluster. |
| **Path parameterization (AC3)** | `atilproject/AtilCalculator` → `atilproject/dev-studio-template` in cluster-lag-detector.sh usage comments (line 30-32). Label-hygiene.sh and branch-base-check.sh have no org-specific refs (use gh CLI for current repo + git for branch detection). Sister-pattern: d095 post-org-migration-clone-urls.sh. |
| **AC2 compliance (NOT ported)** | AtilCalculator-specific `install/systemd/dev-studio-watcher@.service` NOT ported (template has its own systemd per file ownership matrix — human-only territory); AtilCalculator-specific `ops/` (vm-hardening) NOT ported. Sister-pattern: file ownership matrix in CLAUDE.md §File ownership. |
| **Cross-references** | Issue #1034 (story), `docs/sprints/sprint-29/00-plan.md` §3.Wave 2 / S29-009 (AC1-AC3), ADR-0012 (4-cat invariant — sister-pattern in d-test TC5), ADR-0044 (RED-first TDD), ADR-0048 (lens d silent_skip log emission), ADR-0049 (d-test framework ≥3 baseline), ADR-0055 §1 (Cadence Rule 1 atomic), ADR-0057 (`Refs #N` cross-repo anchor), ADR-0059 (cluster-squash batch-lag detection), RETRO-009 §1+§3+§14 (chain-dep + label-hygiene + cluster-squash origin), RETRO-023 (Issue #1024 — cross-repo workstream codification) |
| **Sprint 29 cross-repo workstream pattern** | Issue tracked in `atilcan65/AtilCalculator` (#1034), impl lands here (`atilproject/dev-studio-template`). PR body anchors `Refs atilcan65/AtilCalculator#1034`. Consumer: S29-014 (orchestrator) verifies pre-push hooks usable post-merge. Sister: S29-008 (#1033, scripts port), S29-011 (#1036, ISSUE_TEMPLATE parity), all P1/P2 dev-lane. S29-007 (#1032) BLOCKED on S29-006 ADR port (ADR-0055 §Cadence Rule 1 atomic). |
## d1025 — agent-wake-hotfix Phase A template-port (Sprint 29 W2, sister mirror of AtilCalculator #1062)

| Field | Value |
|---|---|
| **Story** | [Issue #93](https://github.com/atilcan65/dev-studio-template/issues/93) *(closes on PR merge — fill post-merge)* |
| **Source-of-truth sister** | `atilcan65/AtilCalculator/scripts/tests/d1025-s29-agent-wake-hotfix.sh` (PR #1064, Closes #1062, agent:tester). Same RED-first discipline, same 7 TCs, same 3 fixes scope. Sister-cluster per ADR-0059 cluster-squash + Issue #93 §Sister-cluster ref. |
| **Test file** | `scripts/tests/d1025-s29-template-agent-wake-hotfix-port.sh` |
| **Scope** | Mirror of AtilCalculator Phase A #1062 — 3 fixes to `scripts/agent-wake.sh` (Fix 1 log honesty: send-keys `\|\| exit 0` → explicit rc check + error log `role=<R> pane=<P> rc=<N>` + exit 1; Fix 2 pane_id lookup: title-match → deterministic pane_index lookup with role→index map orch=0, pm=1, arch=2, dev=3, test=4, human=5 + `:0.N` format; Fix 3 capture-pane verify: post-send capture-pane + grep against wake text prefix within 1s timeout + exit 1 on mismatch). Pre-impl on current template main: 1 PASS (TC0 bash -n hygiene) / 12 FAIL (TC1 Fix 1 exit-code, TC2 Fix 1 context fields, TC3 Fix 2 orchestrator resolves to `:0.0`, TC4 Fix 2 6-role map incl. human=5, TC5 Fix 3 capture-pane invoked, TC6 Fix 3 mismatch → exit 1) — verified RED baseline 2026-07-14T13:25Z on this branch via `bash scripts/tests/d1025-s29-template-agent-wake-hotfix-port.sh`. Post-impl (Phase B sister-template impl PR per Issue #93): all 7 TCs GREEN per ADR-0044. |
| **TCs** | **7 TCs (1 PASS / 12 FAIL pre-impl verified; 7/7 GREEN post-impl, ADR-0049 ≥5 baseline met + 2 above)** (TC0 bash -n syntactic self-check [PASS pre/post — test file exists] + TC1 Fix 1 — agent-wake.sh exits 1 when tmux send-keys returns non-zero (mock tmux via PATH shim, MOCK_TMUX_SENDKEYS_FAIL=1) [RED pre-impl: exit=0 — current `\|\| exit 0` masks the rc; GREEN post-impl: exit=1] + TC2 Fix 1 — error log line contains `role=`, `pane=`, `rc=` context [RED pre-impl: stderr empty — no error log emitted; GREEN post-impl: explicit error log per Issue #1063 Fix 1] + TC3 Fix 2 — orchestrator resolves to `dev-studio:0.0` (pane_index 0, NOT title-match → NOT `:main.0`) [RED pre-impl: resolves to `dev-studio:main.0` per fallback index map at scripts/agent-wake.sh line 56 (template copy); GREEN post-impl: pane_index lookup returns `dev-studio:0.0`] + TC4 Fix 2 — deterministic 6-role map incl. human=5 [RED pre-impl: 6/6 roles wrong — current emits `:main.N` (format mismatch) + `human` role has no case statement so it exits 0 silently before send-keys; GREEN post-impl: 6/6 resolve to `:0.N` format] + TC5 Fix 3 — post-send `tmux capture-pane` invoked within 1s timeout [RED pre-impl: capture-pane NEVER called; GREEN post-impl: capture-pane -t pane_id -p in mock log + elapsed <1s] + TC6 Fix 3 — capture-pane grep mismatch → exit 1 (MOCK_TMUX_CAPTURE_MATCH=0 returns garbage output) [RED pre-impl: exit=0 — current code never calls capture-pane; GREEN post-impl: exit=1 from grep mismatch] + TC7 Cadence Rule 1 atomic — template scripts/tests/INDEX.md has d1025 row [RED pre-impl: no row; GREEN post-impl: row present per ADR-0055 §1 sibling TC7 = this attestation, sister-pattern d-retro-024 TC6]). |
| **Sister-pattern** | `atilcan65/AtilCalculator/scripts/tests/d1025-s29-agent-wake-hotfix.sh` (PR #1064, Closes #1062 — DIRECT sister, same RED-first discipline, same 7 TCs, same 3 fixes scope) + `d024-agent-wake.sh` (template-side source-coverage tests, sister-pattern for dual-channel doctrine ADR-0033) + `d1024-s29-ping-env-decoupling` (AtilCalculator Sprint 29 W1 cadence sister — same PR cadence, same author lane tester) + `d1020-s29-010-workflow-port-parity` + `d1021-s29-007-label-invariant-port-parity` (Sprint 29 W2 cadence sisters — same cycle slot allocation per Issue #113) + `d-retro-024 TC6` (Cadence Rule 1 INDEX.md attestation shape — TC7 mirrors); ≥3 sister-pattern coverage per ADR-0049 met (6 sisters). |
| **Run** | `bash scripts/tests/d1025-s29-template-agent-wake-hotfix-port.sh` |
| **Cadence Rule 1 atomic** | Single-commit cluster: `scripts/tests/d1025-s29-template-agent-wake-hotfix-port.sh` (NEW, mirrors AtilCalculator d1025) + this INDEX.md row (template-side). Same merge-day as AtilCalculator PR #1064 per ADR-0059 cluster-squash + Issue #93 §Sister-cluster ref. |

---

## d1026 — S29 ping-env-decoupling cross-repo port-parity 🟡 RED PRE-PORT

| Field | Value |
|---|---|
| **Story** | [STORY-S29 ping-env-decoupling #1058 (cluster coord)](https://github.com/atilcan65/AtilCalculator/issues/1058) + [Issue #1059 (Phase A — this d-test)](https://github.com/atilcan65/AtilCalculator/issues/1059) — Sprint 29 W1 gap-closing per owner directive 2026-07-13 pickup-141 |
| **Source-of-truth sister** | `atilcan65/AtilCalculator/scripts/tests/d1024-s29-ping-env-decoupling.sh` (PR #1056, commit 2f31cb3, merged 2026-07-14T09:02:05Z, runs 5/5 GREEN on calc) + `atilcan65/AtilCalculator/scripts/notify.sh` (PR #1057, commit 46e68e4, merged 2026-07-14T09:22:51Z — AC1 Option B fix shipped) |
| **Test file** | `scripts/tests/d1026-s29-template-env-decoupling-port-parity.sh` |
| **Production files** (Phase B, blocked on Phase A GREEN) | `scripts/notify.sh` (template side, line 65 `exit 1` on Telegram env unset — Issue #1053 unfixed on tmpl) + `scripts/peer-poke.sh.tmpl` (already exec-inherits from notify.sh, no change required — sister-pattern to calc's `peer-poke.sh` line 134 `exec ... notify.sh`). Phase B impl will port commit 46e68e4's AC1 Option B fix to template's `notify.sh` (~89 LOC delta: 114 → 203 LOC matching calc). |
| **TCs (5 + TC0 preflight)** | **TC0**: `bash -n` syntactic self-check. **TC1**: AC1 Option B — TELEGRAM_BOT_TOKEN unset → `notify.sh` exits 2 + WARN + tmux-wake fires (pre-port: FAIL — exit 1, no tmux-wake). **TC2**: AC1 Option B — TELEGRAM_BOT_TOKEN invalid → `notify.sh` exits 2 + ERROR + tmux-wake fires (pre-port: FAIL — exit 1, no tmux-wake). **TC3**: AC1 happy-path — valid env + reachable bot → `notify.sh` exits 0 + dual-channel (regression guard, INFO-skip when env unset). **TC4**: `peer-poke.sh.tmpl` with TELEGRAM_BOT_TOKEN unset → exits 2 + tmux-wake (inherits notify.sh behavior via exec — pre-port: FAIL via inheritance). **TC5**: `agent-wake.sh` OSC-2 title contamination → fallback index map graceful no-op (pre-port: PASS — TD-068b already on template via commit 6191b6c S28). |
| **Pre-port RED state** | 2 pass (TC0 + TC5) + 3 fail (TC1/TC2/TC4) + 1 INFO-skip (TC3). Mirrors d1024's pre-PR-#1057 RED state exactly. **Post-port (Phase B)**: 5/5 GREEN — proving tmpl caught up to calc per ADR-0059 cluster-squash. |
| **Sister-pattern** | `d1024-s29-ping-env-decoupling.sh` (AtilCalculator, direct sister — same 5-TC structure, same exit-code matrix, same fake-tmux-session fixture per d058); `d983-s28-003-forward-port-parity.sh` (template sister — same cross-repo port-parity regression-guard framing); `d058-no-live-peer-pane.sh` (fake-session isolation — owner-mercy-gate contract); `d081-auto-verdict-by-hook.sh` (template sister — tmpl-side d-test authoring conventions + INDEX.md row format + 4-cat label discipline); `d296-peer-poke-helper.sh` (TC4 inherits argv shape from `peer-poke.sh.tmpl`); `d320-stale-verdict-contract.sh` (exit-code semantics + stderr structure conventions). ≥3 sister-pattern coverage per ADR-0049 met (d1024 + d983 + d058 = 3 + d081 + d296 + d320 = 6 total). |
| **Run** | `bash scripts/tests/d1026-s29-template-env-decoupling-port-parity.sh` |
| **Cadence Rule 1 atomic** (ADR-0055 §1) | Single-commit cluster: `scripts/tests/d1026-s29-template-env-decoupling-port-parity.sh` (new, ~330 LOC, 5 TCs + TC0 preflight) + `scripts/tests/INDEX.md` (this entry). d-test + INDEX.md row in same commit per Cadence Rule 1. |
| **Cross-references** | Issue #1058 (cluster coordination), Issue #1059 (Phase A: this d-test), Issue #1060 (Phase B: tmpl impl, blocked on Phase A GREEN). ADR-0033 (dual-channel doctrine — the doctrine this cluster fixes on tmpl side), ADR-0044 (RED-first TDD doctrinal home), ADR-0049 (d-test framework ≥5 TCs baseline), ADR-0055 §1 (Cadence Rule 1 atomic), ADR-0057 (`Refs atilcan65/AtilCalculator#1058` cross-repo anchor), ADR-0059 (cluster-squash — d-test ships BEFORE impl, sister-PR must land same merge-day as calc-side for cluster-squash), TD-068b (Issue #935 — WAKE_KEYS_GAP_SEC env override, test fixture tolerance window), ADR-0031 (owner merge gate — only human squash-merges impl PR). Sister-PRs on calc side: PR #1056 (d1024 d-test, merged 2f31cb3), PR #1057 (d1024 impl, merged 46e68e4). |
| **Sprint 29 cross-repo workstream pattern** | Issue tracked in `atilcan65/AtilCalculator` (#1058 cluster coord), Phase A d-test lands here (`atilproject/dev-studio-template`), Phase B impl lands here too. PR body anchors `Refs atilcan65/AtilCalculator#1058` + `Refs atilcan65/AtilCalculator#1059`. Cluster-squash per ADR-0059: Phase A (d-test on tmpl) must land BEFORE Phase B (impl on tmpl); both must land same merge-day as calc-side d1024 PR cluster for cross-repo parity. Consumer: projects cloned from tmpl post-Phase-B will inherit env-decoupling fix automatically on first init. |
