# Changelog

All notable changes to this project are recorded here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

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
