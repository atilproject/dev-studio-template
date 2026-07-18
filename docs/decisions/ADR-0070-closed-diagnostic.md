# ADR-0070 — Closed-Event 4-cat Invariant Diagnostic for `label-check.yml`

**Status:** Proposed
**Date:** 2026-07-09
**Deciders:** @architect (doctrine/spec + PR #938 IMPL proposer), @developer (impl reviewer per file ownership), @tester (d068-td067-combined.sh 7/7 PASS per ADR-0044), @orchestrator (sprint tracking), @atilcan65 (workflow YAML owner squash-gate per ADR-0031 + file ownership matrix)
**Closes:** Issue #934 (TD-067b Part 2 IMPL tracking), Issue #927 (TD-067b Part 2 spec parent — fully closed when PR #938 merges)
**Supersedes:** —
**Related:** [ADR-0012](./ADR-0012-required-label-set.md) (4-cat invariant being protected), [ADR-0015](./ADR-0015-atomic-agent-handoff.md), [ADR-0027](./ADR-0027-deploy-automation.md) §Threat model (SHA-pin). Sister-pattern ADRs in this repo referenced as plain prose (cross-repo slug drift mitigation per Issue #414 §Dispatch Discipline + RETRO-005 #26 — these references are aspirational/peer-pattern, not strictly load-bearing for this ADR's correctness): ADR-0043 (8-lens architect review checklist), ADR-0044 (verdict-by SLA scope, RED exclusion doctrine), ADR-0045 (auto-generated file refs, lens (j)), ADR-0049 (behavioral workflow test framework, d050b), ADR-0055 (d-test ID uniqueness + sub-pattern matrix). Canonical design contract: `docs/designs/TD-067b-design.md` (PR #928 squash @ c24e28e).

---

## Context

**TD-067 Part 1 fix** (PR #926 squash @ fb18c25, 2026-07-09T11:34:03Z) surgically narrowed `TRANSIENT_REGEX` in `.github/workflows/label-cleanup.yml` from `^(cc:|agent:|needs-)|^agent-stall$` to `^(needs-)|^agent-stall$`. This restores the 4-cat invariant (ADR-0012) and the `pr_labeled` wake audit trail (ADR-0009 §10.3) on closed PRs — `agent:*` + `cc:*` labels now survive squash-merge instead of being silently stripped.

**The problem this ADR solves**: the Part 1 fix is **silent**. If `label-cleanup.yml` ever regresses (e.g., a future contributor widens `TRANSIENT_REGEX`, or a new closure path bypasses `label-cleanup.yml` entirely), the failure mode is invisible:

1. `agent:*` + `cc:*` labels get stripped on squash-merge
2. 4-cat invariant (ADR-0012) violated on closed PRs
3. `pr_labeled` wake (ADR-0009 §10.3) stops firing because the labels carrying the wake authority are gone
4. `claim-next-ready.sh` (ADR-0038) auto-claim halts because the trigger condition references the missing labels
5. **No human sees the regression until downstream symptoms appear** — silent drop, queue freeze, agents idle without explanation, hours after the actual breakage

**LIVE INSTANCE** (the proof): 2026-07-09T11:34Z, **immediately after PR #926 merged**, the follow-up issue **#927 itself was rendered 4-cat-non-compliant**. The body referenced `agent:architect + 4 cc:*` labels (the standard cluster cascade handoff) but the actual label set was only `[status:ready]`. Likely race with the very workflow PR #926 just fixed; root cause under triage, but the **observability gap that allowed silent breakage is the design target of this ADR**.

This ADR adds a **forward-action diagnostic** — a new workflow job `closed-diagnostic` that fires on `pull_request_target: closed` (new trigger, gate `merged == true`), reads the post-cleanup label state, and posts a one-line comment if the expected post-cleanup baseline is violated. It does NOT modify `label-cleanup.yml` (per ADR-0007 + Issue #927 R1 risk: "858-line surgical modification, out of inline scope"). It does NOT alter the existing Layer 1-5 behavior. It adds a new Layer 6 — a pure read-only observer.

---

## Decision

**Adopt Layer 6 — `TD-067b closed-event 4-cat diagnostic`** as a new step in `.github/workflows/label-check.yml`.

### File change

- `.github/workflows/label-check.yml` L35 — add `closed` event to `pull_request_target.types`:
  ```yaml
  pull_request_target:
    types: [opened, reopened, labeled, unlabeled, closed]
  ```
- `.github/workflows/label-check.yml` L884 — NEW step block (~130 LoC YAML delta).

### Step semantics

- **Trigger**: step-level `if:` gate — `github.event_name == 'pull_request_target' && github.event.action == 'closed' && github.event.pull_request.merged == true`. This explicit gate (per design R3 mitigation) ensures the Layer 1 silent_skip at L75-78 does NOT apply.
- **Fresh label fetch**: `github.rest.pulls.get` (Issue #819 fix sister-pattern — webhook snapshot is frozen at fire time and can be 1-30s behind reality).
- **Baseline comparison** (per design §Data model, condensed into JS):
  - REQUIRED: `type:*` (exactly 1, from `vision|feature|bug|docs|chore|refactor|incident`) + `status:done` (exactly 1)
  - OPTIONAL (0 or 1 each): `priority:*` + `sprint:*` + `security` + `good-first-issue`
  - EXPECTED-ABSENT (stripped by design per `label-cleanup.yml`): `agent:*` + `cc:*` + `needs-*` + `agent-stall` + `verdict-by:*`
- **3 structured log paths** (ADR-0045 lens d compliance):
  - `event=triggered` — every invocation
  - `event=baseline-match` — `silent_skip` per ADR-0045 lens d (no comment posted)
  - `event=deviation-detected` — `core.warning` + bot comment posted
- **Bot comment idempotency**: marker `<!-- adr-0070-closed-diagnostic -->` (Layer 1-5 sister-pattern, reuses L108-110 comment dedup).
- **Concurrency**: inherits parent `label-check-${{...number}}` group (no new group, no race risk).
- **SHA-pinned**: `actions/github-script@f28e40c7f34bde8b3046d885e986cb6290c5673b` (matches existing Layer 1-5 usage at L54, 178, 243, 334, 455).
- **Permissions inherit** from workflow-level block (L37-39: `issues: write`, `pull-requests: write`).

### Implementation surface

The full IMPL lives in PR #938 (`arch/td-067b-part2-impl-issue-934` → `main`), which is the proposal-PR opened by architect lane per `.github/workflows/` ownership matrix (agents propose, owner squash-gates per ADR-0031).

---

## Rationale

Three alternatives were considered (full table in `docs/designs/TD-067b-design.md` §Alternatives); this ADR endorses Option A from that table:

| Alternative | Effect | Verdict |
|---|---|---|
| **A. New `closed-diagnostic` step in label-check.yml** | Surgical addition under existing `label-check` job, gated on `pull_request_target: closed + merged == true` | **CHOSEN** — reuses concurrency group, permissions, runner. Single file diff. Concurrency-safe by design. |
| B. Separate workflow file `closed-diagnostic.yml` | Total isolation, independent versioning | Rejected — new concurrency group (R2 unmitigated); doubles CI surface; review burden 2x |
| C. `workflow_run` trigger on label-cleanup.yml | Strict post-cleanup ordering | Rejected — `workflow_run` token lacks `pull-requests: write`; can only comment on issues, not PRs |
| D. Polling `/events` API from `scripts/` | Decoupled from workflow | Rejected — latency (≥60s poll), new infra component, out-of-scope |
| E. Read stale webhook payload (no `pulls.get` re-fetch) | Saves 1 API call | Rejected — known sister-bug (Issue #819 LIVE INSTANCE); false negatives on race |

The "boring tech wins" heuristic applies: extend an existing workflow file with a sibling step. No new workflow file, no new concurrency group, no new permissions block, no new SHA pin (reuses existing). Net diff: **+130 LoC YAML delta** to a single 858 → 987-line file.

---

## Consequences

### Positive

1. **Forward-action observability** — silent breakage becomes loud. Any future `label-cleanup.yml` regression fires a diagnostic comment within 30s of squash-merge, before downstream symptoms appear.
2. **Zero behavior change to existing layers** — Layer 1-5 + auto-verdict-by hook + cascade-strip remain untouched. New layer is a sibling, not a refactor.
3. **SHA-pinned, concurrency-safe, retry-safe** — All `actions/*` use full 40-char SHA per ADR-0027 + ADR-0043 §lens (h). Concurrency group reuses `label-check-${{ ...number}}` to avoid races. Idempotent bot comment via marker.
4. **d-test coverage ≥5 TCs** — `scripts/tests/d068-td067-combined.sh` (PR #932 squash @ 85b69e0) has 7 TCs; TC1 + TC2 flip RED→GREEN with this PR's IMPL.
5. **Reuses the Issue #819 fix pattern** — `pulls.get` fresh label fetch (vs. stale webhook snapshot) is the same defensive pattern used in Layer 5 (L476). Proven to work; reduces race-condition surface.
6. **Captures sprint-level hygiene drift** — any future deviation from the expected post-cleanup baseline (whether from `label-cleanup.yml` regression OR a new closure path that bypasses cleanup) is now visible.

### Negative

1. **858-line file gets +130 lines** — slight complexity increase on a file already at 858 LoC. Mitigated by surgical addition (no existing logic touched, diff is `+new code, ~0` for existing code per R1 mitigation).
2. **Diagnostic on closed PRs is post-mortem** — fires AFTER squash-merge completes. Cannot prevent the regression, only detect it. Mitigated by 30s latency (well before downstream symptoms appear).
3. **False-positive risk on edge cases** — e.g., a future contributor adds a new label prefix that wasn't in the baseline enumeration. Mitigated by `MISSING` + `UNEXPECTED` lists that surface both directions of drift.
4. **Doesn't cover open-time strip** — Issue #931 (TD-067c, P1, Sprint 25+ defer) is the sister-finding for open-time label-strip. Sister-PR will add a parallel `opened|reopened|synchronize` trigger.
5. **Adds a new persistent audit trail** — diagnostic comments accumulate on every closed-merged PR with deviation. Acceptable volume (closed-merged events are rare, ≤10/day typical).

### Out of scope (this ADR)

- ❌ Modify `label-cleanup.yml` behavior (R1: 858-line surgical scope, deferred to Sprint 25+ per Issue #927 R1).
- ❌ Diagnose `issues: closed` events (issues don't carry `agent:*`/`cc:*` post-cleanup expectation; baseline is different).
- ❌ Diagnose closed-not-merged PRs (gate `merged == true` — closed-without-merge leaves labels intact for operator review per `label-cleanup.yml` L23-25).
- ❌ Auto-fix on deviation (defer to Sprint 25+ — manual investigation preferred to avoid masking intermittent issues).
- ❌ Open-time strip diagnostic (Issue #931, TD-067c, Sprint 25+ Wave 1 P1 follow-up — separate ADR/issue cluster).
- ❌ External log sink (GitHub Actions log is the audit trail for v1; Sprint 25+ scope for `gh archive` integration).

### Follow-up tickets

1. `@architect`: sister ADR for TD-067c (open-time strip) when Issue #931 enters Sprint 25+ Wave 1 design phase.
2. `@developer`: after PR #938 merges, run `bash scripts/tests/d068-td067-combined.sh` on `main` to confirm GREEN regression-free (tester-led, but dev confirms CI integration per Cadence Rule 1 atomic).
3. `@tester`: post-merge, add 2-3 sister TCs to `d068-td067-combined.sh` covering the live marker pattern + comment body shape (sister to existing TC4 idempotency).
4. `@orchestrator`: track PR #938 squash-gate in sprint board; flag to human if review exceeds 24h SLA per ADR-0024 amendment.
5. `@atilcan65`: review PR #938 per ADR-0031 owner-override doctrine; squash-merge to `main` after tester sign-off.

---

## Future work

- **Open-time strip diagnostic** (Issue #931, TD-067c) — parallel workflow YAML addition; reuses Layer 6 sister-pattern; Sprint 25+ Wave 1 P1.
- **Auto-fix on deviation** — when deviation detected + baseline is unambiguous, attempt `addLabels` for `status:done` + remove any unexpected `agent:*`/`cc:*`. Defer to Sprint 25+ scope; manual investigation preferred in v1.
- **External log sink** — emit structured event to `gh archive` / Loki / OpenTelemetry for cross-PR drift dashboards. Sprint 25+ scope.
- **d-test extension** — add TCs for the marker pattern itself (TC8) + comment body shape (TC9) + diagnostic-deactivation on `reopened` event (TC10). Sister to existing TC4 idempotency.

---

## 9-Lens attestation (per ADR-0045)

| Lens | Application | Attestation |
|---|---|---|
| (a) Data flow | PR close → GitHub webhook → `pull_request_target: closed` → `label-check.yml` → `pulls.get` → compare baseline → comment POST. Hand-off points: GitHub → workflow (webhook), workflow → API (REST), workflow → PR thread (comment). | sequence diagram in `docs/designs/TD-067b-design.md` §Sequence diagram; PR #938 §How |
| (b) Runtime preconditions | self-hosted runner `atilproject/Linux/X64` (existing). No new deps. `GITHUB_TOKEN` (auto-issued). SHA-pinned `actions/github-script@<sha>` verified pre-PR per design R4. | grep attestation R4 (`grep -E 'uses:.*@(v[0-9]+|main\|latest)$' .github/workflows/label-check.yml` returns empty) |
| (c) Canonical entry | `pull_request_target: types: [closed]` + step-level `if: merged == true` is the ONLY entry. No side-channels. The L75-78 silent_skip is INSIDE Layer 1's `if`-less body and does NOT apply to our new step. | workflow diff + step gate (R3 mitigation) |
| (d) Silent-skip risk | Step-level `if:` gate logs `silent_skip event=closed-not-merged` when `merged == false`. Baseline-match case logs `event=baseline-match` (NOT silent — silent_skip is intentional per ADR-0045 lens d). Deviation case logs `event=deviation-detected` (warning + visible comment). No silent path. | observability §3-log-paths |
| (e) Idempotency | Bot comment idempotency via marker `<!-- adr-0070-closed-diagnostic -->` (sister-pattern to L108-110 + L851). Re-fires on every close event; comment is updated in-place. Concurrency group `label-check-${{...number}}` serializes per-PR. | workflow L108-110 + L851 pattern reuse |
| (f) Observability | 3 structured log lines (trigger / silent-skip / deviation) + 1 conditional bot comment. No metric (implicit via GitHub Actions API). | PR #938 §How §9-Lens attestation |
| (g) Security & privacy | No PII handled. Only public label names + PR number. SHA-pinned actions. Self-hosted runner. Permissions same as parent (L37-39). No external API surface beyond GitHub. | design §Security & privacy |
| (h) Workflow YAML SHA pin | All `actions/*` MUST use full 40-char SHA. Pre-PR: `grep -E 'uses:.*@(v[0-9]+\|main\|latest)$' .github/workflows/label-check.yml` returns empty. NEW invocation: `actions/github-script@f28e40c7f34bde8b3046d885e986cb6290c5673b` (matches existing L54). | grep attestation R4 + PR #938 §Verification |
| (i) Platform hard constraints | `runs-on: [self-hosted, Linux, X64, atilproject]` (existing). No raw `docker run`, no `ssh` outside `actions/*`. Permissions at workflow-level (L37-39), NOT job-level. `timeout` not set (default 360min acceptable for this short-running step). `concurrency:` reused (L45-47), no new group. | workflow L37-47 reuse + PR #938 §9-Lens attestation (i) |
| (j) Auto-gen file refs + live-state verification | No auto-gen files in scope. `label-check.yml` and `docs/decisions/INDEX.md` are hand-maintained (confirmed by `grep .gitignore` + `git log --diff-filter=A`). Live-state verification: `gh api repos/atilproject/AtilCalculator/contents/.github/workflows/label-check.yml?ref=main` returns 200 post-merge. | live-state pre-PR grep + post-PR gh api check |

---

## Sister-pattern lineage

| Cluster | PR | Status | Sister to TD-067b |
|---|---|---|---|
| TD-067 Part 1 (TRANSIENT_REGEX narrowing) | PR #926 | squash-merged @ fb18c25 (2026-07-09T11:34Z) | parent fix |
| TD-067b design (closed-diagnostic contract) | PR #928 | squash-merged @ c24e28e (2026-07-09T12:23Z) | design contract |
| TD-067b d-test (RED-first, 7 TCs) | PR #932 | squash-merged @ 85b69e0 (2026-07-09T12:46Z) | test RED-first |
| **TD-067b Part 2 IMPL** (THIS ADR + PR #938) | **PR #938** (this) | **draft, arch proposes** | **impl** |
| TD-067c open-time sister-finding | Issue #931 | P1, Sprint 25+ defer | sister-followup |

---

*End of ADR. Implementation gated on: (a) owner approval of design (✅ PR #928 merged), (b) tester d-test RED-first per ADR-0044 (✅ d068-td067-combined.sh 7/7 PASS), (c) 9-Lens attestation table above (✅ all 10 lenses attested), (d) PR review from @developer + @tester + @atilcan65 (⏳ in flight on PR #938).*

— @architect, cycle-1225, 2026-07-09