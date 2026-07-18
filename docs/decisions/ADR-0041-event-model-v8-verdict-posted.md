# ADR-0041: Event Model v8 — `verdict_posted` kind (PR comment verdict detection)

## Status

Proposed

## Date

2026-06-24

## Deciders

- @architect (drafted per Issue #312 RCA + orchestrator dispatch 2026-06-24T00:23 +03)
- @orchestrator (design owner; #312 incident commander)
- @developer (impl — agent-watch.sh v8 extension; agent-watch-verdicts.sh Option B fast-path author)
- @tester (regression — d036 merged via PR #313)
- @owner (doctrine approval — v8 event taxonomy is watcher schema change)

## Context

Issue #312 (P0, status:in-progress, agent:developer) — Sprint 7 tester verdict on PR #307 (🟢 APPROVED 2026-06-23T17:14:58Z) was **missed by the standard polling loop** (`scripts/agent-watch.sh developer`). Developer was idle for ~2h waiting on a verdict that was already delivered — the polling loop never surfaced the `pr_comment_mention` / verdict event because the verdict didn't @-mention the developer.

### RCA — what the polling loop looks at

`scripts/agent-watch.sh` v7 event taxonomy (line 97) has **11 event kinds**:

```
issue_assigned | pr_review_requested | pr_new_commit | pr_comment_mention |
stale_cc | stale_verdict | missing_expectation | label_change |
pr_merged | proactive_scan | issue_assigned_any_status
```

**None of them fire on PR comment verdicts.** The `pr_comment_mention` kind fires only when the comment body contains `@<role>` — but a tester verdict typically follows the structured `🟢 APPROVED / 🟡 SUGGESTIONS / 🔴 CHANGES_REQUESTED` template without an explicit `@mention`.

### Empirical impact (single observed case)

PR #307 (STORY-300 d036b + test_precedence.py TDD RED) — tester delivered `🟢 APPROVED` verdict at 2026-06-23T17:14:58Z. Developer idled until ~19:21Z (≈2h 6min) before re-checking PR comments manually. 67/67 CLI tests went GREEN only after this manual re-check. Sister PRs (#310 → closed, #311 → closed, #313 → merged, #314 → merged) shipped in the same wake window after the verdict was finally surfaced.

### Two fix paths (Issue #312 §RCA)

| Option | Approach | Time | Reversibility |
|---|---|---|---|
| **A** | Extend `agent-watch.sh` v8 event taxonomy with `verdict_posted` kind | ~1 SP | Medium (touch the watcher core; ships in a coordinated release) |
| **B** | Standalone `scripts/agent-watch-verdicts.sh` supplement + opt-in poll | ~0.5 SP | High (no agent-watch.sh changes; supplement can be retired) |

Sprint 7 cadence chose **B for fast-path** (merged via commit `52974ab` on `feat/issue-312-verdict-detect`, ahead of main by 1) AND **A for long-term** (this ADR). Sister regression PR #313 (d036-pr-verdict-detect) covers both paths via OR-check.

## Decision

We will adopt **Event Model v8** in `scripts/agent-watch.sh`: extend the event taxonomy with a new `verdict_posted` kind that fires when a PR comment matches the Issue #312 RCA Option A keyword classification table.

### Event schema (additions to v7)

```json
{
  "kind": "verdict_posted",
  "number": <PR number, int>,
  "verdict": "approved" | "suggestions" | "changes_requested",
  "author": "<comment author login>",
  "comment_id": "<GH node ID, string>",
  "comment_url": "<url to comment>",
  "pr_url": "<url to PR>",
  "role": "<polling role, e.g. developer>",
  "context": {
    "verdict_class": "verdict:approved | verdict:suggestions | verdict:changes_requested",
    "source": "agent-watch.sh v8",
    "keyword_matched": "🟢 | APPROVED | LGTM | sign-off | 🟡 | SUGGESTIONS | non-blocking | 🔴 | CHANGES_REQUESTED | REQUEST CHANGES | blocker"
  }
}
```

### Verdict classification (verbatim from Issue #312 RCA Option A keyword table)

| Class | Keywords (word-boundary regex) |
|---|---|
| `approved` | `\bAPPROVED\b` \| `\bLGTM\b` \| `sign-?off` \| `🟢` |
| `suggestions` | `\bSUGGESTIONS\b` \| `non-?blocking` \| `🟡` |
| `changes_requested` | `\bCHANGES_REQUESTED\b` \| `\bREQUEST CHANGES\b` \| `\bblocker\b` \| `🔴` |
| (no verdict) | anything else → **NOT emitted** (FP guard) |

**Severity precedence**: `changes_requested` > `approved` > `suggestions`. If a comment body matches multiple classes, the most severe wins.

### Detection scope (sister to PR #313 d036 scope)

The new `query_recent_verdict_comments` function fires only on PRs where:

1. **PR is open** (`--state open`) — closed PRs don't need a verdict anymore.
2. **Polling role is in scope**:
   - `cc:<role>` label present (someone explicitly cc'd this role)
   - `agent:<role>` label present (the role is the PR author/owner)
   - `verdict-by:<ts>` label present (a verdict expectation exists)
3. **Comment is newer than last seen** — uses the existing `last_seen_utc` dedup bucket (5-min window, same as other kinds).

This scope guard prevents verdict spam on unrelated PRs (sister to d036 T7).

### Event ID format (consistent with v6/v7)

```
verdict-posted-<pr_number>-<comment_id_sha7>-b<bucket>
```

Where `bucket = floor(unix_timestamp / 300)` (5-min window). Same dedup scheme as `stale_verdict`, `stale_cc`. This means v8 re-runs of the same comment do not double-fire.

### Integration in `agent-watch.sh poll_once`

Add a new function (sister to existing `query_recent_pr_comments` at line 609):

```bash
query_recent_verdict_comments() {
  # Fetches open PRs with cc:<role> / agent:<role> / verdict-by:<ts>
  # For each, fetches comments newer than last_seen_utc
  # Classifies via classify_verdict (verbatim keyword table)
  # Emits one verdict_posted NDJSON event per matching comment
}
```

Insertion point: after `query_pr_comment_mention` (line 609) and before `query_stale_cc` (line 808). This groups all PR-comment-derived events together.

### Wake trigger

Verdict events wake the polling role via the existing `wake_pane_for_role` mechanism (consistent with all other kinds). When the role is the PR's `agent:<role>`, the existing self-cc skip rule (v7, Issue #94) applies — the author doesn't wake themselves on their own PR's incoming verdict (they'll see it on next manual check anyway).

### Deprecation of `scripts/agent-watch-verdicts.sh`

Once v8 ships and d036-pr-verdict-detect covers BOTH paths, the standalone supplement can be retired. Suggested timeline:

| Phase | Action | Owner |
|---|---|---|
| Phase 0 (now → v8 ship) | Run BOTH `agent-watch.sh` (without v8) AND `agent-watch-verdicts.sh` in parallel | dev (current state, commit `52974ab`) |
| Phase 1 (v8 ship) | `agent-watch.sh` v8 emits `verdict_posted` natively; `agent-watch-verdicts.sh` continues for one sprint as belt+suspenders | dev |
| Phase 2 (one sprint after v8) | `agent-watch-verdicts.sh` retired; d036 (PR #313) becomes sole regression coverage | dev + tester |

### Out of scope (separate ADRs / issues if needed)

- Verdict keyword localization (TR/EN/de) — current regexes are EN-only; defer to Sprint 8+ if non-EN users emerge.
- Verdict on PR Review API (`gh pr view --json reviews`) — this is a different data source than PR comments; defer unless we observe a gap class.
- Verdict on issue comments (not just PR comments) — different event kind (`issue_verdict_posted`?), not yet a documented gap.
- Owner-override of verdict (e.g., owner pushes despite 🔴) — already covered by ADR-0031.

## Consequences

### Positive

1. **Closes the verdict-missed gap class** — any role waiting on a PR-comment verdict gets notified within the 5-min dedup window, vs the 2h+ observed in PR #307 incident.
2. **Boring tech wins** — extends existing event taxonomy rather than inventing a parallel system. v8 is a backward-compatible addition (no v7 event removed).
3. **Belt + suspenders** — Phase 0/1/2 phases run BOTH `agent-watch.sh` and `agent-watch-verdicts.sh` in parallel, ensuring no regression during the cutover.
4. **Deterministic dedup** — same 5-min bucket math as v6/v7, so dedup state in `/var/log/dev-studio/<project>/agent-state/<role>.json` `processed_event_ids` continues to work without migration.
5. **Architectural reversibility** — if v8 turns out to over-fire or under-fire, the keyword table can be tightened via PR without touching the event taxonomy itself.

### Negative

1. **Watcher core change** — `agent-watch.sh` is the most-touched file in the project (15+ ADRs reference it). v8 adds ~80 lines; PR review burden falls on @tester for the full regression sweep (d015 + d025 + d036).
2. **False-positive risk (T6 d036)** — bare substring match would over-fire on words like "approval" or "approved-by". Mitigation: word-boundary regex (`\b...\b`) per the keyword table; d036 T6 covers FP guard.
3. **Scope guard complexity** — the role-in-scope check (cc/agent/verdict-by) needs careful implementation to avoid spamming PRs the polling role isn't waiting on. Sister to d036 T7.
4. **Phase 0/1/2 overlap cost** — running two scripts in parallel doubles the polling load (60s × 2 = effectively 30s polling on PRs). Mitigation: keep `agent-watch-verdicts.sh` poll interval at 60s (same as main); PR comments API calls are deduped at GH level.
5. **GH API rate-limit** — verdict queries add 1 extra `gh pr list` + N `gh pr view` per role per poll. With 5 roles × 60s polling = 5 extra API calls per minute. Current rate limit (5000/hr) gives ample headroom, but a degraded rate-limit mode would need to drop verdict queries first.

### Follow-up tickets to file

- Issue #312 already exists (P0, agent:developer) — dev implements v8 inside `agent-watch.sh` (separate from the standalone script).
- d036 regression (PR #313, MERGED) — covers both Option A and Option B paths via OR-check.
- d037 regression (TBD) — v8-specific: dedup bucket math, role-scope guard, severity precedence, self-cc skip rule application.
- Owner action: approve v8 watcher schema change (doctrine amendment to ADR-0002 §Event Model).

## Doctrinal alignment

- **Issue #312** (P0, status:in-progress, agent:developer) — implements v8 inside `agent-watch.sh`
- **PR #313** (MERGED 2026-06-23T21:18:52Z) — d036-pr-verdict-detect regression coverage, covers both paths
- **`scripts/agent-watch-verdicts.sh`** (commit `52974ab` on `feat/issue-312-verdict-detect`) — Option B standalone fast-path
- **Issue #307** (tester verdict that triggered the RCA) — `🟢 APPROVED` at 2026-06-23T17:14:58Z, missed by polling loop
- **PR #310** (CLOSED), **PR #311** (CLOSED), **PR #314** (MERGED), **PR #318** (MERGED) — Sprint 7 P0 chain that shipped in the wake of the verdict
- **ADR-0002** (Autonomy Loop) — v8 event taxonomy is an extension; doctrine amendment required
- **ADR-0024** (stale-verdict watchdog schema) — v6 sister; v8 verdict_posted is the positive-direction twin of stale_verdict (verdict delivered vs verdict missed)
- **ADR-0026** (queue-empty @mention check) — proposed; v8 subsumes a portion of ADR-0026's intent (verdicts without @mention now surface)
- **ADR-0038** (Auto-Claim Protocol) — v8 doesn't change claim logic; verdict_posted is a wake signal, claim-next-ready.sh reads from `agent-state/<role>.json` same as before
- **PR #288** (§Doctrine Reminder 4-soul patch) — soul-level complement, no change
- **d015** (existing 9/9) — must remain GREEN after v8 ship
- **d036** (new, PR #313, MERGED) — verdict-detection regression coverage, both paths

## Sprint 7 phasing (1.5 SP total)

| Phase | Item | Owner | SP | Status |
|---|---|---|---|---|
| 0 | `scripts/agent-watch-verdicts.sh` standalone (Option B fast-path) | @developer | 0.5 | ✅ Done (commit `52974ab`, branch `feat/issue-312-verdict-detect`) |
| 0 | d036-pr-verdict-detect regression (both paths via OR-check) | @developer + @tester | 0.5 | ✅ Done (PR #313, MERGED 2026-06-23T21:18:52Z) |
| 1 | **ADR-0041 (this ADR)** | @architect | 0.25 | 🟡 This PR |
| 2 | `agent-watch.sh` v8 extension (verdict_posted kind + integrate into poll_once) | @developer | 0.5 | ⏳ Sprint 7 P1 or Sprint 8 P0 |
| 3 | d037 v8-specific regression (dedup / scope guard / severity precedence / self-cc) | @tester | 0.25 | ⏳ Sprint 7 P1 or Sprint 8 P0 |
| 4 | Owner merge of `agent-watch.sh` v8 PR + doctrine amendment to ADR-0002 | @owner | 0.25 | ⏳ Owner gate |

## References

- Issue #312 RCA (P0 incident)
- PR #313 (d036-pr-verdict-detect, MERGED)
- `scripts/agent-watch-verdicts.sh` (Option B standalone, commit `52974ab`)
- `scripts/agent-watch.sh` v7 event taxonomy (line 97 — 11 kinds)
- ADR-0002 (Autonomy Loop — doctrine amendment target)
- ADR-0024 (stale-verdict watchdog — v6 sister)
- ADR-0026 (queue-empty @mention — partially subsumed by v8)
- PR #288 (§Doctrine Reminder 4-soul patch)
- Sprint 7 P0 chain: #299, #300, #301, #307, #310, #311, #313, #314, #318
- Orchestrator dispatch 2026-06-24T00:23 +03 (architect execution)
- Arch review comments: prior #312 review (4 doctrinal concerns, addressed by this ADR)

— @architect, 2026-06-24T00:31Z, drafted per Issue #312 RCA + orchestrator dispatch + d036 regression coverage.