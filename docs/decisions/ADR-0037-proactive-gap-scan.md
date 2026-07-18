# ADR-0037: Orchestrator Proactive Gap-Scan (extend `proactive-board-scan.sh` with D5–D8)

- **Status**: Proposed
- **Date**: 2026-06-22
- **Deciders**: @architect, @developer, @tester, @orchestrator, @atilcan65
- **Related**: Issue #235 (P0 — orchestrator gap-scan duty), Issue #221 (P0 — impl-gap exemplar), Issue #232 (P1 — design-drift exemplar), Issue #238 (P0 — self-standby exemplar), `scripts/proactive-board-scan.sh` (existing, D1–D4, 213 lines, merged via PR #199), `scripts/agent-state.sh` v5 `proactive_sweep_last_utc` (HWM throttle), Issue #44 (Sprint 1 ORCH proactive mode A — grandparent), Issue #48 (PR-T1 extraction — parent), Issue #236 (P0 — template port)

## Context

Third autonomy-loop incident in 4 days had a **predictable failure shape** (RCA-19 #231 RCA, #228 cmd_set RCA, #221 dual-channel design drift). The pattern: doctrine ADR is accepted; implementation is filed as a follow-up issue; orchestrator assigns the issue; the issue sits in `status:ready` for hours; nobody notices the implementation is missing until the next time the gap causes a runtime failure.

Issue #235 frames this as a missing orchestrator duty: **proactive gap-scan**. The proposed script (`scripts/orchestrator-gap-scan.sh`, ~50 lines, cron every 30 min) detects 4 gap classes and routes alerts to the right agent.

**Architect challenge to the spec** (per "delete options, not add them" doctrine): the existing `scripts/proactive-board-scan.sh` (merged via PR #199, ROLE-gated to orchestrator, HWM-throttled) already does 4 BOARD-hygiene detections (D1 ready_unblocked, D2 orphan_backlog, D3 stalled, D4 wip_overflow). The 4 new gap detections (D5–D8) are SYSTEM-health detections on the same data domain (open issues + agent state). A **separate script doubles the boilerplate** (kill switch, role gate, HWM, state helper, cron registration, event consumer) **for marginal conceptual benefit**. The 4 new detections are "proactive-scan-flavored" enough to belong in the same script.

## Decision

**Extend `scripts/proactive-board-scan.sh` with 4 new detections (D5–D8)** — not a new separate script. Single script, single HWM, single cron registration, single `proactive_scan` event stream.

### New detections

| # | ID | Trigger condition | Output event kind | Routing target |
|---|---|---|---|---|
| **D5** | `impl_gap` | Issue with `status:ready` AND `agent:developer` AND a "Doctrinal-PR" reference (e.g. `Refs #221` or `Closes #N` where N is a doctrine-only ADR) AND no `feat:` / `fix:` / `chore:` PR exists for the issue's repo path within 7 days of the doctrine PR's merge | `proactive_scan` (aggregated) with `routing: developer` | `@developer` via `notify.sh -l developer` + auto-comment on the issue |
| **D6** | `dev_idle` | Issue with `status:in-progress` AND `agent:<role>` AND role's `last_heartbeat_utc` is older than 60 min AND no PR opened in last 60 min | `proactive_scan` (aggregated) with `routing: <role>` | `<role>` via `notify.sh -l <role>` (nudge, not blocker) |
| **D7** | `dep_broken` | Issue with `status:ready` AND `blocks on #N` body marker AND predecessor `#N` is `state: open` AND predecessor is NOT `status:blocked`/`status:in-progress` | `proactive_scan` (aggregated) with `routing: orchestrator` | `@orchestrator` via `notify.sh -l orchestrator` (PM decision: re-prioritize or unblock) |
| **D8** | `ac_creep` (renamed from `scope_drift` per PM SUGGESTION — avoid terminology overlap with ADR-0031 "scope drift" = PR size growth) | Issue's `updatedAt` is within 48h of its `status:ready` flip AND its AC source-of-truth content hash has changed since `status:ready` flip (AC source = `docs/backlog/STORY-N.md` if linked from issue body, else issue body) — this catches mid-sprint scope add, not mere AC clarification | `proactive_scan` (aggregated) with `routing: product-manager` | `@product-manager` via **auto-creating a `[Scope-Change]` issue** with `type:incident` + `status:ready` + `agent:product-manager` + `cc:product-manager` + `priority:P1` (PM's standard `issue_assigned` wake path) — replaces direct `notify.sh -l product-manager` which only hits Telegram (PM agent reads GitHub artefacts) per PM SUGGESTION + Auto-Ping Hard-Rule ("insan kurye değil") |

**Key design choice (D5 — the killer detection)**: pattern is "doctrine-only ADR merged + ready status + no impl PR" — this is the exact shape of #221 (ADR-0033 merged 2026-06-21T21:00Z, #222 dev idle 8h 42min on 2026-06-22T06:08Z, no impl PR exists). Catching this within 30 min would have prevented 8h of dev idle. Detection window: 7 days post-doctrine-merge (gives impl PR a reasonable grace period; alerts only if still missing).

### Integration approach

Add 4 new `if [ ... ]; then ... fi` blocks after the existing D4 block (after line 182), each producing a JSON entry of shape `{detection: "<id>", items: <array>}` to be merged into the existing `detections` array. Final aggregation (line 184–213) is unchanged — single `proactive_scan` event with 8 sub-detections.

```bash
# --- D5: impl_gap ---
# Doctrine-only ADR merged + status:ready + no impl PR within 7 days.
# POC: see ADR §D5 algorithm below (max 30 lines).
impl_gap_items="$(... gh issue list ... | jq ... | ... )"  # ~15 lines
if [ "$(echo "$impl_gap_items" | jq 'length')" -gt 0 ]; then
  detections="$(echo "$detections" | jq -c --argjson items "$impl_gap_items" \
    '. + [{detection: "impl_gap", routing: "developer", items: $items}]')"
fi
```

(The D5–D8 algorithm bodies total ~60–80 lines — dev writes final, this is just the integration seam.)

### D5 algorithm (the killer detection) — design

```
For each open issue with status:ready AND agent:developer:
  issue_updated = issue.updatedAt
  issue_refs = parse "Closes #N" / "Refs #N" from issue.body  (or use GitHub's issue references API)
  for each ref in issue_refs:
    if is_pr_closed_and_doctrine_only(ref):
      doctrine_merged_at = ref.merged_at
      age_days = (now - doctrine_merged_at) / 86400
      if age_days > 7:  # impl grace period
        # Check if any feat:/fix:/chore PR exists that closes this issue
        if not has_impl_pr(issue):
          emit impl_gap alert for (issue, ref)
```

`is_pr_closed_and_doctrine_only(pr)`: PR title starts with `docs(adr):` AND is merged. Cheap query: `gh pr list --search "is:pr is:closed author:@me label:none" --state merged --json number,title,mergedAt --limit 100 | jq '[.[] | select(.title | startswith("docs(adr):"))]'`.

`has_impl_pr(issue)`: `gh pr list --search "Closes:#N is:pr" --json number --limit 5`. If empty, impl is missing.

**Reuse, not reinvent**: the `blocks on #N` body-marker parse in D7 is the same regex as the existing D1 `(?i)block(?:ed|s)?\s+by:?\s*#?(?<nums>(?:\s*[#,\s]*\d+\s*)+)` (line 110). Refactor into a shared helper `parse_blocker_refs(body)` to avoid duplication.

### Cron registration (human-only per CLAUDE.md)

The existing `scripts/proactive-board-scan.sh` is called by `agent-watch.sh` (orchestrator's poll loop, every 60s with 5-min HWM throttle). The new D5–D8 detections increase per-sweep cost (~5x more `gh api` calls per detection), but still fit within the 5-min throttle. **No cron change needed** — the existing 5-min throttle via `proactive_sweep_last_utc` (line 84) absorbs the new cost.

(Alternative: separate cron at 30-min cadence per #235 body — REJECTED because: 5-min throttle already gives near-real-time detection; 30-min cadence means 30-min MTTD on gap detection, which is too slow for the P0 use case. The 60s poll × 5-min throttle = 5-min MTTD, which is the right cadence.)

### Backward compatibility

- D1–D4 behavior: UNCHANGED. Existing `d015` regression test (9/9 PASS) still passes. PR #230's stderr-capture fix still applies.
- `proactive_scan` event shape: BACKWARDS-COMPATIBLE — new detections add fields, never remove or rename.
- `scripts/agent-watch.sh` call site (line 1183): UNCHANGED. The wrapper that invokes the standalone script is unchanged.
- Existing `QUERY_ASSIGNED_ANY_STATUS_ENABLED` / `PROACTIVE_SWEEP_ENABLED` kill switches: still work. No new switches; D5–D8 inherit the existing `PROACTIVE_SWEEP_ENABLED` toggle.

### d026 spec (regression test)

| # | Test | Coverage |
|---|---|---|
| 1 | Issue with `status:ready` + `agent:developer` + `Refs #221` (doctrine merged 7+ days ago, no `feat:` PR closes) → D5 fires | happy path |
| 2 | Same issue but `feat:` PR closes #221 within 7 days → D5 does NOT fire | negative (impl exists) |
| 3 | Dev with `last_heartbeat_utc` 90 min old + issue `status:in-progress` + no PR opened → D6 fires for dev | happy path |
| 4 | Issue with `blocks on #231` in body + #231 is `status:ready` (not blocked/in-progress) → D7 fires | happy path |
| 5 | Issue's AC source-of-truth (`docs/backlog/STORY-N.md` or issue body) content hash changed since `status:ready` flip → D8 fires + auto-creates `[Scope-Change]` issue with `agent:product-manager` | happy path (renamed `scope_drift` → `ac_creep`) |
| 6 | All 8 detections (D1–D8) in single aggregated `proactive_scan` event with `detections[]` array | integration shape |

**Total: 6 TCs**.

### Sprint 4 commitment

| Role | SP | Scope |
|---|---|---|
| **Architect** (me) | 0.5 | This ADR + d026 spec — DONE on PR open |
| **Developer** | 1.0 | D5–D8 impl (~60–80 lines in `proactive-board-scan.sh` after line 182) + refactor `parse_blocker_refs` helper (D1 reuse) + d026 regression |
| **Tester** | 0.5 | d026 sign-off (6 TCs) |
| **Total** | **2.0** | Fits Sprint 4 EOD (2026-06-22T24:00Z, ~17h budget from this ADR) |

## Rationale (architect view — why extend, not new)

- **Smaller blast radius**: ~60–80 lines added vs ~150 lines for new script (kill switch + role gate + HWM + state helper + cron + event consumer). Reuses PR #199's already-tested infrastructure.
- **Single HWM**: `proactive_sweep_last_utc` is one bucket. Two scripts would need two HWM fields (state schema migration) or share a field (race condition).
- **Single cron / single event stream**: agent-watch.sh's 60s poll × 5-min throttle gives 5-min MTTD on gap detection. Two scripts = two event types to consume downstream; aggregated event stays single.
- **Same data domain**: D5–D8 query the same `gh issue list` and `gh issue view` APIs as D1–D4. Splitting into a new script means duplicating the same `gh` queries (with different filters) — no decoupling benefit.
- **Backward compatibility**: D1–D4 behavior is byte-identical. d015 (9/9 PASS) + d022 (PR #219) regressions cover the existing surface. New d026 covers the new surface. No migration risk.
- **Naming clarity**: "proactive_scan" is the existing event kind; adding "proactive_gap_scan" as a separate event kind would create consumer-side ambiguity. Better to enrich the existing event with new detection IDs (D5–D8).
- **Reversibility**: if D5–D8 turn out to be the wrong shape, removing them is 4 block deletes. The new-script approach would require deleting an entire 50-line script + cron entry + consumer.

### Why NOT a new `orchestrator-gap-scan.sh` (the issue body's preferred approach)

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **A — Extend existing** (this ADR) | Reuses HWM + role gate + kill switch; single cron; single event; ~60 lines; backward compat | "Conceptually" mixes board hygiene with system health (a labeling concern) | **RECOMMENDED** |
| **B — New `orchestrator-gap-scan.sh`** (issue body) | Clean conceptual separation | Doubles boilerplate; two HWM fields; two cron entries; two event kinds; ~150 lines; no consumer benefit | **REJECTED** — only wins on the "conceptual separation" axis, which is a labeling concern we can solve with detection IDs |

If owner prefers B, it's a 1-line ADR amendment to switch. Reversible.

## Consequences (positive / negative / follow-ups)

**Positive**:
- Closes the systemic gap that caused #221 + #232 + #233 (3 instances of doctrine-merged-impl-missing pattern in 24h)
- D5 catches the exact #221 shape within 7 days (MTTD 5 min via 5-min HWM)
- D6 catches the dev-idle shape that #238 is about (and that #222 hit 8h 42min on)
- D7 catches the dep-broken chain shape (#233 blocks on #231 — would have been caught at 5-min MTTD, not 8h)
- D8 (`ac_creep`) catches true AC source-of-truth changes (scope add) before sprint review, with low false-positive rate (content hash diff eliminates clarification noise)
- Single 5-min MTTD across all 4 gap classes

**Negative / tradeoffs**:
- Per-sweep cost ~5x higher (4 new `gh api` calls per sweep). Still well within rate limit (5000/hr, 4 calls × 12 sweeps/hr = 48 calls/hr for D5–D8). 5-min throttle holds.
- D5 algorithm heuristic (7-day impl grace) is a guess; may need tuning. d026 TC#2 covers the negative case. Adjustable via `IMPL_GAP_GRACE_DAYS` env var.
- D8 detection (AC file content hash) is more accurate than the original AC count delta — eliminates "AC clarification" false positives. Cost: ~30 lines dev work to fetch linked `docs/backlog/STORY-N.md` + compute content hash. False-positive risk: **low** (only true content changes fire). Fallback: PM judges per-alert on the auto-created `[Scope-Change]` issue, doesn't auto-act.

**Follow-up tickets**:
- **Dev**: D5–D8 impl in `proactive-board-scan.sh` (after line 182)
- **Dev**: refactor `parse_blocker_refs` helper to share between D1 and D7
- **Dev**: d026 regression test (6 TCs)
- **Tester**: d026 sign-off
- **Orchestrator**: monitor for D5–D8 false positives in first 48h post-deploy; adjust heuristics if needed
- **Human (owner)**: approve the watcher extension (no `.github/workflows/` change, no `.claude/` change)
- **Architect (post-merge)**: update `.claude/CLAUDE.md` §Orchestrator role to add "proactive gap-scan" to duties
- **Architect (post-merge)**: open Issue #236 (already exists — template port; blocks on this ADR's merge)

## References

- Issue #235 (P0 — this ADR's source issue)
- Issue #221 (P0 — impl-gap exemplar, the "D5 case")
- Issue #232 (P1 — design-drift exemplar, the "D5 secondary case")
- Issue #238 (P0 — self-standby exemplar, the "D6 case")
- Issue #233 (P0 — template port of RCA-19)
- Issue #236 (P0 — template port of this ADR)
- Issue #44 (Sprint 1 ORCH proactive mode A — grandparent)
- Issue #48 (PR-T1 extraction — parent, PR #199 merged)
- PR #199 (`refactor(agent-watch): extract proactive-board-scan.sh for #48 PR-T1`) — MERGED 2026-06-21
- PR #230 (`fix(scripts): STORY-201 — capture query_proactive_sweep stderr to log file`) — OPEN
- `scripts/proactive-board-scan.sh` (213 lines, lines 1–213) — D1–D4 implementation
- `scripts/agent-state.sh` v5 `proactive_sweep_last_utc` — HWM field
- ADR-0002 (autonomy loop — foundation, mentions proactive-board-scan)
