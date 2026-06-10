# Sprint 1 Plan — Hello-world FastAPI service

**Kickoff date:** 2026-06-10
**Sprint length:** 2 weeks (target end: 2026-06-24)
**Status:** In Progress

## Sprint Goal

> Stand up a minimal but production-shaped FastAPI service so the team has a working end-to-end loop (code → CI → deploy slot) for future stories.

In one sentence: **a founder can `cp -r template new-service` → `make run` → `curl /healthz` in under 5 minutes, then push and see a green CI check.**

## Capacity

| Metric | Value |
|---|---|
| Velocity target (first sprint, per `sprint-start.md` §2) | **20 pt** |
| Committed (max-of-three) | **15 pt** |
| Headroom | 5 pt |
| Stories committed | 4 (all sprint:1) |
| Stories deferred to Sprint 2 | 0 |
| Stories split | 0 (all ≤ 5 pt) |

## Final sizing (max-of-three reconciliation)

Per `gh issue 16` joint sizing: Architect 13 pt / Developer 10 pt / Tester 11 pt (agent totals).
Final per-story point = `max(architect, developer, tester)`.

| Story | Title | Arch | Dev | Test | **Final** | Agent | Pri | Upstream deps |
|---|---|---:|---:|---:|---:|---|---|---|
| STORY-001 | FastAPI service + /healthz | 5 | 3 | 3 | **5** | architect | P0 | — |
| STORY-002 | One-command test suite (pytest) | 2 | 3 | 3 | **3** | tester | P0 | STORY-001 |
| STORY-003 | GitHub Actions CI workflow | 5 | 3 | 3 | **5** | developer | P1 | STORY-001, STORY-002 |
| STORY-004 | GET /hello/{name} | 1 | 1 | 2 | **2** | developer | P1 | STORY-001 |
| **Total** |  | **13** | **10** | **11** | **15** |  |  |  |

No story > 8 → no split. All stories in velocity → no deferral.

## Assignments & Critical Path

```
        ┌─→ STORY-002 (3pt, @tester)        ─→ STORY-003 (5pt, @developer)
        │                                                          ↓
STORY-001 (5pt, @architect, trunk)                                   │
        │                                                          ↓
        └─→ STORY-004 (2pt, @developer, parallelisable, leaf) ─── (independent)
```

- **Critical path:** STORY-001 → STORY-002 → STORY-003 (13 pt; 65 % of sprint commit).
- **Parallelisable:** STORY-004 (can start as soon as STORY-001 lands; does not gate STORY-003).
- **Day-1 owner:** `@architect` on STORY-001.

### Project board state (set 2026-06-10)

| Story | Issue | Status | Agent field | Priority field |
|---|---|---|---|---|
| STORY-001 | #10 | **In Progress** | architect | P0 |
| STORY-002 | #11 | Ready | tester | P0 |
| STORY-003 | #12 | Ready | developer | P1 |
| STORY-004 | #13 | Ready | developer | P1 |

## Architectural commitments (ADR list)

To unblock downstream stories, `@architect` must produce these ADRs in or before STORY-001 implementation:

| ADR | Title | Trigger | Blocker for |
|---|---|---|---|
| **ADR-0001** | FastAPI service skeleton: package layout, Python pin, package manager, run command | STORY-001 | STORY-002, STORY-003, STORY-004 |
| **ADR-0002** | GitHub Actions action pin policy + supply-chain choices | STORY-003 | (none downstream; ADR-worthy for audit) |

**Convergent call from the panel** (all three agents agree):

- **Python pin:** 3.12 (architect 5pt mentions this; developer 3pt confirms; tester 3pt confirms).
- **Run/test command convention:** `make run` / `make test` (lowest friction; all three agents recommend).
- **Package manager:** `uv` (architect recommendation, converges with developer 3pt "3 unfamiliar libs"). Force-sync point: if ADR-0001 picks `uv`, STORY-003 CI cache must use `uv` cache, not `pip`.

ADR-0001 must be **accepted before** STORY-002 implementation starts (alignment gate flagged by architect).

## Risks & cross-agent concerns

1. **STORY-001 schedule risk = Sprint-1 schedule risk.** STORY-001 is the trunk. A 1-day slip cascades into 13 pt of downstream work on a 2-week sprint with effectively no slack. `@architect` must keep ADR-0001 tight and unblock `@tester` and `@developer` fast.
2. **Run command contract drift.** STORY-001 AC1 ("documented single command") + STORY-002 AC1 ("documented test command") + STORY-003 AC1 ("the exact same command as STORY-002") must agree. Drift = silent CI breakage. Owner: `@architect` pins in ADR-0001; `@tester` and `@developer` implement against that contract.
3. **STORY-003 human-merge latency.** `.github/workflows/` is human-only territory per CLAUDE.md file-ownership matrix. `@developer` proposes via PR + pings `@atilcan65`; "done" = approved, not merged. Real flow risk if `@atilcan65` is offline when the PR lands. Flagged, not blocking.
4. **STORY-001 AC4 (clean shutdown) — test-side trap.** `TestClient` in-process cannot observe a real process death. `@tester` plan: `subprocess` fixture (Popen `make run` → SIGTERM → assert exit 0, no traceback). `@architect` must ensure `make run` is PID-aware so the test does not flake.
5. **STORY-004 case-preservation (AC2) is a load-bearing demo contract.** `@architect` and `@developer` both recommend a one-line comment in the route handler pinning "case preserved, no normalisation" — locks behaviour against future refactors.
6. **STORY-004 URL-encoding baseline.** AC4 tests only `%20`; `@tester` recommends extending the parametrized test to `%2F` and a Unicode payload (`%E2%98%83` → ☃) to lock the "verbatim, no normalisation" baseline for Sprint 2 i18n work. Owner: `@tester` in test plan; `@developer` in code comment.

## Known gap (deferred, not blocking)

Issue bodies for **#10, #11, #12** still carry the pre-pivot "As a **backend developer (Devon)**" user-story framing. Q2's primary-persona pivot was applied to docs (`personas.md`, `backlog.json`, STORY-004) and to issue #13 only — the orchestrator handoff in this sprint said "sadece #13" (Q2 scope was the persona-pivot docs + STORY-004 framing, not a sweep of all issue bodies).

**Action:** rewrite the "As a …" line in #10, #11, #12 to "As a **founder two weeks out from a demo (Atil-in-2-weeks)**" before each story moves to In Progress. Tracked here; not blocking this sprint. Owner: orchestrator / PM in a 1-PR cleanup pass.

## Definition of Done (per CLAUDE.md — applies to every story)

1. All AC pass automated tests.
2. Merged to `main` via PR with human approval.
3. CI green on `main` post-merge.
4. Docs updated (README, changelog, ADR if design choices warrant one).
5. Project card moved to `Done` on Project #1.
6. No new P0/P1 bugs filed against the story within 24 h of merge.

**Story-specific DoD additions:**

- STORY-001 → ADR-0001 written and accepted in `docs/decisions/`.
- STORY-003 → PR explicitly @-mentions `@atilcan65` and waits for human approval before merge (`.github/workflows/` is human-only territory).
- STORY-004 → code comment pins case-preservation contract.

## Communication cadence

- **Daily standup:** 09:00 Europe/Istanbul, auto- or human-triggered. Orchestrator posts to `[Sprint 1] Daily Standup` issue (this sprint) and to Telegram.
- **PR comments:** structured (per developer.md and tester.md).
- **Cross-agent handoffs:** never DM. Always GitHub Issue or PR comment, with `@agent-role` mention.
- **Escalation to human:** Telegram bot (`scripts/notify.sh`) + GitHub `@`-mention to `@atilcan65`.

## Cross-references

- **Backlog source of truth:** `docs/backlog.json`, `docs/backlog/sprint-1/STORY-00{1..4}-*.md`.
- **Vision:** `docs/product/vision.md`.
- **Personas:** `docs/product/personas.md`.
- **Scope change #1 (persona pivot + STORY-004 promotion):** issue #14 (closed, HUMAN-approved 2026-06-10).
- **Joint sizing:** issue #16 (closing with reconciliation comment after this plan is merged).
- **Grooming tracking:** issue #9 (closed).
- **PR that brought this backlog in:** PR #15 (squash-merged to `main`, commit `e110cf2`).
- **Project board:** https://github.com/users/atilcan65/projects/1
- **Sprint 1 kickoff tracking issue:** see Sprint 1 issues, listed in the active sprint on Project #1.
