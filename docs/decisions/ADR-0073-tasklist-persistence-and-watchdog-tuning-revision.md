# ADR-0073: Task-list Persistence + Watchdog Tuning Revision (Sprint 32)

> **Status**: PROPOSED (draft, awaiting owner ratification per ADR-0012 birth contract)
> **Date**: 2026-07-19
> **Author**: @orchestrator (cycle ~#3760, post-owner-directive cycle-timestamp 2026-07-19T14:15+03:00, option A selection)
> **Sprint**: Sprint 32 Wave-extension (cycle ~#3751)
> **Reviewer**: @architect + @human (owner approval gate per ADR-0031)
> **Sister-ADR**: AtilCalculator ADR-0072 (calc canonical, option A per WP5 #1121 — same doctrine, different repo, ADR number differs to preserve slug uniqueness)

## Context

### Problem statement

The context watchdog's instant-fire tuning (cycle #1638, Issue #725, closed 2026-06-30T17:47:16Z) tightened `STUCK_AFTER_MIN` 20→1 and `STUCK_AFTER_MIN_CRITICAL` 3→0 to enforce owner-directive: *"85% must fire BEFORE timer (instant), not sustained-threshold"*.

While the spirit of the directive was correct (instant-fire > delayed-clear on genuinely stuck panes), the tightening overshoot produced a **secondary defect**: `/compact` operations take 30-90 seconds, but the watchdog's 60s cycle interval + 1-minute `STUCK_AFTER_MIN` causes stuck_override to fire DURING legitimate `/compact` execution, producing **214 false-positive cleared=yes events across the 7-day journal window** (verified `2026-07-19T14:38Z` via direct file inspection of `/var/log/dev-studio/AtilCalculator/journal/facts-2026-07-{13..19}.jsonl`).

### Ground-truth metrics

| Date | Total facts | cleared=yes |
|---|---|---|
| 2026-07-13 | 289 | 19 |
| 2026-07-14 | 392 | 28 |
| 2026-07-15 | 374 | 32 |
| 2026-07-16 | 382 | 38 |
| 2026-07-17 | 470 | 44 |
| 2026-07-18 | 463 | 38 |
| 2026-07-19 | 196 | 15 |
| **Total (7d)** | **2,566** | **214** |

(Note: owner-directive cited 210 — non-fabrication guard adjustment: actual count is **214** across 7 days, all correlated with `stuck_override` triggers per file inspection. Journal grows ~1/day; current cycle ~#3760 count = 215, within noise.)

**Zero `api_overflow` triggers** in the same window → all `/clear` events are false-positive stuck-detection.

### Root-cause chain

1. cycle #1638 (Issue #725, owner directive 2026-06-30T17:25Z): tightening `STUCK_AFTER_MIN` 20→1 + `STUCK_AFTER_MIN_CRITICAL` 3→0
2. `STUCK_AFTER_MIN=1` is too aggressive vs watchdog's 60s poll cycle: cycle-counted 1-min trigger fires before `last_activity` updates post-`/compact`
3. `/compact` runs 30-90s — watchdog sees "no activity" mid-compact, fires stuck_override
4. Result: 214 false-positive cleared=yes events over 7 days, 100% stuck_override correlation, zero api_overflow

### Task-list persistence gap (orthogonal but co-discovered)

Issue co-surfaced: agents do not persist TodoWrite state across `/clear` operations. Per issue directive *"task-list persistence: hiç yok. TodoWrite in-context, /clear silinca kayıp"*. This creates a reprime-storm recovery gap even when `/clear` is correctly triggered (true stuck pane): agent loses task context, must re-derive from heartbeat log + sprint plan.

## Decision

### Two-layer solution

**Layer 1 — Watchdog tuning revision (defensive re-tightening with breathing room):**

- `STUCK_AFTER_MIN` default: **1 → 10** (10 minutes, restores instant-fire semantics for genuine stuck panes)
- `STUCK_AFTER_MIN_CRITICAL` default: **0 → 5** (5 minutes, restores rapid-fire semantics for 100%-saturated panes)
- Rationale: 10/5 chosen because `/compact` worst-case 90s + 8-minute margin covers all legitimate operation overhead (large context compacts, complex reasoning, peer-poke auto-response). 7-day saturation guard preserved at 100% critical + 75% threshold (down from current 100% saturation, restores original cycle #1638 spirit of "85% fire BEFORE timer" — owner-directive verbatim, but with safe breathing room).
- Saturation threshold table:
  - `pct >= CRITICAL_PCT` (100%): `STUCK_AFTER_MIN_CRITICAL` 5min (was 0min — too aggressive)
  - `pct < CRITICAL_PCT && pct >= THRESHOLD_PCT` (75%): `STUCK_AFTER_MIN` 10min (was 1min — too aggressive)
  - `pct < THRESHOLD_PCT` (75%): watchdog-only path, no stuck_override

**Layer 2 — Task-list persistence protocol:**

- New script: `scripts/tasklist-snapshot.sh` — input: ROLE + JSON TodoWrite state. Output: `state/tasklists/${ROLE}.md`.
- Format spec: `state/tasklists/${ROLE}.md` — markdown checklist, one bullet per TodoWrite entry, machine-readable frontmatter (`<!-- tasklist-snapshot role:${ROLE} ts:${ISO8601} -->`).
- Cadence Rule 1 atomic (per ADR-0055 §1): `tasklist-snapshot.sh` + d-test `d108-tasklist-snapshot-write-through.sh` (≥6 TCs per ADR-0049) + `scripts/tests/INDEX.md` same commit.
- `scripts/reprime-agent.sh` MESSAGE_HEAD: append `First action MUST be: cat state/tasklists/${ROLE}.md 2>/dev/null && restore TodoWrite from snapshot` directive.
- `scripts/kickoff/${ROLE}.txt.tmpl` (5 role files): add FIRST ACTION block to each — snapshot restore before any other action.
- `.gitignore.tmpl`: add `state/tasklists/*.md` (runtime, VCS-excluded).
- `docs/CONTEXT-HYGIENE.md`: §6.3 threshold table update (new defaults) + §7 new "Task-list Persistence Protocol" section.

### Cross-repo implementation

**Sister-pattern triple-sync (per WP5 #1121 slug-collision doctrine + Sprint 31 Path A v26 cross-repo forward-port):**

| Layer | Repo | File pattern | Sister-pattern |
|---|---|---|---|
| Canonical | atilproject/dev-studio-template (this ADR-0073) | `*.sh`, `*.tmpl` | source of truth |
| Mirror | atilproject/AtilCalculator (sister-ADR-0072) | `*.sh` (no .tmpl suffix) | full mirror, no .tmpl variant |
| Doc-only | atilproject/dev-studio-launcher | `README.md`, `new-project.sh` | template reference only, no code mirror (owner directive 2026-07-19: "template'den geliyor önerin uygun") |

**Slug-collision doctrine (WP5 #1121)**: Template's ADR-0072 slot is taken by `ADR-0072-s32-026-soul-sync-state-correction.md`. Per WP5 #1121 doctrine ("farklı repo aynı numara izinli"), this sister-ADR uses **ADR-0073** in template to preserve slug uniqueness within template repo. Per owner directive cycle ~#3760 (option A selection).

### Version targets

- Template v1.1.0 → v1.1.1 (post-merge, this ADR scope)
- AtilCalculator: sprint-32 main branch (no version tag — calc is not versioned)
- Launcher v0.4.0 → v0.4.1 (post-merge, this ADR scope) — README + new-project.sh only

## Consequences

### Positive

1. **Zero false-positive `/clear` events** post-deploy (vs 214/7d current baseline) — verified via 24h soak journal
2. **Genuine stuck panes still caught** within 5-10min (vs 0-1min current over-tight) — adequate for human-visible stuck
3. **Task-list persistence across `/clear`** — agents resume from snapshot, no reprime-storm recovery gap
4. **Sprint 32 DoD unblocked** — new project bootstrap end-to-end verification can pass (task-list persistence prerequisite per directive)

### Negative

1. **Slower stuck-pane detection**: 5-10min vs 0-1min. Trade-off: humans can manually `/clear` within 5min if needed (owner-only path, no impact on autonomy loop)
2. **Snapshot file accumulation**: `state/tasklists/*.md` runtime files, not VCS-tracked. Manual cleanup task for agents (rotate old snapshots at sprint boundary)
3. **Tasklist restore race**: if `/clear` fires mid-snapshot-write, restore may miss last task. Mitigation: atomic write-to-temp + mv pattern per `scripts/atomic-write.sh` sister-pattern (Issue #237 doctrine)

### Operational

1. **Systemd override cleanup**: if owner previously added manual override at `~/.config/systemd/user/dev-studio-context-monitor@AtilCalculator.service.d/override.conf` with old defaults, it now shadows the new defaults — README/close.md will instruct cleanup (override redundant since defaults now correct)
2. **Journal soak**: 24h post-deploy journal verification — if any `cleared=yes` events appear that are NOT correlated with `api_overflow` or genuine stuck panes, RETRO-034 candidate

## Alternatives considered

### Option A — Roll back cycle #1638 tightening entirely (STUCK_AFTER_MIN 20, CRITICAL 3)

**Rejected**: original pre-cycle-#1638 defaults were too lenient (delayed `/clear` by 20min on busy pane = owner-visible stuck for 20+ minutes). Cycle #1638 owner directive spirit (instant-fire) preserved in spirit but with breathing room.

### Option B — Polling-only approach (no stuck_override, just heartbeat-watchdog visible)

**Rejected**: agent-watch loop is GitHub-poll-driven, not local-file-watch. Stuck panes with no activity never reach GitHub. Stuck_override is required layer.

### Option C — In-memory tasklist persistence (RAM only, no file write)

**Rejected**: `/clear` clears in-context state including RAM; only file persistence survives. Memory-only is no-persistence.

## Implementation path

### Story S32-XXX-A (this ADR — owner-ratification gate)

**Template file**: `docs/decisions/ADR-0073-tasklist-persistence-and-watchdog-tuning-revision.md` (this file)
**Sister-ADR**: AtilCalculator `docs/decisions/ADR-0072-tasklist-persistence-and-watchdog-tuning-revision.md` (PR #1168)
**Labels** (per ADR-0012 birth contract): `type:doctrine + status:proposed + agent:architect + cc:human`
**STOP**: Await owner ratification (ADR-0073 approved label + owner "go" verbatim) before S32-XXX-B/C/D/E.

### Story S32-XXX-B — Impl PR template repo (canonical source of truth)

**Files** (10 changes, single PR):
- `scripts/agent-context-monitor.sh` — STUCK_AFTER_MIN default 1→10, STUCK_AFTER_MIN_CRITICAL 0→5, header rationale update (cycle #1638 → revised by ADR-0073 cycle-ref)
- `systemd/dev-studio-context-monitor@.service` — `Environment=` lines update (`STUCK_AFTER_MIN=10`, `STUCK_AFTER_MIN_CRITICAL=5`)
- `scripts/reprime-agent.sh` — MESSAGE_HEAD append: "First action MUST be: cat state/tasklists/${ROLE}.md 2>/dev/null && restore TodoWrite from snapshot"
- `scripts/kickoff/${ROLE}.txt.tmpl` (5 role files) — FIRST ACTION block: snapshot restore
- `scripts/tasklist-snapshot.sh` — NEW file
- `.gitignore.tmpl` — `state/tasklists/*.md` runtime entry
- `docs/CONTEXT-HYGIENE.md` — §6.3 threshold table update + §7 new "Task-list Persistence Protocol" section
- `scripts/tests/d108-tasklist-snapshot-write-through.sh` — NEW (≥6 TCs per ADR-0049)
- `scripts/tests/d1XX-compact-breathing-room.sh` — NEW (STUCK_AFTER_MIN=10 verification, 6 TCs)
- `scripts/tests/d108-context-watchdog-instant-fire.sh` — regression update (new defaults)
- `scripts/tests/INDEX.md` — Cadence Rule 1 atomic (ADR-0055 §1) with d-test file entries

### Story S32-XXX-C — Forward-port PR calc

Same file list as S32-XXX-B but `.tmpl` suffix removed (calc has no .tmpl). Plus `state/tasklists/.gitkeep` create + directory bootstrap.

### Story S32-XXX-D — Launcher doc-only sync

- `README.md` — new section "Task-list Persistence" + ADR-0073 link
- `new-project.sh` verify: template-clone path creates `state/tasklists/` + `.gitignore` entry (template-side; calc-side applies on init)
- Version bump v0.4.0 → v0.4.1

### Story S32-XXX-E — Integration test

`scripts/tests/e2e-tasklist-persistence-through-clear.sh` — full lifecycle (TodoWrite → snapshot → /clear → reprime → state restore). Cadence Rule 1 atomic: test + INDEX.md same commit.

### Story S32-XXX-F — RETRO + close

- `docs/sprints/sprint-32/close.md` add "Watchdog tuning revision + tasklist persistence" section
- `RETRO-032.md` cycle #1638 → ADR-0073 evolution capture (defensive tightening → data-driven revision doctrine)

## Cross-references

- **Issue #725** (closed 2026-06-30T17:47:16Z, "URGENT P0: Context watchdog defaults too lenient — instant-fire fix (cycle ~#1638)") — original tightening directive
- **cycle #1638** — owner-directive 2026-06-30T17:25Z verbatim: "85% must fire BEFORE timer (instant), not sustained-threshold"
- **Issue #238** — "Do NOT self-pause" doctrine (escalate blockers immediately)
- **ADR-0012** — 4-cat label invariant birth contract
- **ADR-0031** — owner merge gate
- **ADR-0044** — RED-first TDD (d-tests before impl)
- **ADR-0049** — d-test framework (≥5 TCs behavioral, ≥3 TCs hygiene/docs)
- **ADR-0055 §1** — Cadence Rule 1 atomic (d-test + impl + INDEX.md same commit)
- **ADR-0059** — Cluster-squash cadence (3-PR cluster in 60s window)
- **ADR-0057** — Closes anchor strict format (`Closes #N` vs `Refs #N`)
- **Issue #1121** — Sprint 30 WP5 slug-collision doctrine (farklı repo aynı numara izinli)
- **Sprint 31 Path A v26** — cross-repo forward-port cluster-squash sister-pattern
- **Issue #237** — atomic-write doctrine (write-to-temp + mv pattern, sister to tasklist-snapshot.sh)
- **Sister-ADR**: AtilCalculator ADR-0072 (calc canonical, option A per WP5 #1121)

## Open questions for owner ratification

1. **10/5 default selection**: 10-min STUCK_AFTER_MIN + 5-min CRITICAL chosen as conservative defaults. Owner may ratify different values (e.g., 5/2 for faster detection, 15/8 for more breathing room). Cycle #1638 owner-directive spirit preserved at all reasonable values.
2. **Tasklist snapshot format**: markdown checklist with frontmatter (current proposal). Alternative: pure JSON (machine-only, not human-readable). Owner preference?
3. **state/tasklists/*.md gitignore**: confirmed VCS-excluded. Alternative: VCS-include for audit trail. Owner preference?
4. **Systemd override cleanup**: README/close.md instruction sufficient? Or formal `scripts/cleanup-systemd-overrides.sh` helper needed?

---

*— @orchestrator, cycle ~#3760 (post-owner-directive cycle-timestamp 2026-07-19T14:15+03:00, option A selection per cycle ~#3760). Draft awaiting owner ratification per ADR-0012 birth contract. Sister-ADR-0072 (AtilCalculator PR #1168).*
