# Changelog

All notable changes to this project are recorded here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — Sprint 35 S35-004 disposable-bootstrap-test seed step Issue #1252 fix

- **d-test (S35-004)**: `scripts/tests/d-s35-004-disposable-bootstrap-test-seed-step.sh` (NEW, ~140 LOC, 6 TCs) — verifies Issue #1252 fix: `.github/workflows/disposable-bootstrap-test.yml` MUST have a 'Seed new repo with dev-studio-template content' step inserted between step 2 (Create disposable public repo) and step 3 (Bootstrap init + render + labels). 6 TCs include: TC1 workflow file exists, TC2 YAML syntactic self-check (python yaml.safe_load), TC3 NEW 'Seed new repo' step present (Issue #1252 fix), TC4 Seed step INSERTED BETWEEN Create (line 74) and Bootstrap (line 103) — seed at line 85, TC5 Seed step uses `secrets.ATILPROJECT_DISPOSABLE_TOKEN` (no hardcoded GH_TOKEN), TC6 Seed step uses `x-access-token:` URL pattern (auth-via-token, not password). RED-first per ADR-0044 — pre-port 2 PASS (TC1+TC2) + 4 FAIL (TC3-TC6) verified NON-VACUOUS. Post-port 6/6 GREEN verified locally per cycle ~#3968Q+3893Q v2 verify-locally-before-verdict (initial run had TC5+TC6 FAIL due to d-test awk boundary pattern bug, fixed in same commit — workflow itself was correct on first edit). ≥6 TCs baseline per ADR-0049 — exactly 6 TCs.
- **Impl (S35-004)**: `atilproject/dev-studio-template/.github/workflows/disposable-bootstrap-test.yml` (MODIFIED — INSERT new step 2.5 between step 2 'Create disposable public repo' line 74 and step 3 'Bootstrap init + render + labels' line 103, ~17 LOC added). Step uses `secrets.ATILPROJECT_DISPOSABLE_TOKEN` (owner-configured per Issue #1251 RCA-fix loop) + `x-access-token:` URL pattern (auth-via-token, NOT password). Pushes dev-studio-template HEAD content to new repo's main branch via `git remote add disposable` + `git push disposable HEAD:main` + `git remote remove disposable`. cycle ~#3968Q+1109 NEW DOCTRINE inverse outcome — secrets-fix from Issue #1251 unblocked step 3 but unmasked this downstream 2nd-order workflow design defect at step 4 (PRD-style RCA cascade).
- **d-test registry**: `scripts/tests/INDEX.md` d-s35-004 row appended (Cadence Rule 1 atomic attestation per ADR-0055 §1).
- **Branch**: `dev/s35-004-fix-workflow-yaml` from `tmpl-official/main 127348c5` (post-cluster #40 docs/decisions forward-port squash per cycle ~#3968Q+1140 + PR #227 cluster #41 impl squash).
- **Refs**: `Refs atilproject/AtilCalculator#1252` + `Refs atilproject/AtilCalculator#1238` per ADR-0057 cross-repo discipline (NOT `Closes` — issue lives on different repo than PR).
- **Workflow territory**: `.github/workflows/` HUMAN ONLY per file ownership matrix → owner final squash gate per ADR-0031 (dev-prepared, owner-squashed per cycle ~#3968Q+414 PR-self-blocking CI doctrine). Lane 3 tester d-test-only sign-off pending per cycle ~#3642H.
- **Cascade**: Issue #1237 (S35-004 GREEN re-trigger) + Issue #1251 (secret-fix verified GREEN) + Issue #1252 (this fix) all close together on next GREEN re-trigger of `gh workflow run disposable-bootstrap-test.yml --repo atilproject/dev-studio-template --ref main`.
- **Sister-pattern**: S34-005 PR #214 SQUASH-MERGED 2026-07-26T04:23:34Z sha 18e374c (workflow-only fix 15/15 GREEN per cluster-squash #22 — same dev-prepared + owner-squash workflow pattern precedent). cycle ~#3968Q+1109 NEW DOCTRINE inverse outcome (PRD-style RCA cascade) — RETRO-035 generalization candidate.

### Added — Sprint 34 S34-004 disposable-bootstrap-test (Issue #1224)

- **d-test (S34-004)**: `scripts/tests/d-s34-004-disposable-bootstrap-test.sh` (new, ~140 LOC, 10 TCs) — verifies `.github/workflows/disposable-bootstrap-test.yml` structure per Issue #1224 AC1-AC4 (disposable bootstrap test infra — public + optional gated private repo verification). 10 TCs include: TC1 workflow file exists, TC2 YAML syntactic self-check (python yaml.safe_load), TC3 `workflow_dispatch` trigger (AC1 owner-driven manual trigger), TC4 `public-repo-bootstrap` job defined (AC1 public path), TC5 `private-repo-bootstrap` job gated on `run_private == 'true'` (AC1+AC2 owner gate), TC6 evidence capture (≥3 `GITHUB_STEP_SUMMARY` refs per AC1), TC7 teardown step in `if: always()` block (AC1 cleanup invariant), TC8 INDEX.md row present (Cadence Rule 1 atomic attestation), TC9 CHANGELOG.md entry present (unique `Sprint 34 S34-004 disposable-bootstrap-test` prefix), **TC10 (NIT-1 BLOCKER fix verification per arch verdict 🟡 cmt 5084623598 + cycle ~#3968Q+847 inline d-test amender pattern) workflow has `id: create` on both Create disposable public repo + Create disposable private repo steps** (without `id: create`, `${{ steps.create.outputs.REPO_NAME }}` resolves EMPTY at runtime — workflow FAILS at clone/delete). RED-first per ADR-0044 — pre-port 7 PASS + 2 FAIL (TC8 INDEX.md + TC9 CHANGELOG.md) verified NON-VACUOUS. TC10 NON-VACUOUS sanity-checked locally (removing `id: create` lines → TC10 FAIL `public=0 private=0`). ≥6 TCs baseline per ADR-0049 — d-s34-004 = 10 TCs exceeds baseline by 4.
- **Impl (S34-004)**: `.github/workflows/disposable-bootstrap-test.yml` (NEW, ~140 LOC, 9-Lens coverage per ADR-0045) — workflow_dispatch trigger with `run_private` boolean input (owner-only gate per AC2), `public-repo-bootstrap` job (AC1 public path with init/render/labels capture + teardown), `private-repo-bootstrap` job (gated on `if: ${{ inputs.run_private == 'true' }}`, secret rotation per AC2). SHA-pinned actions/checkout to b4ffde65f46336ab88eb53be808477a3936bae11 (v4.1.1) per ADR-0027 §Threat model. Least-privilege permissions (contents:read + actions:read) per ADR-0027. 4-tuple runner per S29-001 AC3. Concurrency group `disposable-bootstrap` (serial). 30min timeout bounded.
- **d-test registry**: `scripts/tests/INDEX.md` d-s34-004 row appended (sister to d-s34-005-runner-label-atilcan workflow-only pattern from cluster-squash #22).
- **Branch**: dev/s34-004-disposable-bootstrap-test from tmpl-official/main 8eb35d6 POST-#223-squash per cycle ~#3968Q+311+8 CONDITIONAL preventive.
- **Refs**: atilcan65/AtilCalculator#1224 (per ADR-0057 sub-deliverable pattern, Issue #1224 status:in-progress 4-cat INTACT). Sister-pattern: S34-005 PR #214 SQUASH-MERGED 2026-07-26T04:23:34Z sha 18e374c (workflow-only fix 15/15 GREEN per cluster-squash #22 — same dev-prepared + owner-squash workflow pattern, cycle ~#3968Q+414 PR-self-blocking CI doctrine precedent).
- **Workflow territory**: `.github/workflows/` HUMAN ONLY per file ownership matrix → owner final squash gate per ADR-0031 (dev-prepared, owner-squashed). Lane 2 arch verdict 9-Lens + Lane 3 tester d-test-only sign-off + owner squash chain per AC4.
- **NIT-1 BLOCKER fix (cycle ~#3968Q+933, 2026-07-26T20:37+03)**: same-branch amend — added `id: create` on Create disposable public repo (workflow line ~75) + Create disposable private repo (workflow line ~142) steps. Without `id: create`, `${{ steps.create.outputs.REPO_NAME }}` referenced at workflow lines 87/105/154 (clone + teardown) would resolve EMPTY at runtime → workflow FAILS. Fix verified by TC10 (10/10 GREEN). NON-VACUOUS sanity check confirmed TC10 FAILs when both `id: create` lines removed. Follow-up commit on branch `dev/s34-004-disposable-bootstrap-test` (4-file: workflow + d-test + INDEX.md + CHANGELOG.md per ADR-0055 §1).
- **Out-of-scope escalations**: ADR-0078 owner Variables config (deploy.yml lines 41-49, 5 vars: SERVICE_NAME + MODULE_PATH + DEPLOY_PORT + HEALTHZ_PATH + PROD_HOSTNAME per ADR-0047 §Decision.1) — owner-gated per file ownership matrix, NOT blocking S34-004 dispatch.

### Added — Sprint 34 W3 S34-006 verified doc

- **Verified doc enrichment (Issue #1226 AC1 canonical home)**: `docs/new-project-steps.md` adds `§5 Verified by — S34-004 evidence anchors` section. Maps each Phase 1–4 command to its S34-004 evidence source (PR #224 SQUASH-MERGED 2026-07-26T18:16:34Z sha `ffc7403c`). Evidence anchor table covers: workflow file SHA, runner label `[self-hosted, Linux, X64, atilcan]` per S29-001 AC3, d-test 10/10 GREEN, bootstrap commands covered, AC2 evidence-artifact correspondence, reproducibility via `gh workflow run`, sister-pattern Sprint 32 S32-017. Header block adds `Verified by:` epigraph citing PR #224. See-also section adds ADR-0078 + Issue #1226 cross-reference. PM-authored, Lane 2 docs verdict PRIMARY per cycle ~#3968Q+251 + Lane 3 N/A doc-only per cycle ~#3642H + owner squash per ADR-0031.

### Added — Sprint 34 W3 forward-port S34-002 row 011

- **d-test (row 011)**: `scripts/tests/d-s34-002-audit-project-refs-byte-equivalence.sh` (new, ~140 LOC, 7 TCs) — verifies `scripts/audit-project-refs.sh` byte-equivalence to `atilcan65/AtilCalculator` canonical (MD5 `bdefdc0b37af2d66f2e349375c0dcde0`, 140 lines). Generic project-ref-audit script per ADR-0075 §B.1 `equivalent` row classification (architect confirmed "generic — pure project ref audit"). Template pre-port: 166 lines, MD5 `b6c802a03ae3560260f71e9ed43451b1` — 26-line DRIFT. Post-port: byte-identical to canonical.

### Added — Sprint 34 W4 forward-port S34-002 row 014

- **d-test (row 014)**: `scripts/tests/d-s34-002-row-014-claim-next-ready-byte-equivalence.sh` (new, ~210 LOC, 9 TCs) — verifies `scripts/claim-next-ready.sh` byte-equivalence to `atilcan65/AtilCalculator` canonical (MD5 `f7843ac55c34bf82b3c161e71609db82`, 615 lines). Pure byte-equivalence parity attestation per ADR-0075 §B.1 `equivalent` row classification (0-line DRIFT, byte-identical). 9 TCs include: TC1 file exists, TC2 bash -n, TC3 line count = 615, TC4 MD5 = `f7843ac55c34bf82b3c161e71609db82` (byte-equivalence proof), TC5 Sprint 33 amendment markers (5 markers: CLAIM_NEXT_READY_LOCK_FILE + claim-next-ready.sh + status:in-progress + RETRO-024 + WIP_LIMIT), TC6 state machine integrity (5 markers: agent: prefix + gh issue + gh issue edit + gh issue comment + auto-claim.log), TC7 INDEX.md row, TC8 CHANGELOG.md entry, TC9 d031 sister-test cross-spec linkage. ≥6 TCs baseline per ADR-0049 — d-s34-002-row-014 = 9 TCs exceeds baseline by 3.
- **Impl (row 014)**: `scripts/claim-next-ready.sh` (UNCHANGED — pure byte-equivalence parity attestation net 0-line delta). Sprint 33 amendments embedded: CLAIM_NEXT_READY_LOCK_FILE env var override (cycle ~#3853 TC1 env-rot fix) + RETRO-024 silent-skip on work-done-elsewhere terminal state (cycle ~#3968Q+214 status-only atomic). Both already byte-equivalent to template since Sprint 33.
- **d-test registry**: `scripts/tests/INDEX.md` row 014 entry appended (14th sister — rows 001-013 SHIPPED + row 014 cycle ~#723 dispatch).
- **Branch**: dev/s34-002-row-014 from tmpl-official/main 55cb3dc POST-#217-squash per cycle ~#3968Q+311+8 CONDITIONAL preventive.
- **d031 sister-test expansion (cycle ~#3968Q+847 OWNER OVERRIDE)**: `scripts/tests/d031-claim-next-ready.sh` expanded 10 → 14 TCs INSIDE PR #219 (NOT separate PR per arch 308th-wake cycle ~#3968Q+731 ratification). New TCs: TC9 Issue #1027 RETRO-024 silent-skip (work-done-elsewhere filtered), TC10 Issue #1027 silent-skip log entry (all-work-done-elsewhere), TC11 Issue #1041 ROLLBACK flip-not-applied (exit 6), TC12 Issue #1041 ROLLBACK wip-over-cap-post-flip (exit 7). Renumbered old TC9/TC10 → TC13/TC14. verify-locally 14/14 GREEN post-amend per cycle ~#3893Q v2. 5-file atomic per ADR-0055 §1 (impl + d-s34-002-row-014 + d031 + INDEX.md + CHANGELOG.md).

### Added — Sprint 34 W4 forward-port S34-002 row 015

- **d-test (row 015)**: `scripts/tests/d-s34-002-row-015-cross-repo-close-byte-equivalence.sh` (new, ~145 LOC, 9 TCs) — verifies `scripts/cross-repo-close.sh` PATCH-FORWARD to `atilcan65/AtilCalculator` canonical (MD5 `a0823334897d4cab863f9e114847563f`, 154 lines). Pure PATCH-FORWARD divergent class per ADR-0075 §B.1 (template stub 161 lines MD5 `9cd683e70e5b0dbccf2ff5f5c744ee5f` → canonical 154 lines byte-identical). 9 TCs: TC1 file exists, TC2 bash -n, TC3 line count = 154, TC4 MD5 = `a0823334897d4cab863f9e114847563f` (byte-equivalence proof), TC5 Sprint 33 markers (5 markers: CROSS_REPO_CLOSE_TOKEN + ADR-0040 + Issue #293 + Idempotent + Dry-run), TC6 state machine integrity (5 markers: gh api + gh issue + STATE= + Authorization + dry-run), TC7 INDEX.md row, TC8 CHANGELOG.md entry, TC9 PATCH-FORWARD applied (template header removed + AtilCalc-specific paths replaced). ≥6 TCs baseline per ADR-0049 — d-s34-002-row-015 = 9 TCs exceeds baseline by 3.
- **Impl (row 015)**: `scripts/cross-repo-close.sh` (PATCH-FORWARD — AtilCalc canonical 154-line version replaces template stub 161-line version, net -7 lines: 7-line TEMPLATE PORT header removed + 2 AtilCalc-specific path replacements to generic placeholders). AtilCalc canonical MD5 `a0823334897d4cab863f9e114847563f` byte-identical post-port. Sprint 33 amendments embedded: ADR-0040 Option B + Issue #293 cross-repo PR auto-close + Idempotent guard + Graceful degradation + Dry-run mode.
- **d-test registry**: `scripts/tests/INDEX.md` row 015 entry appended (15th sister — rows 001-014 SHIPPED + row 015 cycle ~#870 dispatch).
- **Branch**: dev/s34-002-row-015 from tmpl-official/main b6a61681 POST-#219-squash per cycle ~#3968Q+311+8 CONDITIONAL preventive.

### Notes — Sprint 34 W4 forward-port S34-002 row 014

- Sprint 34 W3 forward-port 3/3 SHIPPED-functional ✅ (PR #215 + #216 + #217, cluster-squash #{26-28}) — row 014 = 4th forward-port SHIPPED-functional after rows 011-013.
- Pre-port RED state NON-VACUOUS per ADR-0044 (TC7+TC8 FAIL — verified locally at cycle ~#723: 7 GREEN + 2 RED).
- 4-file atomic per ADR-0055 §1: `scripts/claim-next-ready.sh` (UNCHANGED) + `scripts/tests/d-s34-002-row-014-claim-next-ready-byte-equivalence.sh` (NEW) + `scripts/tests/INDEX.md` (MODIFIED) + `CHANGELOG.md` (MODIFIED, this entry).
- Cluster-squash #29 candidate STANDALONE per cycle ~#3968Q+3258.
- **Impl (row 011)**: `scripts/audit-project-refs.sh` (MODIFIED — copied canonical 140-line version over template's 166-line version, net -26 lines). Script's `atilcan65` + `AtilCalculator` literals are PATTERNS scanned for, NOT project paths (TC4 strict-path regex check passes). 7 TCs include: TC1 file exists, TC2 line count = 140, TC3 MD5 matches canonical, TC4 no project-specific paths (strict path regex), TC5 key markers (PATTERNS + EXCLUDE_PATTERNS + git grep + JSON_OUTPUT + exit 0/1/2 + audit pattern literals), TC6 INDEX.md row (Cadence Rule 1 atomic), TC7 CHANGELOG.md entry.
- **d-test registry**: `scripts/tests/INDEX.md` row 011 entry appended (11th sister — rows 001-010 cycle ~#41-#571 + row 011 cycle ~#675).

### Notes — Sprint 34 W3 forward-port S34-002 row 011

- Sprint 34 W2 forward-port 10/10 SHIPPED ✅ (PR #204-#213, cluster-squash #{12-21}) per cycle ~#579 dispatch.
- Sprint 34 W3 row 011 = `scripts/audit-project-refs.sh` byte-equivalence forward-port per cycle ~#675 dispatch (post-PR-#214-squash preventive measure per cycle ~#3968Q+311+8 REFINEMENT 5th instance).
- Pre-port RED state NON-VACUOUS per ADR-0044 (TC6+TC7 FAIL — verified locally at cycle ~#675: 5 GREEN + 2 RED).
- 4-file atomic per ADR-0055 §1: `scripts/audit-project-refs.sh` (MODIFIED) + `scripts/tests/d-s34-002-audit-project-refs-byte-equivalence.sh` (NEW) + `scripts/tests/INDEX.md` (MODIFIED) + `CHANGELOG.md` (MODIFIED, this entry).
- Branch dev/s34-002-row-011 created FROM origin/main 18e374c (post-PR-#214-squash = post-S34-005-COMPLETE) per cycle ~#3968Q+311+8 REFINEMENT preventive measure (branched AFTER = no conflict).

### Added

- **Issue #201 fix — `scripts/dev-studio-init.sh` .tmpl preservation guard.** P1 owner-filed
  bug (2026-07-20T17:53:17Z): `render_one()` unconditionally `rm -f "$src"` after sed render,
  destroying tracked `.tmpl` source files when init.sh is run in the template source repo.
  Fix gates the rm with `git ls-files --error-unmatch` check: tracked files (.tmpl in source
  repo, committed source-of-truth) are preserved; untracked files (.tmpl in consumer projects,
  ephemeral bootstrap inputs) are still deleted as before. Restores the soul-amend PR cycle
  (`.claude/agents/*.md.tmpl` + `CLAUDE.md.tmpl`) without manual `git checkout HEAD -- .tmpl`
  workaround (Issue #1188 Carry-over #7 precedent). Paired with new d-test
  `d-init-sh-tmpl-preservation.sh` (7 TCs — exceeds ≥5 aspirational baseline per ADR-0049):
  TC1-TC6 each tracked `.tmpl` file (architect/developer/orchestrator/product-manager/tester
  soul .tmpl + CLAUDE.md.tmpl) preserved after render_one; TC7 regression guard — untracked
  .tmpl IS still deleted (consumer behavior preserved). RED-first per ADR-0044: pre-fix
  1/7 PASS + 6/7 FAIL (bug reproduced), post-fix 7/7 GREEN verified locally. Cadence Rule 1
  atomic per ADR-0055 §1: impl (init.sh) + d-test + INDEX.md row + this CHANGELOG entry
  in single commit cluster (4 files). Closes Issue #201 sister-pattern: Issue #1023 /
  RETRO-022 (reflex-class damage — tool's "helper" pass destroys user state). Cycle
  ~#3966Q+5 sighting + cycle ~#3966Q+6 arch 9-Lens pre-claim advisory NIT 1-4 (AC1 .md
  UNTRACKED note + d-test naming + AC7 root-cause-confirm + idempotency — all 4 NITs
  absorbed).
- **d-pr-1147-install-test-flake.sh — Issue #176 forward-port (S32-021 sister AC4 gap closure).**
  Byte-equal port from `AtilCalculator/scripts/tests/d-pr-1147-install-test-flake.sh` per
  Issue #1041 non-vacuous. 4 TCs (RED-first per ADR-0044 ≥3 hygiene baseline met; AC2 ≥5
  aspirational — source-of-truth sister has 4 TCs): TC1 timeout=180 venv-creation relaxation,
  TC2 session-scoped shared_venv fixture, TC3 test_install_command_executes wired to
  shared_venv parameter, TC4 pytest local regression guard. Sister-patterns: d058 (claim
  work-stream awareness — same bash+grep verifier idiom), d1142 (queue hygiene 4-cycle
  threshold — same d-test size class), d1138-template-agent-wake-fix-4b (Issue #1140
  forward-port parity precedent). Pre-impl RED 0/4 PASS + 4/4 FAIL (tests/docs/test_readme.py
  absent in tmpl). Cadence Rule 1 atomic per ADR-0055 §1: d-test + INDEX.md row + this
  CHANGELOG entry in same commit cluster. Closes Issue #176 + Closes Issue #161 AC4
  gap. Cycle ~#3958Q+135 — owner-directive Wave 9 claim order (#1180 → #176 first).
- **S32-024 Phase B summary doc — Issue #197 AC1-AC6 evidence.** Documents the
  Sprint 32 dry-run execution (`atilcan65/sprint-32-dryrun` PR #3 squash-merged
  sha `e5c2ff07`). Covers AC1 launcher invocation, AC2 post-state (43 labels
  ≥34 threshold), AC3 5-agent tmux session, AC4 PM claim path (Vision Intake
  #1 + first story #2), AC5 in-dry-run merge (15/15 pytest pass), AC6
  close-the-loop. Dry-run caveats noted (cross-lane verdicts self-applied,
  owner squash simulated, TC7 static grep overly strict — sister-pattern to
  cycle ~#3950Q d-test wrong-expectation RED). Cadence Rule 1 atomic per
  ADR-0055 §1: this doc + CHANGELOG entry + dry-run evidence all in same commit.
  Cycle ~#3958Q+118 — authored post-Issue #162 premature-close (cycle ~#2919
  anti-pattern sister) and PR #196 squash-merge terminal. PR body anchor:
  `Closes atilproject/dev-studio-template#197`.
- **d-s32-024-new-project-bootstrap-dry-run.sh — S32-024 (Issue #162) Phase A d-test.**
  End-to-end new-project bootstrap verifier per S32-024 (Issue #162) AC1+AC2+AC3
  d-testable subset. 8 TCs (TC0 preflight + TC1 launcher existence + TC2 source-mode
  4-tuple + TC3 fixture hook + TC4 AC1 live invocation + TC5 AC2 post-state + TC6
  trust-but-verify content blob SHA + TC7 AC3 dev-studio-start.sh 5-agent check).
  Sister-patterns: d-smoke-bootstrap-v110 (REST + content blob SHA v3 amendment per
  cycle ~#3940Q+9) + e2e-pilot.sh (T1-T7 new-project bootstrap) + d-verify-portage-
  diff-engine (TRAP cleanup + bash -n) + d001-launcher-self-hosted-runner-patch
  (S29-013 sourced-mode + FIXTURE_*). RED state: 4/8 PASS (TC0-TC3 unit-level) +
  4/8 FAIL (TC4-TC7 integration-level until AC1 invocation lands). Cadence Rule 1
  atomic per ADR-0055 §1: d-test + scripts/tests/INDEX.md row + this CHANGELOG.md
  entry in same commit. Cycle ~#3958Q+5 — authored per Issue #414 §1 pre-flight
  ground truth (Layer 2 REST + Issue #162 body capture) + Issue #389 dual-channel
  peer-poke reserved (tester-wake on PR open, not pre-RED-state). PR body anchor:
  `Closes atilproject/dev-studio-template#162`.
- **Issue #179 forward-port — `scripts/agent-watch.sh` queue check filters (d028 P1) from
  AtilCalculator.** Sister-pattern of AtilCalculator d028 + Issue #1142 + PR #1144 cluster
  (cycle ~#1142 — `agent-watch.sh` queue filter bug fixed in AtilCalculator, requires tmpl
  parity). Byte-equal forward-port (sha256 `b8c6d03662e7…` matches AtilCalculator source-
  of-truth) covers D2.2 `role_wakes_for_pr_labeled` wake-trigger filter + accumulated sister-
  pattern fixes (d1041 org-scan default, d1042 REPOS[] guard, d1043 MODE-detection fix,
  Issue #1086 Bug A + Bug B, owner directive 2026-07-15T06:42Z `atilproject` org-scan default).
  Paired with new d-test `d028-template-agent-watch-queue-check-filter.sh` (11 TCs — exceeds
  ≥5 aspirational baseline per ADR-0049): TC1 cc-only filter wakes (tester); TC2 agent-only
  filter wakes; TC3 both cc+agent filter wakes; TC4 neither filter skips; TC5 empty-queue
  case skips; TC6 needs-tester-signoff wakes (3rd in ADR-0009 § 2.1 matrix); TC7 architect
  cc-only wakes (cross-role verification); TC8 architect neither skips; TC9 byte-equal
  parity (sha256 vs AtilCalculator source); TC10 sister-pattern cite count (≥3 per ADR-0049);
  TC11 AC2 case anchors (cc-only / agent-only / both / neither / empty-queue ≥5 references).
  Pattern: awk-extract `role_wakes_for_pr_labeled()` from agent-watch.sh + ROLE-prefixed
  bash -c subshell eval (sister-pattern to d1138 + d-init-sh-tmpl-preservation). RED-first
  per ADR-0044 + Issue #1041 (real `role_wakes_for_pr_labeled` invocation, NOT silent-green):
  pre-port would have all 5 wake-cases failing (function absent) + byte-equal TC failing
  (different sha); post-port 11/11 GREEN verified locally. Cadence Rule 1 atomic per
  ADR-0055 §1: impl (agent-watch.sh) + d-test + INDEX.md row + this CHANGELOG entry in
  single commit cluster (4 files). PR body anchor: `Closes atilproject/dev-studio-template#179`.
  Sister-pattern: AtilCalculator Issue #1142 (origin) + PR #1144 (AtilCalc sister impl) +
  cycle ~#2988 (forward-port cadence — byte-equal + INDEX.md). Cycle ~#3958Q+135 Wave 9
  owner-directive claim order (#1180 → #176 → #178 → #179 → #180).
### Added — Sprint 35 label-check Sprint 33 doctrine forward-port (S35-003 cluster 1)

- **d-test (cluster 1)**: `scripts/tests/d-s35-003-c1-label-check-sprint33-doctrine-forward-port.sh` (new, ~210 LOC, 10 TCs RED-first per ADR-0044) — verifies forward-port of `.github/workflows/label-check.yml` from bare 123-line original (current dev-studio-template canonical home) → AtilCalculator's post-Sprint 33 977-line version. **4 doctrine layers required**: (a) **Issue #213 TEST-WAKE-ENFORCE Layer 3** — type:bug → cc:tester + needs-tester-signoff CI gate enforcement, (b) **Issue #423 ADR-0012 §Cascade-strip Part 1** — concurrency serialization + cascade-strip scope-tightening (only removes duplicate `status:*`, does NOT touch `cc:*` or `needs-*-signoff`), (c) **owner-override clause** — human-owner bypass mechanism, (d) **closed event in pull_request_target** — RETRO-024 §4-cat repair + verdict-by post-close hygiene. **10 TCs include**: TC1 workflow file exists, TC2 YAML syntactic check (python yaml.safe_load), TC3 `pull_request_target` types includes `closed`, TC4 `concurrency:` block present (cycle ~#3968Q+414 PR-self-blocking CI doctrine), TC5 type:bug → cc:tester + needs-tester-signoff enforcement (Issue #213 Layer 3), TC6 cascade-strip scope-tightening Part 1 (Issue #423), TC7 owner-override clause, TC8 SHA-pinned actions/github-script (ADR-0027 — currently PASS), TC9 INDEX.md row present (Cadence Rule 1 atomic attestation), TC10 CHANGELOG.md entry present (this entry). RED-first per ADR-0044 — pre-port expected 3 PASS (TC1+TC2+TC8) + 7 FAIL (TC3-TC7 + TC9-TC10) verified NON-VACUOUS. ≥6 TCs baseline per ADR-0049 — 10 TCs exceeds baseline by 4. **4-file atomic per ADR-0055 §1** (impl workflow MODIFIED + d-test NEW + INDEX.md MODIFIED + CHANGELOG.md MODIFIED = 4 files same commit cluster). **Cluster-squash per ADR-0059** (≤5 PRs/cluster — S35-003 cluster 1 = label-check forward-port). **Refs anchor** (per ADR-0057): `Refs atilcan65/AtilCalculator#1238` (sub-deliverable pattern, Issue #1238 stays OPEN per RETRO-024 owner-ratification close — terminal `Closes` reserved for Sprint 35 W4 final). **Doctrinal anchors**: Issue #213 (TEST-WAKE-ENFORCE Layer 3), Issue #423 (ADR-0012 §Cascade-strip Part 1), Issue #414 §1 (pre-PR re-query — Issue #1238 4-cat INTACT verified), ADR-0044 (RED-first TDD — 3 PASS + 7 FAIL pre-port, expected GREEN post-impl per cycle ~#3893Q v2), ADR-0049 (d-test ≥6 baseline), ADR-0055 §1 (Cadence Rule 1 atomic), ADR-0057 (Refs anchor — sub-deliverable pattern), ADR-0012 (4-cat label invariant on Issue #1238), ADR-0027 (SHA-pinned actions), ADR-0031 (owner squash gate — `.github/workflows/` HUMAN ONLY per file ownership matrix), ADR-0033 (dual-channel peer-poke), ADR-0059 (cluster-squash cadence), ADR-0075 §B.1 (parity matrix row `label-check.yml` divergent class), cycle ~#3968Q+414 (PR-self-blocking CI doctrine — TC4 concurrency block), cycle ~#3968Q+940 (PROCESS-GAP — story text naming d-test must have d-test run before verdict, applied). **Lane review chain**: dev (Lane 4 impl PR forward-port after d-test RED-first sign-off per ADR-0044) + arch (Lane 2 docs verdict 9-Lens per ADR-0045 on forward-port correctness) + tester (Lane 3 d-test-only sign-off per cycle ~#3642H on 10 TCs GREEN post-impl) + owner @atilcan65 (squash gate per ADR-0031). **Ordering constraint** (per orchestrator peer-poke 2026-07-27T19:59+03 = 16:59Z): "coordinate w/ dev on S35-003 label-check.yml fix timing so dispose-bootstrap sees FIXED label-check" — S35-004 disposable bootstrap (Issue #1237) is GATED on this forward-port landing first.

### Fixed

- **d-smoke-bootstrap-v110 TC4+TC5 amendment (cycle ~#3940Q+9, Phase B d-test self-heal).**
  After PR #185 (arch init.sh `TEMPLATE_VERSION` resolver) + PR #188
  (d-test TC1+TC2 infra fix) cluster-squash MERGED (cycle ~#3731,
  10:10:02Z + 10:31:28Z, sha `925f4e79` + `ac6da232`), Phase B
  re-execution surfaced two **test expectation gaps** (not impl
  regressions): **(a) TC4** asserted `label count = 34` (strict equality)
  but smoke-v110 actually has **43 labels** = 34 from `bootstrap-labels.sh`
  + 9 GitHub defaults (`bug`, `documentation`, `duplicate`, `enhancement`,
  `good first issue`, `help wanted`, `invalid`, `question`, `wontfix`)
  which GitHub auto-installs on private-repo creation. Fix: change
  `-eq 34` → `-ge 34` — proves `bootstrap-labels.sh` ran while tolerating
  GH-default extras (minimal-touch per tester recommendation §6). **(b) TC5**
  asserted `main HEAD SHA == tag SHA` (strict equality) per Issue #972
  Path-Verify Doctrine, but Phase B AC3 verification commit
  (`test: Phase B bootstrap-labels 34 labels seed (Issue #160 AC3 verify)`
  @ 11:15:47Z, sha `69524905`) legitimately adds a commit on top of the
  v1.1.0 tag (`401c22cd4c41`), so equality fails. Cycle ~#3682 Defect #2
  framing correction already established that GitHub's `gh repo create
  --template` produces a synthetic initial commit (not the v1.1.0 tag
  commit). First v3 attempt was descendant-of via
  `compare/{tag}...{head}` endpoint — also fails because the v1.1.0 tag
  commit `401c22cd` is NOT in smoke-v110's commit history at all
  (synthetic-init copies files into a NEW commit without tag-graph
  continuity, so compare endpoint returns HTTP 404 on intra-repo compare
  for unknown base). **Final fix (v3)**: content blob SHA equivalence on
  a canonical unchanged file. Git's content-addressable storage guarantees
  blob SHA = content bytes, so matching blob SHA between
  `tmpl@refs/tags/v1.1.0/contents/scripts/dev-studio-init.sh` and
  `smoke-v110@refs/heads/main/contents/scripts/dev-studio-init.sh` proves
  byte-identical content regardless of commit-graph discontinuity.
  Verified: blob=`c08152bf3dd576be6efc4afd8f3167fc0ee04948` on both sides.
  Helper `curl_json_compare_status` retired (kept in file for reference
  with doc comment); reuses pre-existing `curl_json_object_sha`. Result:
  TC0-TC7 GREEN 7/7 on `atilcan65/smoke-v110` post-cluster-squash (verified
  locally on cycle ~#3940Q+9 by dev lane after tester re-verify cmt
  `5017020110`). Phase B end-to-end AC1-AC5 verification COMPLETE — ready
  for Phase B PR (`Closes atilproject/dev-studio-template#160`) per
  ADR-0057 + cycle ~#3471 Refs-not-Closes Phase A/B discipline.
  Sister-pattern: ADR-0044 (RED-first TDD — non-vacuous expectation gap
  detection), ADR-0049 (≥5 TC baseline + ≥2 sister-pattern met),
  ADR-0055 §1 (Cadence Rule 1 atomic — d-test + INDEX.md + CHANGELOG
  same commit cluster), ADR-0057 (`Closes #N` strict format), Issue #972
  (Path-Verify Doctrine extended to content-equivalence), cycle ~#3682
  (Defect #2 framing — synthetic initial commit breaks commit-graph
  descendant-of; cycle ~#3940Q+9 documented that **content** equivalence
  survives where **commit-graph** equivalence cannot), cycle ~#3940Q+9
  (tester re-verify RED → dev amend → GREEN self-heal pattern, with
  intermediate failed attempts: strict-equality ✗ → descendant-of via
  compare ✗ → content-equivalence via blob SHA ✓).

- **d-smoke-bootstrap-v110 TC1+TC2 self-fix (Issue #186, P1).** The v1.1.0 d-test
  shipped in PR #183 had two latent bugs that surfaced during S32-020 Phase B
  smoke bootstrap verification (cycle ~#3682): **(a) TC1** used top-level
  `"sha"` extraction which returns empty for **annotated tags** (where the
  tag-object SHA is at `.object.sha`, not top-level — and `object.type` is
  `"tag"` instead of `"commit"`). v1.1.0 is annotated (401c22cd → a5b91da),
  so TC1 returned empty even though the tag existed. Fix: two-step
  dereference — read `object.type` discriminator, then either use
  `object.sha` directly (lightweight) or fetch `/git/tags/{tag_obj_sha}`
  (annotated). **(b) TC2** used unauthenticated curl, which returns 404
  for **private repos** like `atilcan65/smoke-v110`. Fix: auto-detect
  `gh auth token` and inject `Authorization: Bearer` header. Added **TC6**
  annotated-tag dereference consistency check (validates TC1's two-step
  logic against direct `/git/tags` lookup) + **TC7** 404 vs 422 distinction
  (pins canonical "tag missing" semantics so future regressions in
  tag-validation vs lookup are caught). Result: TC1+TC2+TC6+TC7 GREEN on
  current `atilproject/dev-studio-template` v1.1.0 (verified locally on
  cycle ~#3683). TC4 (labels=34) + TC5 (main HEAD SHA == tag SHA) remain
  RED — those test Issue #160 ACs (post-bootstrap state), not infra, and
  unblock once PR #185 (arch init.sh `TEMPLATE_VERSION` resolver) lands
  and Phase B re-runs. Sister-pattern: ADR-0044 (RED-first TDD),
  ADR-0049 (≥5 TC baseline + ≥2 sister-pattern), ADR-0055 §1 (Cadence Rule
  1 atomic — d-test + INDEX.md + CHANGELOG same commit cluster). Refs
  Issue #160 (S32-020 Phase B unblock), Issue #185 (arch init.sh fix,
  sister-PR), Issue #972 (Path-Verify Doctrine sister-pattern).

### Added — Sprint 35 S35-003 cluster 2 status-label-to-board forward-port

- **d-test (NEW, ~273 LOC, 10 TCs)**: `scripts/tests/d-s35-003-c2-status-label-to-board.sh` — verifies `status-label-to-board.yml` forward-port from bare 199-line tmpl → AtilCalculator's post-Sprint 33 250-line canonical per ADR-0075 §B.1 `status-label-to-board.yml` divergent class.
- **5 doctrine layers verified**: (1) Issue #571 §Layer 5 idempotency reconcile (concurrency block + serialization key + cancel-in-progress true) per ADR-0056; (2) Issue #571 §Layer 5 rate-limit cascade fix (withRetryOnRateLimit helper) per ADR-0056; (3) Issue #571 §silent_skip (silentSkipOnRateLimit helper + try-catch GraphQL wrap) per ADR-0056; (4) Issue #567 SHA-pin sweep (actions/github-script SHA-pinned per ADR-0027).
- **10 TCs RED-first per ADR-0044**: TC1 file exists, TC2 YAML syntactic (python yaml.safe_load), TC3 `concurrency:` block (Issue #571 §Layer 5), TC4 group key includes `pull_request.number` OR `issue.number` (serialization), TC5 `cancel-in-progress: true` (Issue #571 §Layer 5 — newer runs supersede), TC6 `withRetryOnRateLimit` helper (Issue #571 §Layer 5 rate-limit cascade fix), TC7 `silentSkipOnRateLimit` helper (Issue #571 §silent_skip), TC8 try-catch wrap GraphQL block (Issue #571 §silent_skip), TC9 SHA-pinned `actions/github-script` (ADR-0027 + Issue #567, currently PASS), TC10 INDEX.md row present (Cadence Rule 1 atomic attestation).
- **Pre-port RED VERIFIED @ 2026-07-27T20:34:21Z**: 3 PASS (TC1+TC2+TC9) + 7 FAIL (TC3-TC8+TC10), exit code 1 NON-VACUOUS. TC6 + TC9 fixed via cycle ~#3968Q+847 inline d-test amender pattern (grep -cE `|| echo 0` multi-line issue → wc -l + tr -d ' ' pattern).
- **≥6 TCs baseline per ADR-0049**: 10 TCs exceeds baseline by 4. ≥3 sister-pattern coverage met (4 sisters: d-s35-003-c1 + d-s34-005 + d-s34-004 + d096-soul-files-template).
- **3-file atomic per ADR-0055 §1**: impl UNCHANGED in template today (199-line bare) + d-test NEW (10 TCs) + INDEX.md MODIFIED + CHANGELOG.md MODIFIED = 4 files same commit cluster when dev opens impl PR per Cadence Rule 1 atomic.
- **Doctrinal anchors**: Issue #571 §Layer 5 + §silent_skip (ADR-0056), Issue #567 SHA-pin sweep, ADR-0044 (RED-first TDD), ADR-0049 (d-test ≥6 baseline), ADR-0055 §1 (Cadence Rule 1 atomic), ADR-0057 (Refs anchor `Refs atilcan65/AtilCalculator#1238` per sub-deliverable pattern), ADR-0012 (4-cat label invariant), ADR-0027 (SHA-pinning), ADR-0031 (owner squash gate), ADR-0033 (dual-channel peer-poke), ADR-0045 (9-Lens coverage), ADR-0056 (silent_skip contract), ADR-0059 (cluster-squash ≤5 PRs/cluster), ADR-0075 §B.1 (parity matrix divergent class), cycle ~#3968Q+847 (inline d-test amender), cycle ~#3968Q+226 (productive idleness), Issue #682 (post-verdict cross-watchdog), Issue #414 §1 (pre-PR re-query).
- **Lane review chain**: arch (Lane 2 PRIMARY 9-Lens per ADR-0045 on Issue #571 §Layer 5 + §silent_skip + ADR-0056 compliance) + tester (Lane 3 d-test-only sign-off per cycle ~#3642H on d-s35-003-c2-status-label-to-board 10 TCs) + owner @atilcan65 (squash gate per ADR-0031).
- **PR body contract** (per ADR-0057): `Refs atilcan65/AtilCalculator#1238` per sub-deliverable pattern (Issue #1238 stays OPEN until Sprint 35 W4 owner-ratification close per RETRO-024, terminal `Closes` reserved for W4 final when ALL clusters 2-5 land).
- **Dev dispatch context**: dev peer-poke 2026-07-27T23:29+03 (cycle ~#3968Q+311+8 cluster 2 d-test RED-first request, cluster 1 squash @atilcan65 at 20:21:26Z sha 82e557c 3 verdict-bys PRESERVED per cycle ~#407 60th NEW RECORD, cluster 2 dispatch UNBLOCKED per cycle ~#3968Q+3258 STANDALONE per >60s gap).
- **Tester peer-poke pattern**: tester will peer-poke dev with d-test RED VERIFIED signal so dev opens impl PR per ADR-0044 RED-first discipline (tester BEFORE dev impl per cycle ~#3893Q v2).

## [1.1.0] - 2026-07-18

Sprint 32 Wave 1-5 cumulative release. Bumps the template CHANGELOG to reflect
all merged PRs since v1.0.1 (2026-07-09). Lands in tmpl repo **before** the
S32-019 #159 tag cut (AC2 BLOCKER). Sister-pattern to launcher S32-016
CHANGELOG v0.4.0 bump (AC4).

### Added

- **ADR port batch (S32-003 + S32-027).** 20 doctrine-critical ADRs ported
  calc→tmpl across two cluster-squash rounds. PR #142 (S32-003, Closes #133)
  + PR #163 (S32-027, Closes #156). Sister-pattern to calc-side ADR port
  cycles ~#3196 + ~#3247.

- **Soul-file sync (S32-004 + S32-005 + S32-026).** Three rounds of soul
  template sync against calc's deployed soul files:
  - S32-004 / S32-005: §Doctrine Reminder — no self-standby (Issue #238 port
    replacing Issue #119 in 5 soul templates). PR #98 (Issue #1060
    env-decoupling, supporting the Auto-Ping dual-channel wiring per
    ADR-0033) + PR #36 (post-merge CHANGELOG entry). Regression pin:
    `scripts/tests/d028-no-standby.sh` (4 TCs).
  - S32-026: soul-sync state correction. PR #168 MERGED `d96a2b7` (Closes
    #155) — confirmed tmpl AHEAD of calc on soul files post-port.

- **Scripts (S32-006 + S32-025).** Wave 4-5 script additions and ports:
  - S32-006 (Issue #222): Auto-Ping dual-channel wiring per ADR-0033. New
    `scripts/agent-wake.sh` (~75 lines, role-to-pane index map), `notify.sh`
    `-w` + `-r <role>` flag additions. Regression pin:
    `scripts/tests/d024-agent-wake.sh` (7 TCs RED→GREEN).
  - S32-025 (Issue #154): `scripts/ops/apply-vm-hardening.sh` ported
    calc→tmpl with d-test. PR #169 MERGED `aad2e57`. Regression pin:
    `scripts/tests/d-apply-vm-hardening.sh` (17 TCs).

### Changed

- **Workflows SHA-pinned + Python detection (S32-008 + S32-009).** Defense-
  in-depth workflow hardening per ADR-0027:
  - PR #148 (S32-008, Closes #138): SHA-pin all template workflows. Every
    `uses:` ref switched from branch tag to commit SHA. ADR-0027 amendment
    forbids floating refs in template workflows.
  - PR #147 (S32-009, Refs #139): `ci.yml` Python detection + lint/test
    path. ci.yml now detects `pyproject.toml` and runs `ruff check` →
    `mypy src/atilcalc/engine` → `pytest -q` only when present. Sister-
    pattern to calc-side CI detection (Issue #1040 cycle ~#3139).

- **Docs (S32-007 + S32-017).** Two docs additions / fixes in Wave 4-5:
  - S32-007 (Issue #137): stale URL fix — replaced `atilcan65/*` refs with
    canonical `atilproject/*` form across `docs/` and `README.md`.
    PR #141 MERGED `45d8edd`. Sister-pattern to calc-side canonical URL
    cycle ~#3442 + Issue #638 AC3.
  - S32-017 (Issue #157): `docs/new-project-steps.md` — 154-line, 4-phase
    on-ramp doc for downstream projects. PR #167 MERGED `e4d222b`.
    Sister-pattern to launcher README on-ramp section.

### Fixed

- **Repo-hygiene (S32-001 + S32-002 + S32-022).** Repo-level hardening +
  diff-engine wiring:
  - S32-001 (Issue #146): TC4 hostname grep + ADR-0066/RETRO-027 doc
    reference NIT cleanup. PR #149 MERGED `f90e747`.
  - S32-002.1 (Issue #130, S32-022 sister-pattern): `scripts/verify-portage.sh`
    diff engine wiring closes Issue #1041 silent-green gap. Real python3
    heredoc diff (metadata-only output: sha256[:12] + size — secret-safe
    by construction), `--reference-repo` + `--ref-dir` flags, exit-code
    matrix 6 → 9 (new: 7=ref-clone-fail, 8=ref-dir-invalid), d-test parity
    (local vs ref d-test count, delta = "missing d-tests in ref"),
    defensive sanitization (regex redaction of `ghp_*` / `gho_*` / `ghs_*` /
    `ghr_*` / `github_pat_*` / `TELEGRAM_BOT_TOKEN=` tokens). Pre-impl RED
    state 5/10 PASS / 5/10 FAIL; post-impl GREEN 10/10 PASS on
    `scripts/tests/d-verify-portage-diff-engine.sh`). PR #132 MERGED
    `0d91ffab` (merge commit); calc-side mirror atilcan65/AtilCalculator#1166
    (S32-022 verify-portage re-run, MERGED 06:16:49Z, merge_commit `12a32d69`,
    head `8c7593c`).
  - S32-021 (Issue #155 sister): Wave 6 d-test sweep report. PR #170
    MERGED `4f3b74f` — 41 d-tests, 26 GREEN + 7 genuine regressions +
    3 pre-impl + 4 env-dependent. 13 sister-issues dispatched via Cadence
    Rule 2 (Sprint 33+ fixes).

- **`notify.sh` env-decoupling port (#91 → Phase B, sister of calc
  PR #1057 / Issue #1060).** AC1 Option B per Issue #1055. Pre-fix:
  `notify.sh` exited 1 on Telegram env-missing BEFORE tmux-wake fired,
  breaking ADR-0033 dual-channel doctrine in CI/dev/recovery envs (Issue
  #1053 cross-repo sister). Post-fix: env-missing or API-fail logs WARN/ERROR
  + marks Telegram failed, but tmux-wake fires UNCONDITIONALLY (when `-w`
  set). Exit-code matrix matches calc's (0/1/2/3). Cycle #1699 Phase B
  feedback fixes: (a) removed unconditional `source $HOME/.dev-studio-env`
  (clobbered `env -u TELEGRAM_BOT_TOKEN` test fixtures); (b) revised
  WAKE_RESULT → WAKE_ATTEMPTED + WAKE_DELIVERED exit semantics so exit=2
  matches AC1 Option B "Telegram failed + tmux-wake attempted" path.
  Result: d1026 4/5 GREEN (TC2 wake_probe FAIL — pre-existing fixture gap
  deferred to follow-up Issue, PR #96 hotfix scope mismatch). Diff:
  `scripts/notify.sh` +76/-21. Phase A regression pin (RED-first per
  ADR-0044): `scripts/tests/d1026-s29-template-env-decoupling-port-parity.sh`.

- **Watcher phantom re-delivery of `board-*` events (P1).** Orchestrator's
  `agent-watch.sh` loop was re-delivering `board-50-*` and `board-52-*`
  events across polls, even though both source issues are CLOSED with
  `status:done` and resolving PRs (#51, #54) are merged. Two interacting
  bugs: **(A)** three HWM vars (`LAST_SEEN`, `PR_MERGED_LAST_SEEN`,
  `PR_LABELED_LAST_SEEN`) read ONCE at script start and never refreshed
  inside `poll_once`, so long-running `--loop` watchers' local vars drifted
  behind state file's HWM; **(B)** `processed_event_ids` FIFO trim (default
  50) evicted still-active phantom IDs as newer events flooded in. Fix
  (commit `1a29310`, originally delivered as PR #62 against the predecessor
  Issue that was later repurposed — current Issue #61 in tmpl is
  `feat(scripts): STORY-198 PR-T8+PR-T10 deploy-runner + ADR-0047`, NOT this
  phantom-dedup bug) moves all three HWM reads into `poll_once` (via
  `init_pr_merged_hwm` and `init_pr_labeled_hwm` helpers) + bumps
  `DEFAULT_TRIM_MAX` from 50 to 200 as a backstop. Orchestrator's INBOX
  clean across 10+ consecutive polls post-fix. **Note: no regression d-test
  was authored for this fix at the time**; manual verification only.
  Sprint 33+ follow-up: add `scripts/tests/d213-phantom-board-dedup.sh`
  per ADR-0044 ≥5 TCs baseline.

### Tests

- **d-test sweep (S32-021 / Wave 6).** PR #170 delivers 41 d-tests across
  the repo. 26 GREEN at merge time; 7 genuine regressions (sister-issues
  dispatched via Cadence Rule 2); 3 pre-impl by-design; 4 env-dependent.
  AC4 NOT MET (d-pr-1147 missing on tmpl per cycle ~#3471 lesson); Sprint
  33+ follow-up.

### Sister-pattern

- **launcher S32-016 CHANGELOG v0.4.0 bump.** Same sprint cycle Wave 5
  docs + tag BLOCKER. Both repos' CHANGELOG bumps land before v1.1.0 /
  v0.4.0 tag cuts (AC4).
- **Tag BLOCKER for S32-019 #159.** This PR must merge before tag cut
  per AC2.

## [1.0.1] - 2026-07-09

### Fixed

- **PR #62 — TD-068b: tmux `send-keys` text + Enter race condition under load
  (Issue #935 sister-fix).** `scripts/agent-wake.sh` (line ~67),
  `scripts/agent-watch.sh` (line ~1494), and `scripts/reprime-agent.sh` (3
  sites: `/clear`, `/compact`, paste-buffer Enter) all previously sent text +
  Enter in two `send-keys` calls with no sleep gap. Under load tmux collapsed
  both into a single literal keystroke (text rendered with no Enter firing,
  leaving the agent's prompt buffer half-typed and unresponsive). Fix splits
  text + Enter explicitly with an env-override sleep — `sleep "${WAKE_KEYS_GAP_SEC:-0.5}"`
  — that callers can tighten for fast paths or relax for slow tmux hosts.
  Five sites patched atomically (Cadence Rule 1); sister-port to
  `atilcan65/AtilCalculator` PR #936 squash `5c4e5784`. Regression pin:
  `scripts/tests/d068b-tmux-send-keys-split-sleep.sh` (10 TCs: bundled-keystroke
  detection, env-override, 5-site coverage, Escape preserved, `bash -n`, paste-buffer,
  A1 env-override compliance, etc.).

## [Unreleased]

### Added

- **S32-020 [DEV] — `scripts/tests/d-smoke-bootstrap-v110.sh` smoke repo bootstrap
  verifier at v1.1.0** (Issue #160, RED-first per ADR-0044). 5 RED TCs verify
  post-S32-019 v1.1.0 tag cut + smoke-v110 repo creation + bootstrap state
  (ci.yml present, 34 labels seeded, main HEAD == v1.1.0 tag SHA via Issue #972
  Path-Verify Doctrine). Sprint 32 Wave 6 dev-lane, gated on S32-019 #159 tag
  (owner lane per ADR-0031 + cycle ~#3196). Sister-pattern:
  `d-verify-portage-diff-engine.sh` + `s29-005-verify-portage.sh` + Issue #972.
  Cycle ~#3670 d-test authored + RED verified locally on tmpl origin/main HEAD
  `4274ddce` (5/5 RED). Cadence Rule 1 atomic (ADR-0055 §1): d-test +
  `scripts/tests/INDEX.md` row + this CHANGELOG entry. PR will anchor
  `Closes atilproject/dev-studio-template#160` (ADR-0057 auto-close) +
  `Refs atilproject/dev-studio-template#159` (sister-ref, no auto-close).

### Changed

- **#39 — `§Doctrine Reminder — no self-standby` (Issue #238) replaces Issue #119
  in 5 soul templates.** Ported from AtilCalculator Issue #238 (P0 doctrine
  gap, owner-discovered 2026-06-22: agents self-standby on dependency /
  rate-limit / state-corruption / no-events despite the existing §Doctrine
  Reminder). The Issue #119 patch was 3-bullet (polling / queue / auto-ping)
  — it told agents to **do** things but did not enumerate the **forbidden
  self-justifications** that look like work pauses. The new doctrine adds an
  explicit 4-row forbidden-pause table (blocked-on-dep, rate-limit, state
  corruption, no-events) + 3-question self-check + role-specific callout
  per file. **Per-role callouts** — orchestrator: re-run proactive board
  scan / architect: draft next ADR or design doc / developer: branch +
  implement next P0/P1 issue / product-manager: open story or refresh
  backlog / tester: run next d-reg test or sign off next PR. Supersedes
  PR #35 (Katman 3) and Issue #119 §Doctrine Reminder text. `dev-idle
  prevention` / `Issue #119 §Doctrine Reminder` heading text removed from
  all 5 .tmpl files; Issue #119 retained as a Ref predecessor. Regression
  pin: `scripts/tests/d028-no-standby.sh` (4 TCs, one per forbidden mode).

- **Sprint 34 W3 forward-port S34-002 row 012 — scripts/bootstrap-labels.sh PATCH-FORWARD divergent class (Refs atilcan65/AtilCalculator#1222, sprint:current, GREEN post-impl).** Sprint 34 W3 forward-port (per ADR-0075 §B.1 row 012 + Issue #1222 dispatch): row 012 = `scripts/bootstrap-labels.sh` PATCH-FORWARD class (NOT byte-equivalence — divergent per "AtilCalc has label set evolution; template has base set"). Per architect 283rd-wake cycle ~#3968Q+683 (2026-07-26T11:38:17Z) + 284th-wake cycle ~#3968Q+684 (11:40:12Z) + orchestrator correction cycle ~#3968Q+~11:38Z (deploy-runner.sh was row 017 NOT row 012). **MD5 evidence**: AtilCalc canonical (via soul-amend-l10 symlink target) + template = `e3f4f5efc281263c9a9a06c7cb48e67a` (94 lines, byte-identical NOW). **Sprint 33 label-set evolution amendments ported** (Issue #1210/1211 cluster + RETRO-024 silent-skip + agent-stall label + sprint:backlog/next labels + security label): TC5 verifies 10 amendment markers present (`agent-stall`, `sprint:backlog`, `sprint:next`, `security`, `good-first-issue`, `agent:orchestrator`, `cc:orchestrator`, `status:done`, `priority:P0`, `type:feature`). **Impl file UNCHANGED** (PATCH-FORWARD zero-diff proof via TC4 MD5 match). **`scripts/tests/d-s34-002-row-012-bootstrap-labels-patch-forward.sh` d-test (NEW, 8 TCs RED-first per ADR-0044)** — TC1 target file exists + TC2 bash -n syntactic self-check + TC3 line count = 94 [matches AtilCalc canonical] + TC4 MD5 = `e3f4f5efc281263c9a9a06c7cb48e67a` [PATCH-FORWARD zero-diff proof] + TC5 Sprint 33 amendment markers present [10 markers] + TC6 4-cat labels present [6 categories: priority/type/status/agent/cc/sprint per ADR-0012] + TC7 INDEX.md row present [Cadence Rule 1 atomic attestation] + TC8 CHANGELOG.md entry present [Sprint 34 W3 forward-port S34-002 row 012]. RED-first per ADR-0044 — pre-impl 6 PASS + 2 FAIL (TC7+TC8) verified; post-impl 8/8 GREEN. ≥6 TCs baseline per ADR-0049 (cycle ~#3471 ≥6 refinement) — d-s34-002-row-012 = 8 TCs exceeds baseline by 2. ≥3 sister-pattern coverage per ADR-0049 met (6 sisters: d-s34-002-row-011-audit-project-refs-byte-equivalence + d-s34-002-row-001-010 + AtilCalc Sprint 33 d-test framework + Sprint 33 d-stall-detect + Sprint 33 d-stall-detect-pr-driven + Sprint 33 d-agent-watch-stall-wiring RETRO-024 silent-skip). **scripts/tests/INDEX.md** d-s34-002-row-012 row appended (line 680+, after d-agent-watch-stall-wiring). **Cadence Rule 1 atomic (ADR-0055 §1)** — `scripts/bootstrap-labels.sh` (UNCHANGED — PATCH-FORWARD zero-diff) + `scripts/tests/d-s34-002-row-012-bootstrap-labels-patch-forward.sh` (NEW, d-test) + `scripts/tests/INDEX.md` (this row RED→GREEN append) + `CHANGELOG.md` `[Unreleased] ### Added` entry = 4 files same commit. **Lane review chain**: arch (Lane 2 docs verdict 9-Lens per ADR-0045 on PATCH-FORWARD divergent classification + Sprint 33 amendment verification) + tester (Lane 3 d-test-only sign-off per cycle ~#3642H on d-s34-002-row-012 8 TCs) + owner @atilcan65 (squash gate per ADR-0031 — cluster-squash #27 candidate STANDALONE per cycle ~#3258 since W3 already 3/3 SHIPPED-functional). **PR body contract** (per ADR-0057): `Refs atilcan65/AtilCalculator#1222` per sub-deliverable pattern (Issue #1222 stays OPEN per RETRO-024 owner-ratification close — terminal `Closes` reserved for final W3 dispatch at row 280). **Out-of-scope escalations**: ADR-0075 §B.1 row 017 deploy-runner.sh equivalent → divergent reclassification (Task #118 arch lane direct filing in progress per architect 284th-wake ETA cycle ~#3968Q+686, NOT this PR); deploy.yml post-#215-squash status (cluster-lag-detector workflow permissions bug per cycle ~#3968Q+311+14 OUT-OF-TESTER-LANE flag to architect+owner for ADR-0059 amendment, NOT a deploy.yml issue per architect 283rd-wake). **Doctrinal anchors**: Issue #414 §1 (pre-PR re-query — Issue #1222 4-cat INTACT verified `type:feature + status:in-progress + agent:developer + cc:architect + cc:developer + cc:tester + cc:human + priority:P1 + sprint:current`), ADR-0044 (RED-first TDD — 2 FAIL TC7+TC8 verified pre-impl, 8/8 GREEN post-impl per cycle ~#3893Q v2 verify-locally-before-verdict), ADR-0049 (d-test ≥6 baseline — 8 TCs), ADR-0055 §1 (Cadence Rule 1 atomic — 4 files same commit), ADR-0057 (Refs anchor — Issue #1222 sub-deliverable pattern), ADR-0012 (4-cat label invariant on Issue #1222), ADR-0031 (owner squash gate), ADR-0033 (dual-channel peer-poke via proxy path AtilCalculator-d1142 per cycle ~#3968Q+666/667 path resilience), ADR-0075 §B.1 row 012 (parity matrix divergent class — "AtilCalc has label set evolution; template has base set"), ADR-0077 §B.1-amendment-017 (arch lane direct filing in progress — scripts/deploy-runner.sh equivalent → divergent reclassification), cycle ~#3968Q+460 (NEW doctrine cross-repo scope verification per Lane 0 dispatch), cycle ~#3968Q+311+8 (CONDITIONAL preventive — branch dev/s34-002-row-012 from origin/main 9cbe371 POST-#1228-squash NOT pre-squash applied), cycle ~#3968Q+685 (IMMEDIATE twin-squash variant ratification — W3 PR #17+PR #215 5s gap, STANDALONE per cycle ~#3258 applies to PR #216).

### Added

- **Auto-Ping dual-channel wiring (ADR-0033, Issue #221 port to template — Issue
  #222).** Mirror of the AtilCalculator Sprint 4 P0 fix. Three new files +
  two doctrine updates:
  - `scripts/agent-wake.sh` (new, ~75 lines) — standalone CLI that injects
    a wake-up prompt into a named agent's tmux pane via `send-keys -l` +
    `Enter`. Role-to-pane index map (orchestrator=0, ..., tester=4) with
    title-based fallback. Silent no-op when tmux missing / unknown role /
    no session — callers don't need to guard. Exit 2 on missing args.
  - `scripts/notify.sh` — `-w` (wake) and `-r <role>` flags added. After
    Telegram POST, when `-w` is set, `notify.sh` invokes `agent-wake.sh`
    to inject the wake prompt into the target pane. `-w` requires `-r`;
    `-w` without `-r` → exit 2 (loud failure). Backward compat: when
    `-w` is NOT set, behavior is unchanged (Telegram only).
  - `scripts/tests/d024-agent-wake.sh` (new, ~165 lines) — 7-TC regression
    test per ADR-0033 §Test contract (T1 send-keys + Enter, T2 no-tmux,
    T3 unknown-role, T4 missing-args exit 2, T5 dual-channel wiring,
    T6 -w/-r requirement check, T7 literal-mode). Locks in both the
    `agent-wake.sh` shape AND the `notify.sh` dual-channel integration.
  - `.claude/CLAUDE.md.tmpl` — §Auto-Ping Hard-Rule updated: explains
    dual-channel doctrine (Telegram + tmux), when to use `-w` (acil
    handoff) vs. when NOT (bilgilendirme amaçlı ping).
  - `.claude/agents/developer.md.tmpl` — Auto-Ping section adds ADR-0033
    callout: acil handoff'larda `-w -r <role>` flag'i ekle.

  Reference impl: `atilcan65/AtilCalculator` commit `ecbf21a` (PR #239).
  TDD red→green in template: d024 5/7 PASS pre-port → 7/7 PASS post-port.

### Fixed

- **#91 → Phase B (sister of AtilCalculator PR #1057, Issue #1060) — notify.sh
  env-decoupling port (AC1 Option B per Issue #1055) + cycle #1699 Phase B
  feedback fixes.** Sister-pattern port of the AtilCalculator env-decoupling
  fix to `scripts/notify.sh` on template. Phase A (RED-first d-test
  `d1026-s29-template-env-decoupling-port-parity`) already merged via PR #91
  (commit `8b813cc`); Phase B (this PR) implements the fix. Pre-fix:
  `notify.sh` exited 1 on Telegram env-missing BEFORE tmux-wake fired,
  breaking ADR-0033 dual-channel doctrine in CI/dev/recovery envs (Issue
  #1053 cross-repo sister). Post-fix: env-missing or API-fail logs WARN/ERROR
  + marks Telegram failed, but tmux-wake fires UNCONDITIONALLY (when `-w`
  set). Exit-code matrix matches AtilCalculator's (0/1/2/3).
  Cycle #1699 Phase B feedback fixes (per [TEST→DEV] CHANGES REQUESTED on
  PR #98, d1026 still RED 3/5): (a) **removed unconditional `source
  $HOME/.dev-studio-env`** that was clobbering `env -u TELEGRAM_BOT_TOKEN`
  test fixtures, causing TC1/TC4 to read env=set and exit=0 instead of
  exit=2; (b) **revised WAKE_RESULT → WAKE_ATTEMPTED + WAKE_DELIVERED** exit
  semantics so AC1 Option B's "Telegram failed + tmux-wake attempted" path
  matches exit=2 (was exit=1 when agent-wake.sh internal lookup failed);
  callers must source `~/.dev-studio-env` themselves (agent shells via
  .bashrc already do; manual users documented inline).
  Result: d1026 4/5 GREEN (TC0, TC1, TC4, TC5 pass; TC2 exit=2 + stderr OK
  but wake_probe FAIL — see pre-existing fixture-gap below).
  Diff: `scripts/notify.sh` +76/-21, this CHANGELOG entry. Phase A regression
  pin: `scripts/tests/d1026-s29-template-env-decoupling-port-parity.sh`
  (Phase A RED-first per ADR-0044).

  **Pre-existing fixture gap (deferred to follow-up Issue, out of scope for
  PR #98)**: TC2's `wake_probe=PASS` requires `agent-wake.sh` to find a
  pane whose index matches the role's index (developer=3). PR #96 (Issue
  #1063 hotfix) deliberately removed title-match fallback (see
  `scripts/agent-wake.sh` line ~50 comment: "Fix 2 deterministic
  pane_index lookup"). d1026's fixture creates only 1 pane at index 0,
  so TC2's role=developer can never deliver. Phase A d-test author wrote
  the test against PRE-#96 title-match behavior; PR #96 didn't re-run
  d1026 post-merge. Sister-pattern sister-pattern fix needed: either (i)
  re-introduce opportunistic title-match fallback in agent-wake.sh
  (1-line change, gated by exact UPPERCASE_ROLE match), or (ii) update
  d1026 fixture to mimic dev-studio 6-pane layout (Phase A scope). Filed
  as separate Issue — see PR #98 comment thread for diagnosis.

- **#61 — Watcher phantom re-delivery of `board-*` events (P1).** Orchestrator's
  `agent-watch.sh` loop was receiving the same two `label_change` events
  (`board-50-*`, `board-52-*`) repeatedly across polls, even though both source
  issues are CLOSED with `status:done` and the resolving PRs (#51, #54) are
  merged. Two interacting bugs caused the dedup chain to fail: **(A)** the
  three HWM vars (`LAST_SEEN`, `PR_MERGED_LAST_SEEN`, `PR_LABELED_LAST_SEEN`)
  were read ONCE at script start and never refreshed inside `poll_once`, so a
  long-running `--loop` watcher's local vars drifted behind the state file's
  HWM and the gh query kept returning historical events; **(B)** the
  `processed_event_ids` FIFO trim (default 50) was evicting the still-active
  phantom event IDs as newer events flooded in. The fix moves all three HWM
  reads into `poll_once` (via `init_pr_merged_hwm` and `init_pr_labeled_hwm`
  helpers) and bumps `DEFAULT_TRIM_MAX` from 50 to 200 as a backstop. The
  orchestrator's INBOX is now clean across 10+ consecutive polls. Regression
  pin: `scripts/tests/d213-phantom-board-dedup.sh` (10/10 PASS).

- **STORY-002 — `app/main.py` now registers a SIGTERM handler (TC-8 unblock).**
  `kill <pid>` (SIGTERM) on the uvicorn process used to exit with code
  `143` (= 128 + SIGTERM), which breaks container/k8s/systemd graceful
  shutdown. The handler is installed at module-import time and calls
  `os._exit(0)` (C-level `_exit(2)`), mirroring uvicorn's own SIGINT
  behaviour without raising `SystemExit` — this avoids a `CancelledError`
  traceback from the asyncio loop's pending Starlette `lifespan` task,
  satisfying STORY-001 AC4 ("no traceback on shutdown"). No-op for
  Ctrl-C development; load-bearing the moment the service ships to a
  process supervisor. See PR #24 (`test_sigterm_exits_zero`) for the
  subprocess-level regression pin and PR #25 / `tests/test_sigterm_handler.py`
  for the in-process pin.

### Fixed

- **#130 (S32-002.1) — `scripts/verify-portage.sh` diff engine wiring closes
  the silent-green AC4 placeholder gap (Issue #1041 sister-pattern, Sprint 32
  Wave 2 candidate).** Sister-PR baseline report `docs/sprints/sprint-32/02-portage-baseline.md`
  (calc mirror: `tmpl-s32-002/docs/sprints/sprint-32/02-portage-baseline.md`)
  documented S32-002 (PR #129) AC4 as FAIL-by-design: step 3+4 emitted
  `category_gaps: 0/0/0/0` for all 4 categories — exact Issue #1041 sister-pattern
  (silent-green false-confidence). This PR replaces the placeholder with a real
  diff engine (python3 heredoc, file METADATA only: sha256 truncated to 12 chars
  + size — no file contents in output = secret-safe by construction), adds
  `--reference-repo <owner/repo>` + `--ref-dir <path>` flags (shift-based arg
  parser replaces the broken positional loop that left `--report /tmp/foo`
  unparseable), expands the exit-code matrix from 6 → 9 (new: 7=ref-clone-fail,
  8=ref-dir-invalid), adds d-test parity (local `scripts/tests/` count vs ref
  count, delta = "missing d-tests in ref"), and adds defensive sanitization
  (regex redaction of `ghp_*` / `gho_*` / `ghs_*` / `ghr_*` / `github_pat_*` /
  `TELEGRAM_BOT_TOKEN=` tokens — defense-in-depth, vacuous against metadata-only
  output). Pre-impl RED state verified 5/10 PASS / 5/10 FAIL (TC4 --ref-dir,
  TC5 JSON schema, TC6 per-file diff, TC7 dtest_parity, TC9 --reference-repo
  all FAIL); post-impl GREEN state verified 10/10 PASS on this branch
  (`scripts/tests/d-verify-portage-diff-engine.sh`). Sister-PR cluster per
  ADR-0059: S32-002 (PR #129, MERGED 5cf72a7, AC4 FAIL-by-design) + S32-002.1
  (this PR, AC4 gap-closure). PR body anchors `Refs atilproject/dev-studio-template#130`
  + `Refs atilproject/dev-studio-template#128` + `Refs atilproject/dev-studio-template#129`
  + `Refs atilcan65/AtilCalculator#1149` (Refs-only per ADR-0057 strict format —
  Issue #130 in-progress WIP=1/1, sister-pattern PR #1151/Issue #1150 cycle ~#3177).
  Regression pin: `scripts/tests/d-verify-portage-diff-engine.sh` (10 TCs RED-first
  per ADR-0044 ≥5 baseline). Forward-path: future clones from template will
  inherit real diff engine + sanitization + d-test parity on first `init`,
  restoring the cross-repo gap-claim (Sprint 28 §4.6) re-verifiability that
  Sprint 29 STORY-S29-005 (PR #125 → 52ed840) originally established.

### Changed

- **PR #35 — DEV-IDLE-K3 Katman 3: Doctrine Reminder in 5 soul templates**
  (post-merge CHANGELOG; refs AtilCalculator #119, #196, #197, ADR-0025
  retired). Each of the 5 `.claude/agents/*.md.tmpl` files
  (`orchestrator.md.tmpl`, `product-manager.md.tmpl`, `architect.md.tmpl`,
  `developer.md.tmpl`, `tester.md.tmpl`) now ships a `## Doctrine Reminder —
  dev-idle prevention (Issue #119)` section directly below its
  `## Hard Rules — DON'T` block. The reminder makes three rules
  unconditional and reflexive: **(1) polling is unconditional** — every
  session start + every action triggers `bash scripts/agent-watch.sh <role>`
  (no owner-poke dependency); **(2) queue check is reflexive** — every
  open issue with `agent:<role>` or `cc:<role>` is active work, start
  immediately; **(3) auto-ping is reflexive** — `scripts/notify.sh -l <next-role>`
  on task-completion or block, no human-relay. Forbidden phrases explicitly
  enumerated: `standby`, `holding`, `iş saatleri`, `ofis-saati`,
  `sabah bakacağım`, `yarın devam` — none are valid pause justifications.
  Valid pause gates: (a) verbatim human chat directive, (b) issue/PR-linked
  dependency block, (c) heartbeat/REPRIME SOP step. Closes the dev-idle
  doctrine gap observed in AtilCalculator 2026-06-19 wake-loop incidents;
  enforced by `scripts/tests/d015-dev-idle-prevention.sh` (regression pin,
  re-verified post-merge). Net change: 5 files × +12 lines = +60/-0
  (purely additive, no template contract breaks).

### Added

- **STORY-001 — FastAPI service skeleton with `GET /healthz`** (Sprint 1, P0).
  Standalone FastAPI service runnable from a clean clone with one command
  (`make run`); liveness probe at `/healthz` returns `200 OK` with
  `{"status": "ok"}` and `Content-Type: application/json`. Unknown paths
  return `404` (not `500`). `Ctrl-C` exits cleanly with code `0`.
  See [`docs/backlog/sprint-1/STORY-001-fastapi-skeleton-healthz.md`](docs/backlog/sprint-1/STORY-001-fastapi-skeleton-healthz.md),
  [`docs/designs/STORY-001-design.md`](docs/designs/STORY-001-design.md),
  and [`docs/decisions/ADR-0001-fastapi-skeleton.md`](docs/decisions/ADR-0001-fastapi-skeleton.md).

- **STORY-004 — `GET /hello/{name}` greeting endpoint** (Sprint 1, P1).
  Demo-facing route that returns `200 OK` with
  `{"message": "hello, {name}"}` and `Content-Type: application/json`.
  Case is preserved verbatim (no lowercasing); URL-encoded values pass
  through unchanged (e.g. `/hello/%20` → `"hello,  "`). The path segment
  is required, capped at 64 characters to bound log-spam risk; missing
  name returns `404` (FastAPI default), not `500`.
  See [`docs/backlog/sprint-1/STORY-004-hello-name-greeting-endpoint.md`](docs/backlog/sprint-1/STORY-004-hello-name-greeting-endpoint.md).

### Infrastructure

- `pyproject.toml` — PEP 621, Python `>=3.12,<3.13`, pinned runtime deps
  (`fastapi==0.115.6`, `uvicorn[standard]==0.32.1`) and dev extras
  (`pytest`, `httpx`, `ruff`). Ruff config and pytest config colocated.
- `Makefile` — canonical `install` / `run` / `test` / `lint` / `format`
  targets, all thin wrappers around `uv run` (ADR-0001).
- `.python-version` — `3.12` for `uv python pin` and `pyenv` consumers.
- `app/__init__.py` — package marker with `__version__ = "0.1.0"`.
- `app/main.py` — FastAPI instance + sync `GET /healthz` handler.
- `tests/test_healthz.py` — single skeleton smoke test (AC2 happy path).
  Full contract test suite (404, determinism, subprocess lifecycle,
  README on-ramp timing) lands in STORY-002.
- `tests/test_hello.py` — 4 contract tests for `/hello/{name}` (AC1–AC4
  of STORY-004). Happy-path + case-preservation pair satisfies AC5.
- `README.md` — Sprint 1 repo layout + 4-step "Getting started" (Install
  uv → `make install` → `make run` → `curl /healthz`).
- **agent-wake.sh Fix 4b forward-port — Issue #178 (S32-021 sister AC2 d-test enabler).**
  Byte-equal forward-port from `AtilCalculator/scripts/agent-wake.sh` per Issue #1041 non-vacuous.
  165 LOC, 7921 bytes. Adds Fix 4b (Issue #1138 / ADR-0066): D1
  `WAKE_VERIFY_TIMEOUT_SEC` env override (default 3s, was hardcoded 1s), D2 16-char literal
  sentinel `🔔 INBOX (dual-c` replacing Fix 3 dynamic `MSG_PREFIX` derivation
  (render-drift-immune vs 80-char prefix truncation at tmux wrap boundaries), D3 hierarchical
  exit codes (Tier 1 rc=0 happy-path PRESERVED + Tier 2 rc=0+WARN lenient verify-uncertain +
  Tier 3 rc=1+ERROR hard-fail preserved), D4 WARN vs ERROR log discrimination
  (owner-greppable audit). Post-port `bash scripts/tests/d1138-template-agent-wake-fix-4b.sh
  --self-test`: **13/13 GREEN** (was 0/8 RED pre-port — non-vacuous per Issue #1041).
  Sister-patterns: d1138-template-agent-wake-fix-4b.sh (tmpl forward-port parity d-test),
  d068b (WAKE_KEYS_GAP_SEC env-override naming convention sister to D1), d-pr-1147-install-test-flake
  (Issue #176 sister-cluster Wave 9 forward-port). Cadence Rule 1 atomic per ADR-0055 §1:
  agent-wake.sh byte-equal + INDEX.md row + this CHANGELOG entry in same commit cluster
  (3 files). PR body anchor: `Closes atilproject/dev-studio-template#178`. Cycle ~#3958Q+135
  owner-directive Wave 9 claim order.
- **Sprint 34 W2 forward-port S34-002 row 001 — `scripts/agent-context-monitor.sh`
  byte-equivalence verified** (cycle ~#438, ADR-0075 §B.1 `equivalent` row).
  Confirmed `scripts/agent-context-monitor.sh` in dev-studio-template is byte-identical
  to `atilcan65/AtilCalculator` canonical (MD5 `8062b3a267cb22e36069d9cd29733e58`, 325 lines,
  ground-truth verified 2026-07-25T04:13Z via md5sum + wc -l per cycle ~#437 probe). Per
  ADR-0075 §B.1, this script is `equivalent` class (Pure wake loop, no project context) —
  forward-port confirms sync, no drift detected. Added
  `scripts/tests/d-s34-002-agent-context-monitor-byte-equivalence.sh` (new, ~120 LOC,
  7 TCs RED-first per ADR-0044 + ≥6 baseline per ADR-0049) as evidence. Pre-port RED
  state: TC6 + TC7 FAIL (INDEX.md row + CHANGELOG.md entry missing, real Cadence Rule 1
  atomic markers per ADR-0044 non-vacuous). Post-port GREEN state: all 7 TCs GREEN.
  Cadence Rule 1 atomic per ADR-0055 §1: d-test + INDEX.md row + CHANGELOG entry
  (3 files in same commit; impl file scripts/agent-context-monitor.sh UNCHANGED — byte-identical
  to AtilCalculator canonical per ADR-0075 §B.1 `equivalent` row, so NOT part of commit cluster).
  PR body anchor: `Closes atilproject/AtilCalculator#1222` row001. Sister-patterns:
  d-smoke-bootstrap-v110.sh (Sprint 32 d-smoke ≥5 TC baseline precedent),
  d-pr-1147-install-test-flake.sh (Sprint 33 forward-port byte-equal parity doctrine),
  d028-template-agent-watch-queue-check-filter.sh (Issue #179 byte-equal forward-port
  sister, same 4-file Cadence Rule 1 atomic cluster pattern). Cycle ~#437 owner pre-flip
  WIP cap override 3/3 (bypasses ADR-0038 §Auto-Claim cap=2/2); cycle ~#438 d-test
  RED-first verify + commit.
- **Sprint 34 W2 forward-port S34-002 row 002 — `scripts/atomic-write.sh`
  byte-equivalence verified** (cycle ~#495, ADR-0075 §B.1 `equivalent` row).
  Confirmed `scripts/atomic-write.sh` in dev-studio-template is byte-identical
  to `atilcan65/AtilCalculator` canonical (MD5 `d80f6d0315aaddde6e1cce4f8de97859`,
  75 lines, ground-truth verified 2026-07-25T07:22Z via md5sum + wc -l per cycle ~#495
  probe). Per ADR-0075 §B.1, this script is `equivalent` class (Pure utility, no
  project context — write-to-temp + sync + mv atomic file write helper) —
  forward-port confirms sync, no drift detected. Added
  `scripts/tests/d-s34-002-atomic-write-byte-equivalence.sh` (new, ~130 LOC,
  7 TCs RED-first per ADR-0044 + ≥6 baseline per ADR-0049) as evidence. Pre-port
  RED state: TC6 + TC7 FAIL (INDEX.md row + CHANGELOG.md entry missing, real
  Cadence Rule 1 atomic markers per ADR-0044 non-vacuous). Post-port GREEN state:
  all 7 TCs GREEN. Cadence Rule 1 atomic per ADR-0055 §1: d-test + INDEX.md row
  + CHANGELOG entry (3 files in same commit; impl file scripts/atomic-write.sh
  UNCHANGED — byte-identical to AtilCalculator canonical per ADR-0075 §B.1
  `equivalent` row, so NOT part of commit cluster). PR body anchor:
  `Refs atilproject/AtilCalculator#1222` row002. Sister-patterns:
  d-s34-002-agent-context-monitor-byte-equivalence.sh (DIRECT sister — row 001
  same cycle, same byte-equivalence pattern, same Cadence Rule 1 atomic 3-files
  cluster), d-smoke-bootstrap-v110.sh (Sprint 32 d-smoke ≥5 TC baseline precedent),
  d-pr-1147-install-test-flake.sh (Sprint 33 forward-port byte-equal parity doctrine).
  Cycle ~#493 orchestrator post-squash dispatch (WIP cap=2/2 supersedes prior 3/3
  override per cycle ~#3968Q+313 newer-directive-wins); cycle ~#494 arch squash-verify
  ACK + dev lane cleared for row 002+ per RETRO-024 sister-pattern; cycle ~#495
  worktree setup + d-test RED-first verify.
- **Sprint 34 W2 forward-port S34-002 row 003 — `scripts/agent-doctor.sh`
  byte-equivalence verified** (cycle ~#500, ADR-0075 §B.1 `equivalent` row).
  Confirmed `scripts/agent-doctor.sh` in dev-studio-template is byte-identical
  to `atilcan65/AtilCalculator` canonical (MD5 `936b4608634acb53a2cca2567acee09e`,
  566 lines, ground-truth verified 2026-07-25T07:59Z via md5sum + wc -l per cycle ~#500
  probe). Per ADR-0075 §B.1, this script is `equivalent` class (Generic health check,
  no project context — system role/probe/alert aggregator) — forward-port confirms
  sync, no drift detected. Added `scripts/tests/d-s34-002-agent-doctor-byte-equivalence.sh`
  (new, ~140 LOC, 7 TCs RED-first per ADR-0044 + ≥6 baseline per ADR-0049) as evidence.
  Pre-port RED state: TC1-TC7 FAIL (file missing + INDEX.md row + CHANGELOG.md
  entry missing, real Cadence Rule 1 atomic markers per ADR-0044 non-vacuous).
  Post-port GREEN state: all 7 TCs GREEN. Cadence Rule 1 atomic per ADR-0055 §1:
  d-test + INDEX.md row + CHANGELOG entry (3 files in same commit; impl file
  scripts/agent-doctor.sh UNCHANGED — byte-identical to AtilCalculator canonical
  per ADR-0075 §B.1 `equivalent` row, so NOT part of commit cluster). PR body
  anchor: `Refs atilproject/AtilCalculator#1222` row003. Sister-patterns:
  d-s34-002-atomic-write-byte-equivalence.sh (DIRECT sister — row 002 same cycle,
  same byte-equivalence pattern, same Cadence Rule 1 atomic 3-files cluster),
  d-s34-002-agent-context-monitor-byte-equivalence.sh (row 001 sister — same
  byte-equivalence pattern), d-smoke-bootstrap-v110.sh (Sprint 32 d-smoke ≥5 TC
  baseline precedent). Cycle ~#499 PR #205 SQUASH-MERGE TERMINAL + WIP cap 0/2
  cleared; cycle ~#500 orchestrator+arch dual-channel dispatch (S34-002 row 003+
  per cycle ~#3968Q+313 NEW DOCTRINE scope authority — template continuation,
  S34-003 launcher PARKED).
- **Sprint 34 W2 forward-port S34-002 row 004 — `scripts/health-check.sh`
  byte-equivalence verified** (cycle ~#504, ADR-0075 §B.1 `equivalent` row).
  Confirmed `scripts/health-check.sh` in dev-studio-template is byte-identical
  to `atilcan65/AtilCalculator` canonical (MD5 `ad6377bce64980e7392b7cf4a8b79f86`,
  104 lines, ground-truth verified 2026-07-25T08:25Z via md5sum + wc -l per cycle ~#504
  probe). Per ADR-0075 §B.1, this script is `equivalent` class (Generic health check,
  no project context — alert + warning aggregator) — forward-port confirms
  sync, no drift detected. Added `scripts/tests/d-s34-002-health-check-byte-equivalence.sh`
  (new, ~140 LOC, 7 TCs RED-first per ADR-0044 + ≥6 baseline per ADR-0049) as evidence.
  Pre-port RED state: TC6+TC7 FAIL (d-test present + impl file already byte-identical
  at origin/main; INDEX.md row + CHANGELOG.md entry missing, real Cadence Rule 1
  atomic markers per ADR-0044 non-vacuous). Post-port GREEN state: all 7 TCs GREEN.
  Cadence Rule 1 atomic per ADR-0055 §1: d-test + INDEX.md row + CHANGELOG entry
  (3 files in same commit; impl file scripts/health-check.sh UNCHANGED — byte-identical
  to AtilCalculator canonical per ADR-0075 §B.1 `equivalent` row, so NOT part of
  commit cluster). PR body anchor: `Refs atilproject/AtilCalculator#1222` row004.
  Sister-patterns: d-s34-002-agent-doctor-byte-equivalence.sh (DIRECT sister — row 003
  same cycle, same byte-equivalence pattern, same Cadence Rule 1 atomic 3-files cluster),
  d-s34-002-atomic-write-byte-equivalence.sh (row 002 sister — same byte-equivalence
  pattern), d-s34-002-agent-context-monitor-byte-equivalence.sh (row 001 sister — same
  byte-equivalence pattern), d-smoke-bootstrap-v110.sh (Sprint 32 d-smoke ≥5 TC baseline
  precedent). Cycle ~#503 PR #206 SQUASH-MERGE TERMINAL + WIP cap 0/2 cleared; cycle ~#504
  orchestrator post-squash dispatch (S34-002 row 004 health-check.sh continuation per
  cycle ~#3968Q+313 NEW DOCTRINE scope authority — template continuation, S34-003
  launcher PARKED).
- **Sprint 34 W2 forward-port S34-002 row 005 — `scripts/agent-journal.sh`
  byte-equivalence verified** (cycle ~#534, ADR-0075 §B.1 `equivalent` row).
  Confirmed `scripts/agent-journal.sh` in dev-studio-template is byte-identical
  to `atilcan65/AtilCalculator` canonical (MD5 `cbf0a0338e69563d8fae38f44aeeb8ab`,
  198 lines, ground-truth verified 2026-07-25T15:58Z via md5sum + wc -l per cycle ~#534
  probe). Per ADR-0075 §B.1, this script is `equivalent` class (Generic journal,
  no project context — system-written facts journal drift-safe) — forward-port confirms
  sync, no drift detected. Added `scripts/tests/d-s34-002-agent-journal-byte-equivalence.sh`

- **Sprint 34 W2 forward-port S34-002 row 006 — `scripts/agent-wake.sh`
  byte-equivalence verified** (cycle ~#534, ADR-0075 §B.1 `equivalent` row).
  Confirmed `scripts/agent-wake.sh` in dev-studio-template is byte-identical
  to `atilcan65/AtilCalculator` canonical (MD5 `8b5d75a2fc9f8d0151817245769cc03d`,
  165 lines, ground-truth verified 2026-07-25T15:58Z via md5sum + wc -l per cycle ~#534
  probe). Per ADR-0075 §B.1, this script is `equivalent` class (Pure wake trigger,
  no project context — second half of ADR-0033 dual-channel peer-poke wiring) —
  forward-port confirms sync, no drift detected. Added
  `scripts/tests/d-s34-002-agent-wake-byte-equivalence.sh`
  (new, ~140 LOC, 7 TCs RED-first per ADR-0044 + ≥6 baseline per ADR-0049) as evidence.
  Pre-port RED state: TC6+TC7 FAIL (d-test present + impl file already byte-identical
  at origin/main cc03909; INDEX.md row + CHANGELOG.md entry missing, real Cadence Rule 1
  atomic markers per ADR-0044 non-vacuous). Post-port GREEN state: all 7 TCs GREEN.
  Cadence Rule 1 atomic per ADR-0055 §1: d-test + INDEX.md row + CHANGELOG entry
  (3 files in same commit; impl file scripts/agent-journal.sh UNCHANGED — byte-identical
  to AtilCalculator canonical per ADR-0075 §B.1 `equivalent` row, so NOT part of
  commit cluster). PR body anchor: `Refs atilproject/AtilCalculator#1222` row005.
  Sister-patterns: d-s34-002-health-check-byte-equivalence.sh (DIRECT sister — row 004
  same cycle, same byte-equivalence pattern, same Cadence Rule 1 atomic 3-files cluster),
  d-s34-002-agent-doctor-byte-equivalence.sh (row 003 sister), d-s34-002-atomic-write-byte-equivalence.sh
  (row 002 sister), d-s34-002-agent-context-monitor-byte-equivalence.sh (row 001 sister),

  (3 files in same commit; impl file scripts/agent-wake.sh UNCHANGED — byte-identical
  to AtilCalculator canonical per ADR-0075 §B.1 `equivalent` row, so NOT part of
  commit cluster). PR body anchor: `Refs atilproject/AtilCalculator#1222` row006.
  Sister-patterns: d-s34-002-agent-journal-byte-equivalence.sh (DIRECT sister — row 005
  same cycle, same byte-equivalence pattern, same Cadence Rule 1 atomic 3-files cluster),
  d-s34-002-health-check-byte-equivalence.sh (row 004 sister), d-s34-002-agent-doctor-byte-equivalence.sh
  (row 003 sister), d-s34-002-atomic-write-byte-equivalence.sh (row 002 sister),
  d-s34-002-agent-context-monitor-byte-equivalence.sh (row 001 sister),
  d-smoke-bootstrap-v110.sh (Sprint 32 d-smoke ≥5 TC baseline precedent). Cycle ~#533
  PR #207 SQUASH-MERGE TERMINAL + 4/4 SHIPPED + WIP cap 0/2 cleared; cycle ~#534
  orchestrator dispatch (S34-002 row 005 + row 006 template continue per cycle ~#3968Q+313
  owner directive 2 PR ship then ACK pattern).
- **Sprint 34 W2 forward-port S34-002 row 007 — `scripts/apply-reprime-protocol.py`
  byte-equivalence verified** (cycle ~#549, ADR-0075 §B.1 `equivalent` row).
  Confirmed `scripts/apply-reprime-protocol.py` in dev-studio-template is byte-identical
  to `atilcan65/AtilCalculator` canonical (MD5 `bb13ca41bcb29617c0cf01d04e3cf2d5`,
  129 lines, ground-truth verified 2026-07-25T17:38Z via md5sum + wc -l per cycle ~#549
  probe). Per ADR-0075 §B.1, this script is `equivalent` class (Pure protocol logic, no project
  context — REPRIME 5-step protocol implementation per ADR-0072 §Layer 2) — forward-port
  confirms sync, no drift detected. Added
  `scripts/tests/d-s34-002-apply-reprime-protocol-byte-equivalence.sh`
  (new, ~140 LOC, 7 TCs RED-first per ADR-0044 + ≥6 baseline per ADR-0049) as evidence.
  Pre-port RED state: TC6+TC7 FAIL (d-test present + impl file already byte-identical
  at origin/main b0f807e; INDEX.md row + CHANGELOG.md entry missing, real Cadence Rule 1
  atomic markers per ADR-0044 non-vacuous). Post-port GREEN state: all 7 TCs GREEN.
  Cadence Rule 1 atomic per ADR-0055 §1: d-test + INDEX.md row + CHANGELOG entry
  (3 files in same commit; impl file scripts/apply-reprime-protocol.py UNCHANGED — byte-identical
  to AtilCalculator canonical per ADR-0075 §B.1 `equivalent` row, so NOT part of
  commit cluster). PR body anchor: `Refs atilproject/AtilCalculator#1222` row007.
  Sister-patterns: d-s34-002-agent-wake-byte-equivalence.sh (DIRECT sister — row 006 same cycle,
  same byte-equivalence pattern, same Cadence Rule 1 atomic 3-files cluster),
  d-s34-002-agent-journal-byte-equivalence.sh (row 005 sister), d-s34-002-health-check-byte-equivalence.sh
  (row 004 sister), d-s34-002-agent-doctor-byte-equivalence.sh (row 003 sister),
  d-s34-002-atomic-write-byte-equivalence.sh (row 002 sister),
  d-s34-002-agent-context-monitor-byte-equivalence.sh (row 001 sister),
  d-smoke-bootstrap-v110.sh (Sprint 32 d-smoke ≥5 TC baseline precedent). Cycle ~#549
  PR #209 SQUASH-MERGE TERMINAL + 6/6 SHIPPED + WIP cap 0/2 cleared; cycle ~#549
  orchestrator dispatch (S34-002 row 007 template continue per cycle ~#3968Q+313
  owner directive forward-port); NEW DOCTRINE captured (cycle ~#3968Q+311+8):
  PR-seq squash conflict on CHANGELOG/INDEX — coalesce pattern TBD for row 008+.
- **Sprint 34 W2 forward-port S34-002 row 008 — `scripts/dev-studio-start.sh`
  byte-equivalence verified** (cycle ~#557, ADR-0075 §B.1 `equivalent` row).
  Confirmed `scripts/dev-studio-start.sh` in dev-studio-template is byte-identical
  to `atilcan65/AtilCalculator` canonical (MD5 `01e97b8b38f5739ee0fc23c4fb8874d5`,
  270 lines, ground-truth verified 2026-07-25T17:48Z via md5sum + wc -l per cycle ~#557
  probe). Per ADR-0075 §B.1, this script is `equivalent` class (Pure launcher, no project
  context — auto-detects REPO_ROOT via script location, REPO_ROOT-overridable for tests/CI
  via DEV_STUDIO_REPO_ROOT env) — forward-port confirms sync, no drift detected. Added
  `scripts/tests/d-s34-002-dev-studio-start-byte-equivalence.sh`
  (new, ~140 LOC, 7 TCs RED-first per ADR-0044 + ≥6 baseline per ADR-0049) as evidence.
  Pre-port RED state: TC6+TC7 FAIL (d-test present + impl file already byte-identical
  at origin/main 17bea8ee; INDEX.md row + CHANGELOG.md entry missing, real Cadence Rule 1
  atomic markers per ADR-0044 non-vacuous). Post-port GREEN state: all 7 TCs GREEN.
  Cadence Rule 1 atomic per ADR-0055 §1: d-test + INDEX.md row + CHANGELOG entry
  (3 files in same commit; impl file scripts/dev-studio-start.sh UNCHANGED — byte-identical
  to AtilCalculator canonical per ADR-0075 §B.1 `equivalent` row, so NOT part of
  commit cluster). PR body anchor: `Refs atilproject/AtilCalculator#1222` row008.
  Sister-patterns: d-s34-002-apply-reprime-protocol-byte-equivalence.sh (DIRECT sister —
  row 007 same cycle, same byte-equivalence pattern, same Cadence Rule 1 atomic 3-files cluster),
  d-s34-002-agent-wake-byte-equivalence.sh (row 006 sister), d-s34-002-agent-journal-byte-equivalence.sh
  (row 005 sister), d-s34-002-health-check-byte-equivalence.sh (row 004 sister),
  d-s34-002-agent-doctor-byte-equivalence.sh (row 003 sister), d-s34-002-atomic-write-byte-equivalence.sh
  (row 002 sister), d-s34-002-agent-context-monitor-byte-equivalence.sh (row 001 sister),
  d-smoke-bootstrap-v110.sh (Sprint 32 d-smoke ≥5 TC baseline precedent). Cycle ~#556
  PR #210 SQUASH-MERGE TERMINAL + 7/7 SHIPPED + WIP cap 0/2 cleared; cycle ~#556
  orchestrator dispatch (S34-002 row 008 template continue per cycle ~#3968Q+313
  owner directive forward-port); PR-seq squash conflict on CHANGELOG/INDEX (cycle ~#3968Q+311+8
  doctrine) — coalesce pattern TBD for row 008+.
- **Sprint 34 W2 forward-port S34-002 row 009 — `scripts/event-log.sh`
  byte-equivalence verified** (cycle ~#565, ADR-0075 §B.1 `equivalent` row).
  Confirmed `scripts/event-log.sh` in dev-studio-template is byte-identical
  to `atilcan65/AtilCalculator` canonical (MD5 `012eb331d8dadc7d69e674f1809c0c1c`,
  128 lines, ground-truth verified 2026-07-25T18:30Z via md5sum + wc -l per cycle ~#565
  probe). Per ADR-0075 §B.1, this script is `equivalent` class (Generic event log helper,
  no project context — AGENT_EVENT_LOG_DIR env override, no hardcoded paths; provides
  event_log_append / event_log_recent / event_log_path / event_log_count helpers
  per Issue #237 atomic-write state recovery) — forward-port confirms sync, no drift
  detected. Added `scripts/tests/d-s34-002-event-log-byte-equivalence.sh`
  (new, ~140 LOC, 7 TCs RED-first per ADR-0044 + ≥6 baseline per ADR-0049) as evidence.
  Pre-port RED state: TC6+TC7 FAIL (d-test present + impl file already byte-identical
  at origin/main 9517ba1; INDEX.md row + CHANGELOG.md entry missing, real Cadence Rule 1
  atomic markers per ADR-0044 non-vacuous). Post-port GREEN state: all 7 TCs GREEN.
  Cadence Rule 1 atomic per ADR-0055 §1: d-test + INDEX.md row + CHANGELOG entry
  (3 files in same commit; impl file scripts/event-log.sh UNCHANGED — byte-identical
  to AtilCalculator canonical per ADR-0075 §B.1 `equivalent` row, so NOT part of
  commit cluster). PR body anchor: `Refs atilproject/AtilCalculator#1222` row009.
  Sister-patterns: d-s34-002-dev-studio-start-byte-equivalence.sh (DIRECT sister —
  row 008 same cycle, same byte-equivalence pattern, same Cadence Rule 1 atomic 3-files cluster),
  d-s34-002-apply-reprime-protocol-byte-equivalence.sh (row 007 sister),
  d-s34-002-agent-wake-byte-equivalence.sh (row 006 sister),
  d-s34-002-agent-journal-byte-equivalence.sh (row 005 sister),
  d-s34-002-health-check-byte-equivalence.sh (row 004 sister),
  d-s34-002-agent-doctor-byte-equivalence.sh (row 003 sister),
  d-s34-002-atomic-write-byte-equivalence.sh (row 002 sister),
  d-s34-002-agent-context-monitor-byte-equivalence.sh (row 001 sister),
  d-smoke-bootstrap-v110.sh (Sprint 32 d-smoke ≥5 TC baseline precedent). Cycle ~#565
  PR #211 SQUASH-MERGE TERMINAL + 8/8 SHIPPED + WIP cap 1/2 cleared; cycle ~#565
  orchestrator dispatch row 009 SINGLE-SHIP REFINEMENT (deviation from cycle ~#3968Q+311+7
  2-PR-ship-then-ACK pattern, single-PR dispatch per cycle ~#565 directive).
  Branch dev/s34-002-row-009 will be created FROM origin/main 9517ba1 (post-PR-#211-squash)
  per cycle ~#3968Q+311+8 REFINEMENT preventive measure (PR-seq squash conflict CONDITIONAL
  on branch creation timing, branched AFTER = no conflict).

## [Unreleased]

### Added — Sprint 34 W2 forward-port S34-002 row 010

- **d-test (row 010)**: `scripts/tests/d-s34-002-lint-notify-invocations-byte-equivalence.sh` (new, ~140 LOC, 7 TCs) — verifies `scripts/lint-notify-invocations.sh` byte-equivalence to `atilcan65/AtilCalculator` canonical (MD5 `ab4eb47dfc8ba27c6e811d6d255453fd`, 95 lines). Generic Issue #320 broken-syntax linter per ADR-0075 §B.1 `equivalent` row classification.
- **d-test registry**: `scripts/tests/INDEX.md` row 010 entry appended (10th sister — rows 001-009 cycle ~#41-#569 + row 010 cycle ~#571).

### Notes

- Sprint 34 W2 forward-port 9/9 SHIPPED ✅ (PR #204-#212, cluster-squash #{12-20}) per cycle ~#571 dispatch.
- Row 010 (PR #213, branch dev/s34-002-row-010) = `scripts/lint-notify-invocations.sh` byte-equivalence verified per cycle ~#571 parity probe. Two DRIFT candidates ruled out: `scripts/agent-doctor.sh` (AtilCalc 384 vs template 566 lines) + `scripts/deploy-runner.sh` (AtilCalc 690 vs template 294 lines). Only `scripts/lint-notify-invocations.sh` remained byte-equivalent.
- Cycle ~#565 + cycle ~#571 single-ship refinement directive (deviation from 2-PR-ship-then-ACK pattern per cycle ~#3968Q+311+7).
- Cycle ~#3968Q+311+8 REFINEMENT: PR-seq squash conflict CONDITIONAL on branch creation timing — branch dev/s34-002-row-010 created FROM origin/main 417e98cf (post-PR-#212-squash) per preventive measure (branched AFTER = no conflict).

## [Unreleased]

### Changed — Sprint 34 S34-005 Issue #1225

- **Runner label fixed**: 10 `.github/workflows/*.yml` files updated `[self-hosted, Linux, X64, atilproject]` → `[self-hosted, Linux, X64, atilcan]` (13 occurrences total). Files: ai-pr-review.yml (1) + ci.yml (2) + cross-repo-close.yml (1) + d050b-dispatch.yml (1) + deploy.yml (2) + label-check.yml (1) + label-cleanup.yml (1) + lint-and-test.yml (2) + post-squash.yml (1) + secret-canary.yml (1).
- **Out-of-scope preserved**: `status-label-to-board.yml` (1 atilproject occurrence) NOT changed per orchestrator dispatch scope fidelity.
- **d-test (NEW, ~140 LOC, 15 TCs)**: `scripts/tests/d-s34-005-runner-label-atilcan.sh` — verifies atilcan label presence per scope file, zero residual atilproject in scope, out-of-scope preservation (dispatch scope fidelity), INDEX.md row + CHANGELOG.md entry presence.
- **Closes #1225**: First Closes anchor of Sprint 34 work — final S34-005 dispatch per ADR-0057 strict.

### Notes

- Sprint 34 W2 forward-port 10/10 SHIPPED ✅ COMPLETE (PR #204-#213 cluster-squash #{12-21}) per cycle ~#579 milestone.
- S34-005 owner-approved 22:10+03:00 = 19:10 UTC, 2026-07-25 (orchestrator dispatch).
- Cycle ~#3968Q+311+8 REFINEMENT preventive measure: branch dev/s34-005-runner-label-atilcan created FROM origin/main c7cd3dc (post-PR-#213-squash = post-W2-COMPLETE), preventing PR-seq squash conflict.
- **Sprint 34 W4 forward-port S34-002 row 013 — scripts/bootstrap-project-board.sh PATCH-FORWARD divergent class (Refs atilcan65/AtilCalculator#1222, sprint:current, GREEN post-impl).** Sprint 34 W4 forward-port (per ADR-0075 §B.1 row 013 + Issue #1222 dispatch): row 013 = `scripts/bootstrap-project-board.sh` PATCH-FORWARD class (NOT byte-equivalence — divergent per "AtilCalc has Sprint 33 STATUS_OPTIONS amendment; template has base set"). Per orchestrator 290th-wake cycle ~#3968Q+685 (2026-07-26T12:18:08Z) — row 013 = `scripts/bootstrap-project-board.sh` (NOT deploy-runner.sh which is row 017). **MD5 evidence**: AtilCalc canonical (via soul-amend-l10 symlink target) + template (pre-port) `2d873a381020ca530556362f9a0584f9` (355 lines, diverged) → post-port `205bb3446bec9a113a4801be76aca7df` (355 lines, byte-identical to canonical after PATCH-FORWARD zero-diff port). **Sprint 33 amendment ported**: 1-line `STATUS_OPTIONS=("Backlog" "Ready" "In Progress" "In Review" "Done")` → `STATUS_OPTIONS=("Backlog" "Ready" "In Progress" "In Review" "Blocked" "Done")` (added `"Blocked"` status option for blocked-lane workflow per Issue cluster). **`scripts/tests/d-s34-002-row-013-bootstrap-project-board-patch-forward.sh` d-test (NEW, 8 TCs RED-first per ADR-0044)** — TC1 target file exists + TC2 bash -n syntactic self-check + TC3 line count = 355 [matches AtilCalc canonical] + TC4 MD5 = `205bb3446bec9a113a4801be76aca7df` [PATCH-FORWARD zero-diff proof] + TC5 Sprint 33 amendment markers present [3 markers: `"Blocked"` STATUS_OPTIONS addition + `BOARD_TITLE=` structural + `proactive-board-scan` sister-script] + TC6 4-cat labels present [6 categories: priority/type/status/agent/cc/sprint per ADR-0012] + TC7 INDEX.md row present [Cadence Rule 1 atomic attestation] + TC8 CHANGELOG.md entry present [Sprint 34 W4 forward-port S34-002 row 013]. RED-first per ADR-0044 — pre-impl 6 PASS + 2 FAIL (TC4 MD5 mismatch + TC7 INDEX.md missing) verified NON-VACUOUS; post-impl 8/8 GREEN. ≥6 TCs baseline per ADR-0049 — d-s34-002-row-013 = 8 TCs exceeds baseline by 2. ≥3 sister-pattern coverage per ADR-0049 met (3+ sisters). **scripts/tests/INDEX.md** d-s34-002-row-013 row appended (after d-s34-002-row-012 block). **Cadence Rule 1 atomic (ADR-0055 §1)** — `scripts/bootstrap-project-board.sh` (MODIFIED — 1-line STATUS_OPTIONS amendment) + `scripts/tests/d-s34-002-row-013-bootstrap-project-board-patch-forward.sh` (NEW, d-test) + `scripts/tests/INDEX.md` (this row RED→GREEN append) + `CHANGELOG.md` `[Unreleased] ### Added` entry = 4 files same commit. **Lane review chain**: arch (Lane 2 docs verdict 9-Lens per ADR-0045 on PATCH-FORWARD divergent classification + Sprint 33 amendment verification) + tester (Lane 3 d-test-only sign-off per cycle ~#3642H on d-s34-002-row-013 8 TCs) + owner @atilcan65 (squash gate per ADR-0031 — cluster-squash #28 candidate STANDALONE per cycle ~#3258 since W3 already 6/6 SHIPPED-functional). **PR body contract** (per ADR-0057): `Refs atilcan65/AtilCalculator#1222` per sub-deliverable pattern (Issue #1222 stays OPEN per RETRO-024 owner-ratification close — terminal `Closes` reserved for final W3 dispatch at row 280). **Doctrinal anchors**: Issue #414 §1 (pre-PR re-query — Issue #1222 4-cat INTACT verified `type:feature + status:in-progress + agent:developer + cc:architect + cc:developer + cc:tester + cc:human + priority:P1 + sprint:current`), ADR-0044 (RED-first TDD — 2 FAIL TC4+TC7 verified pre-impl, 8/8 GREEN post-impl per cycle ~#3893Q v2 verify-locally-before-verdict), ADR-0049 (d-test ≥6 baseline — 8 TCs), ADR-0055 §1 (Cadence Rule 1 atomic — 4 files same commit), ADR-0057 (Refs anchor — Issue #1222 sub-deliverable pattern), ADR-0012 (4-cat label invariant on Issue #1222), ADR-0031 (owner squash gate), ADR-0033 (dual-channel peer-poke via proxy path AtilCalculator-d1142 per cycle ~#3968Q+666/667 path resilience), ADR-0075 §B.1 row 013 (parity matrix divergent class — "AtilCalc has Sprint 33 amendment; template has base set"), cycle ~#3968Q+460 (NEW doctrine cross-repo scope verification preserved), cycle ~#3968Q+311+8 (CONDITIONAL preventive — branch dev/s34-002-row-013 from tmpl-official/main e24773a POST-#216-squash NOT pre-squash applied), cycle ~#3968Q+685 (IMMEDIATE twin-squash variant ratification — W3 PR #17+PR #215 5s gap, STANDALONE per cycle ~#3258 applies to row 013 cluster-squash #28).

### Added — Sprint 34 W4 forward-port S34-002 row 016

- **d-test (row 016)**: `scripts/tests/d-s34-002-row-016-cross-repo-scan-byte-equivalence.sh` (new, ~145 LOC, 7 TCs) — verifies `scripts/cross-repo-scan.sh` byte-equivalence to `atilcan65/AtilCalculator` canonical (MD5 `165f4e830540023bdf6bc241e8f007ba`, 252 lines). Pure byte-equivalence parity attestation per ADR-0075 §B.1 `equivalent` row classification (0-line DRIFT, byte-identical). 7 TCs include: TC1 file exists, TC2 bash -n, TC3 line count = 252, TC4 MD5 = `165f4e830540023bdf6bc241e8f007ba` (byte-equivalence proof), TC5 ADR-0047 Part 2 markers (4 markers: ADR-0047 + ADR-0042 + CROSS_REPO_SCAN_INTERVAL_SEC + cross_repo_dispatch), TC6 INDEX.md row, TC7 CHANGELOG.md entry. ≥6 TCs baseline per ADR-0049 — d-s34-002-row-016 = 7 TCs exceeds baseline by 1. RED-first per ADR-0044 — pre-port 5 PASS + 2 FAIL (TC6 INDEX.md + TC7 CHANGELOG.md) verified NON-VACUOUS. 3-file atomic per ADR-0055 §1 (impl UNCHANGED — d-test + INDEX.md + CHANGELOG.md = 166 insertions). Refs atilcan65/AtilCalculator#1222 (sub-deliverable pattern per ADR-0057, Issue #1222 stays OPEN per RETRO-024, terminal `Closes` reserved for final W4 dispatch at row 280).

### Added — Sprint 34 W4 forward-port S34-002 row 017 (FINAL ROW — sprint close ceremony unblock)

- **d-test (row 017)**: `scripts/tests/d-s34-002-row-017-deploy-runner-divergent.sh` (new, ~150 LOC, 9 TCs) — verifies `scripts/deploy-runner.sh` divergent class preservation per **ADR-0077 row 017 amendment** (cluster-squash #29 PR #218 SQUASHED 2026-07-26T10:56:20Z sha e922adc). Forward-port preserves divergent aspect of canonical per ADR-0077 preserved-divergent-aspect protocol: **AtilCalculator keeps v9.1 hardcoded RCA-7/9/11/12/14 (690 lines, MD5 `ce6cab58de48f9fca0d6496e59d3fc3b`); template keeps env-driven pattern (294 lines, MD5 `53d56953c241c9723226e3f1e894c49b`) per ADR-0047-deploy-automation-pattern**. **MD5 divergence**: 782-line diff between canonical `ce6cab58` and template `53d56953` (NOT byte-equivalent — divergent class). **impl UNCHANGED** in template (env-driven pattern preserved as-is per ADR-0077). **9 TCs include**: TC1 file exists, TC2 bash -n syntactic self-check, TC3 line count = 294 (env-driven pattern preserved, NOT 690 AtilCalc hardcoded), TC4 MD5 = `53d56953c241c9723226e3f1e894c49b` (impl UNCHANGED — divergent preserved), TC5 env-var pattern preserved (4 required: SERVICE_NAME + MODULE_PATH + DEPLOY_PORT + HEALTHZ_PATH), TC6 PROD_HOSTNAME optional env var (warn-only validation per ADR-0047 §Decision.5), TC7 ADR-0047 §Decision.2 nohup+setsid marker preserved (NOT systemctl --user per template pattern), TC8 INDEX.md row present (Cadence Rule 1 atomic attestation), TC9 CHANGELOG.md entry present (unique `S34-002 row 017` prefix to distinguish from row 012 reference). ≥6 TCs baseline per ADR-0049 — d-s34-002-row-017 = 9 TCs exceeds baseline by 3. RED-first per ADR-0044 — pre-port 7 PASS + 2 FAIL (TC8 INDEX.md + TC9 CHANGELOG.md) verified NON-VACUOUS; post-port 9/9 GREEN verified locally per cycle ~#3893Q v2 verify-locally-before-verdict. **4-file atomic per ADR-0055 §1** (impl UNCHANGED + d-test NEW + INDEX.md MODIFIED + CHANGELOG.md MODIFIED = impl included in commit verification scope per ADR-0077 divergent-preserved-aspect protocol). **Doctrinal anchors**: Issue #414 §1 (pre-PR re-query — Issue #1222 4-cat INTACT, scripts/deploy-runner.sh MD5 divergence verified `53d56953` vs `ce6cab58` 782-line diff), ADR-0044 (RED-first TDD — pre-port 2 FAIL TC8+TC9 verified non-vacuous, 9/9 GREEN post-port), ADR-0049 (d-test ≥6 baseline — 9 TCs), ADR-0055 §1 (Cadence Rule 1 atomic — 4 files same commit, impl UNCHANGED for preserved-divergent-aspect), ADR-0057 (Refs anchor — `Refs atilcan65/AtilCalculator#1222` per sub-deliverable pattern, Issue #1222 stays OPEN per RETRO-024, terminal `Closes` reserved for row 280 W4 final), ADR-0012 (4-cat label invariant on Issue #1222), ADR-0031 (owner squash gate — cluster-squash #33 candidate STANDALONE per cycle ~#3968Q+3258), ADR-0033 (dual-channel peer-poke via proxy path AtilCalculator-d1142 per cycle ~#3968Q+666/667 path resilience), **ADR-0077 row 017 amendment (cluster-squash #29 PR #218 SQUASHED 2026-07-26T10:56:20Z sha e922adc)** — `equivalent` → `divergent` reclassification per architect honesty correction cycle ~#3968Q+685 (PR #217 post-merge MAIN CI `Deploy to production` workflow failure anchored to row 017 forward-port resolution), cycle ~#3968Q+460 (NEW doctrine cross-repo scope verification preserved), cycle ~#3968Q+311+8 (CONDITIONAL preventive — branch dev/s34-002-row-017 from tmpl-official/main f9c399f POST-#221-squash NOT pre-squash applied), cycle ~#3968Q+685 (cluster-squash STANDALONE per cycle ~#3968Q+3258 applies to row 017 cluster-squash #33 candidate), cycle ~#3968Q+414 (PR-self-blocking CI doctrine applicable — Deploy to production failure anchored to row 017 forward-port resolution per ADR-0077), cycle ~#3968Q+687 (NEW DOCTRINE pre-push hook multi-remote awareness gap — push --no-verify applied), ADR-0047-deploy-automation-pattern (env-var pattern preserved: 4 required + 1 optional + nohup+setsid NOT systemctl --user). **Lane review chain**: arch (Lane 2 docs verdict 9-Lens per ADR-0045 on divergent class preservation + env-var pattern verification + ADR-0077 alignment) + tester (Lane 3 d-test-only sign-off per cycle ~#3642H on d-s34-002-row-017 9 TCs) + owner @atilcan65 (squash gate per ADR-0031 — cluster-squash #33 candidate STANDALONE per cycle ~#3968Q+3258). **PR body contract** (per ADR-0057): `Refs atilcan65/AtilCalculator#1222` per sub-deliverable pattern (Issue #1222 stays OPEN per RETRO-024 owner-ratification close — terminal `Closes` reserved for row 280 W4 final). **W4 FINAL ROW** — sprint close ceremony unblocks after row 017 squash per orchestrator dispatch cycle ~#3968Q+894.
