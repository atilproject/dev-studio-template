# New Project Steps

> Manual follow-ups after [`new-project.sh`](https://github.com/atilproject/dev-studio-launcher) creates the repo. Sister-pattern to the launcher README — terse, command-anchored, copy-pasteable.
>
> **Verified by**: Sprint 34 S34-004 disposable bootstrap test infra (PR #224, sha `ffc7403`, 2026-07-26T18:16:34Z) — workflow `.github/workflows/disposable-bootstrap-test.yml` runs the bootstrap path end-to-end against disposable public + private repos, captures evidence (URL, commit SHA, workflow run, runner label match, rendered tree, log), tears down on completion. See [§5 Verified by — S34-004 evidence anchors](#5-verified-by--s34-004-evidence-anchors) below.

A new multi-agent dev studio project is **not** done when the script exits zero. The launcher covers A1 + B1 + C2 (repo create, clone, init + labels, rendered push) and intentionally stops there. The four phases below pick up exactly where the launcher leaves off.

## 1. Pre-bootstrap — prerequisites

Before running `new-project.sh`, confirm:

| Tool | Why | Install |
|---|---|---|
| `gh` CLI | Authenticated GitHub operations | `sudo apt install gh` + `gh auth login` |
| `git` | Clone + commit + push | `sudo apt install git` |
| `jq` | Used by `dev-studio-init.sh` + label scripts | `sudo apt install jq` |
| `tmux` | For the 5-pane agent runtime | `sudo apt install tmux` |
| `python3.11+` | Required by `dev-studio-init.sh` + d-test framework | `sudo apt install python3.11` |

And:

- `git config --global user.name` + `user.email` must be set
- `gh auth status` reports `Logged in to github.com`
- For private repos (ADR-0016): a GitHub spending limit is configured (Actions minutes)

If `gh` is not authed, `new-project.sh` exits with `[fail] gh auth status`. Fix that first.

## 2. Bootstrap — `new-project.sh <name>`

```bash
# One-time launcher setup (skip if already symlinked)
git clone https://github.com/atilproject/dev-studio-launcher.git ~/dev-studio-launcher
mkdir -p ~/bin
ln -sf ~/dev-studio-launcher/new-project.sh ~/bin/new-project.sh
export PATH="$HOME/bin:$PATH"

# Create the project (lands in ~/projects/<name> by default)
new-project.sh <project-name>

# Examples
new-project.sh AtilCalculator
new-project.sh book-tracker --dir /tmp
new-project.sh stock-watcher --owner my-org
new-project.sh my-side-project --private   # requires spending limit
```

What `new-project.sh` does — see the [launcher README](https://github.com/atilproject/dev-studio-launcher/blob/main/README.md) for full details:

1. Preflight checks (`gh` auth, `git` config, `jq` present)
2. Create repo from [`dev-studio-template`](https://github.com/atilproject/dev-studio-template) (default public — ADR-0016)
3. Clone locally
4. Run `dev-studio-init.sh` (render `.tmpl` → final files)
5. Run `bootstrap-labels.sh` (seed `type:*`, `status:*`, `agent:*`, `cc:*` — ADR-0012)
6. Commit + push the rendered changes to `main`

What it **does not** do (kept manual by design): start tmux, open Vision Intake, run e2e smoke test.

## 3. Post-bootstrap — verify + render

After `new-project.sh` exits zero:

```bash
cd ~/projects/<project-name>     # or wherever --dir pointed

# 1. Verify rendered template landed cleanly
git log --oneline -5              # should show init + bootstrap commits
gh label list --limit 5 | head    # should show agent:*, cc:*, type:*, status:*

# 2. (Re-)render templates if you edited any .tmpl source
bash scripts/dev-studio-init.sh
git diff                          # preview rendered changes
git add -A && git commit -m "chore(render): re-render after edit"

# 3. Verify CI is green on main
gh run list --branch main --limit 1
gh pr list --state all
```

`dev-studio-init.sh` is idempotent — re-running it is safe. The script reads `.claude/CLAUDE.md.tmpl` and `README.md.tmpl`, resolves the 6 placeholders (per ADR-0050), and writes the rendered files. **Edit the `.tmpl` source, never the rendered file** — manual edits to the rendered file are lost on the next re-render.

The 4-cat label invariant (ADR-0012) is enforced by `.github/workflows/label-check.yml`. Any new issue or PR missing a `type:*`, `status:*`, `agent:*`, or `cc:*` label fails CI and gets a fix-it comment.

## 4. First-week — Vision Intake, agents, first standup

### Day 1 — open the Vision Intake

The Vision Intake is a single high-leverage issue that gives the Product Manager agent the inputs it needs to write your project's `docs/product/vision.md` and seed the backlog.

```bash
gh issue create --title "Vision Intake — <project-name>" --body-file - <<'EOF'
## Vision (1 paragraph)
<what the project is, who it's for, why now>

## Success in 90 days
<3 concrete outcomes>

## Out of scope (explicit non-goals)
<bulleted list>

## Constraints
<tech, time, budget, regulatory>

## Stakeholders
<who decides what, who builds, who uses>
EOF

# Then cc the PM agent (label-driven — does NOT require opening a chat thread)
gh issue edit <issue-number> \
  --add-label "type:vision" --add-label "status:backlog" \
  --add-label "agent:product-manager" --add-label "cc:product-manager"
```

The PM agent will pick this up on its next `agent-watch.sh` poll (≤60s) and respond with the rendered vision doc + first backlog slice.

### Day 1 — start the agent runtime

```bash
# From the project root
bash scripts/dev-studio-start.sh
```

This opens a tmux session named after the project with 5 panes (one per agent: Orchestrator, Product Manager, Architect, Developer, Tester). Each pane auto-runs `agent-watch.sh <role>` and stays quiet until a wake event lands. `Ctrl-b d` detaches; `tmux attach -t <project>` re-enters.

### Day 2 — first standup

The orchestrator auto-posts a standup issue at 09:00 Europe/Istanbul every working day (it's a *schedule*, not a work-hours gate — agents operate 24/7). To trigger an ad-hoc standup:

```bash
gh issue create --title "[Sprint 1] Daily Standup" --body "Status?" \
  --label "type:chore" --label "status:ready" \
  --label "agent:orchestrator" --label "cc:product-manager" \
  --label "cc:architect" --label "cc:developer" --label "cc:tester"
```

Each agent responds in-thread with: *yesterday / today / blockers*. The orchestrator synthesizes a summary comment.

### Day 3–5 — first sprint

The PM writes the Sprint 1 plan (`docs/sprints/sprint-01/plan.md`) after the vision lands. Sprint cadence: 2 weeks (10 working days). The orchestrator opens a `[Sprint 1] Kickoff` issue for human approval on Monday of week 1.

## 5. Verified by — S34-004 evidence anchors

> **Story**: S34-006 (Issue #1226 — verified canonical doc derived from executed bootstrap, audit Q6 acceptance criterion)
> **Evidence source**: [PR #224 (dev-studio-template)](https://github.com/atilproject/dev-studio-template/pull/224) SQUASH-MERGED 2026-07-26T18:16:34Z sha `ffc7403c518e7e0f44c72dcad7a06615a5a198e5`
> **Why this section exists**: Audit Q6 ("verified detailed document") explicitly deferred this verification pending E2E evidence (per PR #1218 SQUASH-MERGED audit). S34-004 produced that evidence; S34-006 cites it.

This doc's commands (Phases 1–4 above) are verified by the **disposable bootstrap test infra** — a workflow that runs the exact bootstrap path against disposable GitHub repos and captures authoritative evidence per command:

### Evidence anchor — workflow file

| Artifact | Location | SHA |
|---|---|---|
| Workflow | [`.github/workflows/disposable-bootstrap-test.yml`](https://github.com/atilproject/dev-studio-template/blob/main/.github/workflows/disposable-bootstrap-test.yml) | `ffc7403` (PR #224 merge commit) |
| d-test | [`scripts/tests/d-s34-004-disposable-bootstrap-test.sh`](https://github.com/atilproject/dev-studio-template/blob/main/scripts/tests/d-s34-004-disposable-bootstrap-test.sh) | 10/10 GREEN (per PR #224 d-test execution) |
| INDEX.md row | [`scripts/tests/INDEX.md`](https://github.com/atilproject/dev-studio-template/blob/main/scripts/tests/INDEX.md) | entry registered same commit (Cadence Rule 1 atomic per ADR-0055 §1) |
| CHANGELOG.md | [`CHANGELOG.md`](https://github.com/atilproject/dev-studio-template/blob/main/CHANGELOG.md) | "Sprint 34 S34-004 disposable-bootstrap-test" entry |

### Evidence anchor — runner label match (per S29-001 AC3)

The disposable bootstrap workflow runs on the **canonical 4-tuple runner label** that downstream projects inherit:

```yaml
runs-on: [self-hosted, Linux, X64, atilcan]
```

This is the same label set Phase 1 prerequisites implicitly assume — any new project cloned from this template is expected to provision a runner with these labels. AC3 met (verified per PR #224 NIT-1 BLOCKER fix + cycle ~#3968Q+847 inline d-test amender TC10).

### Evidence anchor — bootstrap commands covered

The workflow exercises these commands from this doc and captures evidence per command:

| Doc command (Phases 1–4) | Workflow step | Evidence captured |
|---|---|---|
| Phase 1: `gh auth status` | (preflight, not in workflow) | operator responsibility |
| Phase 2: `new-project.sh <name>` | `Create disposable public repo` step | `REPO_NAME` + URL → `$GITHUB_STEP_SUMMARY` |
| Phase 2: `dev-studio-init.sh` (render) | `Bootstrap init + render + labels` step | `git rev-parse HEAD > /tmp/evidence-commit-sha` |
| Phase 2: `bootstrap-labels.sh` (label seed) | same step | label list output → `$GITHUB_STEP_SUMMARY` |
| Phase 3: `git log --oneline -5` | bootstrap commit SHA | `/tmp/evidence-commit-sha` |
| Phase 3: `gh label list` | labels seeded | `$GITHUB_STEP_SUMMARY` |
| Phase 3: `gh run list --branch main` | (not in disposable test — runs on the new project's main) | operator responsibility |
| Phase 4: `bash scripts/dev-studio-start.sh` | (not in disposable test — agent runtime is per-project) | operator responsibility |

### Evidence anchor — AC2 evidence-artifact correspondence

Per Issue #1226 AC2 ("each command in the doc has a corresponding evidence artifact from S34-004 execution"), the table above maps each Phase 1–4 command to its S34-004 evidence source. Operator-side commands (auth check, tmux start, Vision Intake creation) are **out of test scope** — they require operator decisions and are not part of the deterministic bootstrap path.

### Evidence anchor — reproducibility

The workflow is **re-runnable** via GitHub Actions `workflow_dispatch` (manual owner trigger). Each run creates a fresh disposable repo (unique timestamp suffix), runs the bootstrap path, captures evidence, tears down. To reproduce locally:

```bash
# From a clone of dev-studio-template at PR #224 commit
gh workflow run disposable-bootstrap-test.yml \
  --repo atilproject/dev-studio-template \
  --ref main
# Then check the Actions run summary for evidence artifacts.
```

Private-repo path is gated on `run_private == 'true'` (owner-only per AC2 — requires `OWNER_DISPOSABLE_PRIVATE_TOKEN` secret). Public path runs by default.

### Sister-pattern — Sprint 32 S32-017 authoring

This verified version supersedes the **unverified** v0.5.0 draft shipped at S34-003 (Issue #1223). Original scaffolding: 4 phases + See also + What to NOT do. S34-006 enrichment: §5 Verified by evidence anchors + cross-references to PR #224 evidence artifacts. Sister-pattern to Sprint 32 S32-017 (new-project-steps.md original authoring at launcher v0.5.0).

## See also

- [atilproject/dev-studio-launcher](https://github.com/atilproject/dev-studio-launcher) — the bootstrap script + visibility defaults
- [atilproject/dev-studio-template CLAUDE.md.tmpl](https://github.com/atilproject/dev-studio-template/blob/main/CLAUDE.md.tmpl) — full doctrine (rendered to `CLAUDE.md` on init)
- [ADR-0001](../decisions/ADR-0001-template-architecture.md) — single-repo template doctrine
- [ADR-0012](../decisions/ADR-0012-required-label-set.md) — required label set on every issue/PR
- [ADR-0013](../decisions/ADR-0013-status-label-to-board-sync.md) — `status:*` → Projects v2 board sync
- [ADR-0016](../decisions/ADR-0016-public-by-default.md) — why default is public
- [ADR-0078](../decisions/ADR-0078-deploy-failure-root-cause.md) — Deploy FAILURE root cause analysis + workflow fix path (cluster-lag-detector FAILURE permissions gap, addressed by PR #223)
- [Issue #1226](https://github.com/atilcan65/AtilCalculator/issues/1226) — S34-006 verified doc story (PM-owned, status:done after this PR merges)

## What to NOT do

- ❌ Edit rendered files directly (`.claude/CLAUDE.md`, `README.md`) — edit the `.tmpl` source instead.
- ❌ Push to `main` directly — branch + draft PR + tester signoff + human squash-merge (ADR-0031).
- ❌ Open issues without all 4 label categories — CI fails on every event.
- ❌ Open the Vision Intake without `cc:product-manager` — the PM agent never wakes.
- ❌ Merge your own PRs — owner-only merge gate is non-negotiable.