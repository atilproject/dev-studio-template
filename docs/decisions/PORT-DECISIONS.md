# PORT-DECISIONS — calc→tmpl ADR Gap Audit (S32-027)

> **Story:** [atilproject/dev-studio-template#156](https://github.com/atilproject/dev-studio-template/issues/156) (S32-027, Sprint 32 Wave 3 calc→tmpl gap-closing per cycle ~#3431)
> **Audit date:** 2026-07-18
> **Auditor:** @architect (cycle ~#3450+)
> **Sister-pattern:** [S32-003 / tmpl#142](https://github.com/atilproject/dev-studio-template/pull/142) (10 doctrine-critical ADR port batch, cluster-squash)

## Audit summary

| Metric | Calc (atilproject/AtilCalculator) | Tmpl (atilproject/dev-studio-template, origin/main pre-port) | Delta |
|---|---|---|---|
| ADR docs (excluding INDEX) | 79 | 42 | **−37** (tmpl missing 37 doctrine-amendment pairs + parent ADRs) |
| ADR docs (excluding INDEX + amendments) | ~57 | ~37 | **−20** parent ADRs |
| `*-amendment-*.md` files | 17 | 0 | **−17** amendments |

The Issue #156 estimate of "35 missing" was based on rough audit. **Actual gap: 20 parent ADRs + 17 amendments = 37 calc-only files** (some amendments overlap parent numbers like ADR-0019-amendment-2/3/4/5, ADR-0024-amendment-1/2, ADR-0038-amendment-1/2, ADR-0048-amendment-1/2/3 — counted as 17 distinct amendment files but ~10 distinct parent ADRs).

## Classification

### (A) DOCTRINE-PORT — ported in this PR (tmpl PR #150, this batch)

10 net-new ADR files copied from calc → tmpl (RESERVED placeholders resolved or new rows added). 8 additional files were already byte-equal between calc and tmpl origin/main (Sprint 28 S29-017 re-author pre-sync, S32-003 port batch, etc.) — copy was idempotent NO-OP.

| ADR | Title (short) | Tmpl slot pre-port | Status |
|---|---|---|---|
| [ADR-0041](./ADR-0041-event-model-v8-verdict-posted.md) | Event Model v8 — `verdict_posted` kind | (no row) | ✅ NEW row + file |
| [ADR-0043](./ADR-0043-8-lens-architect-review-checklist.md) | 8-Lens Architect Review Checklist | (no row) | ✅ NEW row + file |
| [ADR-0054](./ADR-0054-9lens-enforcement.md) | §9-Lens Enforcement Application | (no row) | ✅ NEW row + file |
| [ADR-0056](./ADR-0056-layer-5-idempotency-reconcile.md) | Layer 5 idempotency reconcile | (no row) | ✅ NEW row + file |
| [ADR-0058](./ADR-0058-comment-trigger-guard-multi-fire-prevention.md) | Comment-trigger guard + multi-fire prevention | RESERVED | ✅ RESERVED → real content |
| [ADR-0067](./ADR-0067-multi-reviewer-wake-doctrine.md) | Multi-Reviewer Wake Doctrine | RESERVED | ✅ RESERVED → real content |
| [ADR-0068](./ADR-0068-j4-tester-author-exception.md) | Layer 5 j.4 Tester-Author Exception | RESERVED | ✅ RESERVED → real content |
| [ADR-0069](./ADR-0069-form-c-race-detection.md) | Form C Verdict-Stamp Self-Sign-Off Race Detection | RESERVED | ✅ RESERVED → real content |
| [ADR-0070](./ADR-0070-closed-diagnostic.md) | Closed-Event 4-cat Invariant Diagnostic | RESERVED | ✅ RESERVED → real content |
| [ADR-0071](./ADR-0071-td-067c-open-diagnostic.md) | Open-Time Label-Strip Diagnostic | RESERVED | ✅ RESERVED → real content |

**Idempotent NO-OP files** (already byte-equal between calc and tmpl origin/main, copy verified via `diff -q`):
ADR-0034, ADR-0035, ADR-0037, ADR-0039, ADR-0044, ADR-0045, ADR-0053, ADR-0055.

### (B) DOCTRINE-PORT DEFERRED — number-collision, requires renumbering follow-up

Calc and tmpl ADRs share ADR numbers but encode DIFFERENT doctrines. Porting requires either renumbering tmpl or calc to resolve the collision.

| Calc ADR | Title (short) | Tmpl collision | Resolution |
|---|---|---|---|
| [atilproject/AtilCalculator ADR-0060](./../AtilCalculator/docs/decisions/ADR-0060-ac-mapping-verification-doctrine.md) | §AC Mapping Verification Doctrine | tmpl ADR-0060 = Claude Code 2.1.207 agent-flag | **DEFERRED** — tmpl#88 closure pinned to tmpl ADR-0060. Calc ADR-0060 needs renumber (e.g., ADR-0072) before port. |
| [atilproject/AtilCalculator ADR-0061](./../AtilCalculator/docs/decisions/ADR-0061-claude-code-agent-flag-removal.md) | Claude Code 2.1.207 — Remove `--agent` Flag | tmpl ADR-0060 (same doctrine under different number) | **DEFERRED** — duplicate doctrine already in tmpl. Calc ADR-0061-cli-2.1.207-agent-flag = same content, redundant. |
| [atilproject/AtilCalculator ADR-0059](./../AtilCalculator/docs/decisions/ADR-0059-cluster-squash-batch-lag-detection.md) | Cluster-Squash Batch-Lag Detection Doctrine | tmpl ADR-0059-cluster-squash-batch-lag-detection.md (same name, byte-equal content) | **DEFERRED** — already synced. INDEX entry for ADR-0059 still says "RESERVED — Sprint 28" (stale). INDEX inconsistency follow-up. |
| [atilproject/AtilCalculator ADR-0062](./../AtilCalculator/docs/decisions/ADR-0062-amendment-layer-5-label-change-verdict-gate.md) | §Layer 5 Label-Change Verdict-Gate Extension (amendment) | tmpl ADR-0062 RESERVED | **DEFERRED** — RESOLVED-by-amendment pattern. Port requires parent ADR check (does parent exist in tmpl?). See follow-up issue. |
| [atilproject/AtilCalculator ADR-0063](./../AtilCalculator/docs/decisions/ADR-0063-amendment-layer-4-cascade-strip-lane-transition-skip.md) | §Layer 4 Cascade-Strip Lane-Transition Skip (amendment) | tmpl ADR-0063 RESERVED | **DEFERRED** — same as 0062. |
| [atilproject/AtilCalculator ADR-0064](./../AtilCalculator/docs/decisions/ADR-0064-cross-user-env-var-pattern.md) | Cross-User Env Var Pattern | tmpl ADR-0064 RESERVED | **DEFERRED** — clean slot, port possible in follow-up PR. |
| [atilproject/AtilCalculator ADR-0065](./../AtilCalculator/docs/decisions/ADR-0065-cpython-3-12-13-asyncio-get-running-loop-fix.md) | CPython Tool-Cache + asyncio fix | tmpl ADR-0065 RESERVED | **DEFERRED** — clean slot, port possible in follow-up PR. |

### (C) CALC-SPECIFIC — not portable (by design)

These ADRs are AtilCalculator-specific (project structure, tech stack, front-end, persistence, engine perf). They are NOT doctrine — they document calc's own implementation choices. They SHOULD NOT be ported to tmpl because tmpl is the template from which calc was bootstrapped, not vice versa.

| ADR | Title | Reason |
|---|---|---|
| [ADR-0001](./../AtilCalculator/docs/decisions/ADR-0001-template-architecture.md) | Template Architecture (calc's view) | calc-local architectural summary |
| ADR-0017 | Tech stack for AtilCalculator | calc-specific (Python 3.11+, decimal.Decimal, etc.) |
| ADR-0018 | Front-end framework for MVP-1 web shell | calc-specific |
| ADR-0019 + 5 amendments | HTTP API contract (FastAPI surface) | calc-specific HTTP API |
| ADR-0022 | Persistence layer | calc-specific |
| ADR-0023 | Frontend architecture | calc-specific |
| ADR-0051 | Engine perf flake vs regression codification | calc-specific engine perf |

### (D) HYBRID — partial port with redaction

These ADRs contain both doctrine (portable) AND calc-specific examples. Tmpl should receive the doctrine, but calc-specific examples need redaction or annotation. Sister-pattern to (B) and (C).

| ADR | Title | Doctrine aspect (port) | Calc-specific aspect (redact) |
|---|---|---|---|
| ADR-0007 | Label cleanup and revert doctrine | General label hygiene doctrine | calc-specific timeline examples |
| ADR-0002-amendment-1 | Stale-verdict filter scope | TDD RED exclusion clause | calc-specific VerdBy timestamps |
| ADR-0024-amendment-1 (auto-verdict-by-hook) | Verdict-by hook auto-issuance | Hook pattern | calc hook impl details |
| ADR-0024-amendment-2 (stale-verdict-supersede) | Verdict-by supersede rule | Supersede doctrine | calc-specific timestamps |
| ADR-0038-amendment-1 (watcher-enforcement) | Watcher enforcement rule | WIP cap enforcement | calc-specific watcher names |
| ADR-0038-amendment-2 (workstream-awareness) | Workstream awareness | Multi-workstream doctrine | calc workstream names |
| ADR-0048-amendment-1, 2, 3 | Layer 5 trigger guards | Guard pattern | calc-specific PR numbers |
| ADR-0049-amendment-subcheck-k | d-test subcheck k | d-test framework extension | calc-specific d-test names |
| ADR-0057-amendment-closes-vs-refs-intent | Closes vs Refs intent rule | Intent classification doctrine | calc-specific intent examples |

**Decision for (D):** These amendments are tightly coupled to their parent ADRs (which already exist in tmpl). Recommended approach: port as SEPARATE files in follow-up PR with redaction, OR incorporate doctrine directly into parent ADR §Amendments section. Latter is preferred per ADR-0057 amendment-via-parent pattern.

## Cadence Rule 2 dispatch (forward-port)

Per Cadence Rule 2 amendment (orchestrator soul file §KAPI HOTFIX, this PR-cluster tmpl#140 sister-soul):
- ADR-0057, ADR-0059, ADR-0060, ADR-0066 already in tmpl — no dispatch needed
- 10 new ports in this PR (tmpl#150) — dispatch is the PR itself, no separate sister-issue dispatch
- Deferred items (B) above — file follow-up sister-issues for each renumbering workstream

## d-test integration (ADR-0049 ≥5 TCs)

Sister-pattern to d983 (S28-003 forward-port parity) — see `scripts/tests/d156-s32-027-adr-port-batch.sh` for the d-test verifying the 10 new ports are byte-equal to calc, the 8 idempotent copies remain byte-equal, and the INDEX.md updates preserve row uniqueness + ID monotonic.

## Sister-pattern references

- [S32-003 / tmpl#142](https://github.com/atilproject/dev-studio-template/pull/142) — 10 ADR port batch precedent
- [S32-004 + S32-005 / tmpl#140](https://github.com/atilproject/dev-studio-template/pull/140) — Soul-file sync (calc→tmpl, +5500B orchestrator + +1440B architect)
- [S32-007 / tmpl#141](https://github.com/atilproject/dev-studio-template/pull/141) — Stale URL hygiene (calc→tmpl)
- [S32-026 / Issue #155](https://github.com/atilproject/dev-studio-template/issues/155) — Soul sync audit (work-done-elsewhere per tmpl#140)
- [Cycle ~#3431](https://github.com/atilproject/dev-studio-template/issues/156#issuecomment-XXXXX) — Wave 3 direction corrected to calc→{tmpl,launcher}
- ADR-0012 (4-cat invariant) — applies to Issue/PR labels only, not ADR docs
- ADR-0044 (RED-first TDD) — applies to code changes only, not ADR docs
- ADR-0049 (d-test framework ≥5 TCs) — sister-pattern to d156
- ADR-0055 §1 (Cadence Rule 1 atomic) — d-test + INDEX.md row in same commit
- ADR-0057 (Closes anchor strict format) — tmpl#150 Closes #156 strict
- ADR-0059 (Cluster-Squash ≤15-sec window) — tmpl#150 + d156 may cluster if both squash-merged in window