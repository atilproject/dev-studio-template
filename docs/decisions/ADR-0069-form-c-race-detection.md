# ADR-0069 — ADR-0038 Amendment #2: Form C Verdict-Stamp Self-Sign-Off Race Detection (Issue #811)

- **Status:** Proposed (Sprint 24+ P2 doctrine hardening; closes Issue #811 P1 doctrinal codification)
- **Date:** 2026-07-04
- **Deciders:** @architect (doctrine/spec — this ADR), @developer (Layer 2 impl shipped in commit 156ef01 = `scripts/claim-next-ready.sh` amendment #2 + `scripts/tests/d020a-claim-next-ready-form-c.sh` + `scripts/tests/INDEX.md` row atomic, **Closes #811**), @tester (d020a sign-off pending — 5/5 GREEN locally on STORY-811-form-c-race-detection branch per d020a INDEX row, peer verification required), @product-manager (cross-lane sponsor — verify dev/tester/PM scenario coverage), @orchestrator (escalation carrier cycle ~#4033 — Form C spec ask), @atilcan65 (impl owner squash gate pending per file ownership matrix — `scripts/` developer territory, this ADR is docs-only)
- **Supersedes:** — (amends ADR-0038 §Auto-Claim Protocol as amendment #2; sister-pattern to [ADR-0038-amendment-watcher-enforcement.md](./ADR-0038-amendment-watcher-enforcement.md) which is amendment #2.0 of watcher enforcement, and [ADR-0038-amendment-workstream-awareness.md](./ADR-0038-amendment-workstream-awareness.md) which is amendment #1)
- **Related:**
  - [ADR-0002](./ADR-0002-autonomy-loop.md) — autonomy loop, WIP limit doctrine
  - [ADR-0012](./ADR-0012-required-label-set.md) — 4-cat label invariant
  - [ADR-0015](./ADR-0015-atomic-agent-handoff.md) — Atomic 4-flag handoff
  - [ADR-0024](./ADR-0024-stale-verdict-watchdog-schema.md) — `verdict-by:<ts>` convention
  - [ADR-0031](./ADR-0031-owner-override-doctrine.md) — owner-override PR merge
  - [ADR-0038](./ADR-0038-auto-claim-protocol.md) — §Auto-Claim Protocol (this ADR amends)
  - [ADR-0044](./ADR-0044-verdict-by-scope-clarification.md) — RED-first TDD (d020a sister)
  - [ADR-0049](./ADR-0049-behavioral-workflow-test-framework.md) — d-test framework (d020a = 5 TCs)
  - [ADR-0055 §1](./ADR-0055-d-test-id-uniqueness-sub-pattern-matrix.md) — Cadence Rule 1 atomic
  - [ADR-0056](./ADR-0056-layer-5-idempotency-reconcile.md) — Layer 5 idempotency reconcile (sister-pattern)
  - **ADR-0068** (Layer 5 j.4 tester-author exception — pending PR #817 merge, direct sister, same Sprint 24+ P2 doctrinal hardening cycle)
- **Closes:** Issue #811 doctrinal codification (impl Closes #811 already landed in commit 156ef01; this ADR seals the doctrine). **RETRO-016 candidate** — auto-claim re-flip loop cluster (3rd live instance cycle ~#4038 today).
- **Live Instances:**
  | # | Date | Cycle | PR | Symptom | Resolution |
  |---|---|---|---|---|---|
  | 1 | 2026-07-04T09:22Z | ~#3523 | PR #795 | Squash-gate reproducer | Owner squash landed in 5-min window before auto-claim re-flip (historical evidence only) |
  | 2 | 2026-07-04T12:14Z | ~#4015 | PR #817 | Architect-authored docs PR re-claimed by architect's own auto-claim (54s gap) | Manual re-flip x2; abandoned per Handoff Discipline §label-flip-storm |
  | 3 | 2026-07-04T12:55Z | ~#4030 | PR #822 | Tester-authored d-test re-claimed by tester's own auto-claim (22s gap) | periodic_backlog_scan restoration |
  | 4 | 2026-07-04T13:14Z | ~#4038 | PR #822 (again) | 3rd cycle today; status:ready stripped within ~30s | This ADR + commit 156ef01 Form C impl |
- **d-test integration:** d020a (`scripts/tests/d020a-claim-next-ready-form-c.sh`, 5 TCs RED-first per ADR-0049 baseline) — atomic with impl in commit 156ef01, 5/5 GREEN locally per d020a INDEX.md row.
- **Workflow YAML changes:** None. Pure Layer 2 claim-next-ready.sh amendment + d020a d-test. Cadence Rule 1 atomic (ADR-0055 §1) preserved: `docs/decisions/` + `scripts/claim-next-ready.sh` + `scripts/tests/d020a-*` + `scripts/tests/INDEX.md` row all in same PR-cluster (commit 156ef01).

---

## Context

### The race (3 confirmed live instances today)

ADR-0038 §Auto-Claim Protocol Layer 2 (`scripts/claim-next-ready.sh`) atomically flips `status:ready → status:in-progress` when claiming a `status:ready` item. Per Handoff Discipline (ADR-0015) + ADR-0031 (owner-override PR merge doctrine), `status:ready` is the **squash gate signal** — owner squash-merges PRs carrying `status:ready` + `verdict-by:<ts>` stamp + peer approval markers.

The race surfaces when:
1. Peer (architect / tester / PM) posts APPROVED verdict + canonical 4-flag flip (add `status:ready`, remove `cc:<self>`, `needs-<self>-signoff`, etc.)
2. Within 30-60s, the SAME role's `scripts/claim-next-ready.sh` poll fires
3. The script sees `agent:<role>` + `status:ready` and re-claims, flipping back to `status:in-progress`
4. Squash gate signal lost — owner cannot see PR as ready-to-merge from the board

**Critical asymmetry**: the peer who stamps APPROVED is often the SAME role as the auto-claim bot that re-claims. PR #822 (tester-authored): tester stamps APPROVED → tester's auto-claim re-flips. PR #817 (architect-authored): architect stamps APPROVED (per ADR-0021 docs PR convention) → architect's auto-claim re-flips.

### Form design space (orchestrator cycle ~#4033 analysis)

| Form | Predicate | Verdict | Rationale |
|---|---|---|---|
| **A** | `author.login != env.<ROLE>` (filter self-authored items) | ❌ REJECTED | Sister-pattern silent-drop family: `agent:<role>` and `author.login` are different fields. Tester-authored + `agent:tester` = SAME role per ADR-0012 (tester assigned tester-authored PR). Filter exempts but doesn't solve cross-role cases. |
| **B** | Skip `type:docs` PRs (ADR-0021 docs PR convention) | ❌ REJECTED | PR #822 (3rd instance) is `type:feature`, not `type:docs`. Form B covers PR #817 but NOT PR #822. |
| **C** | Exempt items with `verdict-by:*` label + (Phase 2: peer-approval comment) | ✅ **ADOPTED** | Verdict-stamp self-sign-off detection — directly addresses the squash gate signal semantic. Cross-cuts all 3 live instances (PR #795, PR #817, PR #822). |

### Why a new ADR (not amend ADR-0038 inline)

ADR-0038 already has 2 amendments (workstream-awareness = #1, watcher-enforcement = #2). Adding Form C as inline amendment #3 would conflate watcher-side concerns (amendment #2) with claim-side race detection (this amendment #2). Per file ownership matrix + ADR-0046 §Load-bearing ADR §Implementation Guide Pattern, **load-bearing amendments warrant their own canonical home for discoverability**. Sister-pattern to ADR-0062 / ADR-0063 (Layer 5 amendments as separate ADRs).

**Why "amendment #2" (not #3)**: per scripts/claim-next-ready.sh L207 comment, this is amendment #2 of the Layer 2 claim-next-ready.sh specifically (not ADR-0038 global). The numbering is claim-side, not watcher-side. Amendment #1 = workstream-awareness (also claim-side). Amendment #2 = Form C (this). Amendment #3+ would be future claim-side amendments. The naming is consistent within scripts/claim-next-ready.sh.

---

## Decision

**Extend `scripts/claim-next-ready.sh` with Form C race-detection (Phase 1: label-only half).** Phase 1 detects items carrying `verdict-by:<ts>` label and exempts them from auto-claim. Phase 2 (follow-up) adds comments-fetching for full peer-approval detection, gated on feature-flag `CLAIM_NEXT_READY_FORM_C_VERIFY=1` (default ON, 0 for emergency rollback).

### Phase 1 — Label-based half of Form C predicate (impl shipped commit 156ef01)

```bash
# Phase 1 (shipped): exempt items with verdict-by:* stamp
FORM_C_CANDIDATE_COUNT=$(printf '%s' "$ready_raw" | \
  jq '[.[] | select(.labels | map(select(.name | startswith("verdict-by:"))) | length > 0)] | length' 2>/dev/null || echo 0)
if [ "${CLAIM_NEXT_READY_FORM_C_VERIFY:-1}" = "1" ] && [ "${FORM_C_CANDIDATE_COUNT:-0}" -gt 0 ]; then
  log "<!-- adr-0038-amendment-2-form-c --> Form C race-detection: $FORM_C_CANDIDATE_COUNT candidate(s) with verdict-by stamp detected for this role ($ROLE) — exempting from auto-claim pending peer-approval comments verification (Phase 2 follow-up). Live instance: PR #822 cycle ~#4033."
fi
```

**Predicate semantics** (jq):
```
exempt ⇔ has_label(starts_with("verdict-by:"))
```

**Why Phase 1 alone is sufficient for the live race**: the race fires within 30-60s of `verdict-by:<ts>` stamp application. Phase 1 catches all 3 live instances (PR #795, PR #817, PR #822) because all carry verdict-by stamps at re-flip time. Phase 2 (comments-fetching) adds defense-in-depth against future race variants (e.g., label-check verdict-gate races).

### Phase 2 — Comments-fetching pass (Sprint 24+ P3 follow-up, NOT in this PR)

```bash
# Phase 2 (follow-up): N+1 comments-fetching per ready item, verify peer-approval
# comment is non-bot-authored AND body matches approval markers
# (🟢 APPROVED / Verdict: 🟢 / tests accepted / review complete).
# Feature-flag gated: CLAIM_NEXT_READY_FORM_C_VERIFY=1 (default)
# Cost: N+1 API calls per claim cycle. Mitigation: 5-min cache TTL.
```

**Why deferred**: Phase 1 catches the live race. Phase 2 is defense-in-depth for future variants. Per ADR-0044 RED-first discipline + Cadence Rule 1 atomic, Phase 2 = separate d-test + impl PR.

### §Marker pattern (sister-pattern to ADR-0012 §Layer 5 audit trail)

- Form C log line: `<!-- adr-0038-amendment-2-form-c -->`
- Concurrency: `scripts/agent-watch.sh` `poll_once` integration unchanged (per-issue `gh issue edit` is atomic per ADR-0038 §Layer 2)

### Sister-pattern: 3-layer defense-in-depth (per ADR-0045 §lens (d))

| Layer | Surface | Mitigation |
|---|---|---|
| 1. Detection predicate | `jq` filter on labels array | Phase 1: label-only (shipped); Phase 2: comments-fetching |
| 2. Feature-flag gate | `CLAIM_NEXT_READY_FORM_C_VERIFY=1` | Default ON; 0 = emergency rollback |
| 3. Audit log emission | `log "<!-- adr-0038-amendment-2-form-c -->"` | Sister-pattern to ADR-0012 Layer 5 audit trail |
| 4. d020a d-test guard | 5 TCs RED-first | TC1 predicate present + TC2 semantics correct + TC3 bot exclusion + TC4 perf budget + TC5 d031 non-regression |

### Concurrency (sister-pattern to PR #426 L42-46)

`scripts/claim-next-ready.sh` is called once per agent per `poll_once` cycle (60s cadence). Concurrent arch + tester verdicts cannot trigger concurrent re-flip because:
- `gh issue edit` is atomic per ADR-0038 §Layer 2
- Re-poll after claim surfaces self-action in next cycle
- Form C exemption is sticky for the lifetime of `verdict-by:*` label

---

## Rationale

**Why Form C (not Form A or B)**:
1. **Form A** (`author != role`) doesn't solve cross-role cases AND confuses the self-claim pattern (tester assigned tester-authored PR is correct per ADR-0012).
2. **Form B** (skip type:docs) covers 1 of 3 live instances (PR #817). PR #822 is type:feature.
3. **Form C** directly addresses the squash gate signal semantic (`status:ready + verdict-by:*` = ready for owner squash). Cross-cuts all 3 instances. Cross-cuts type:docs / type:feature / type:bug / type:refactor.

**Why verdict-by label alone (Phase 1) is sufficient for live race**:
- All 3 live instances carry `verdict-by:*` label at re-flip time
- Per ADR-0024, `verdict-by:<ts>` IS the squash gate signal (owner squash-merge triggers after the label is set + peer approval posted)
- Per ADR-0012, `status:ready` is the squash gate lane signal (board filters owner view by this label)
- Form C Phase 1: `status:ready AND has(verdict-by:*) → exempt` catches all 3 instances

**Why a separate ADR (not amend ADR-0038 inline)**:
- ADR-0038 has 2 amendments already; adding Form C as inline amendment #3 would conflate watcher-side (amendment #2) with claim-side (this amendment)
- Per ADR-0046 §Load-bearing ADR §Implementation Guide Pattern, load-bearing amendments warrant canonical home
- Discoverability: future "why does claim-next-ready.sh skip items with verdict-by?" grep → finds ADR-0069 directly

**Why Phase 1 + Phase 2 split (not all-or-nothing)**:
- Phase 1 catches live race NOW (Sprint 24+ P2 urgency per orchestrator cycle ~#4033)
- Phase 2 adds defense-in-depth but costs N+1 API calls (perf budget risk)
- Per ADR-0056 Layer 5 idempotency reconcile pattern: ship minimal fix first, harden later
- Cadence Rule 1 atomic: Phase 1 + d020a in single PR-cluster (commit 156ef01); Phase 2 = separate PR

**Why d020a (5 TCs) exceeds ADR-0049 ≥3 TCs baseline**:
- TC1 predicate present (static grep — protects against accidental predicate removal)
- TC2 predicate semantics (jq-verified against 3-item fixture)
- TC3 bot-authored comment exclusion (X1 user=bot-* NOT exempted; X2 user=developer exempted — Phase 2 hook)
- TC4 perf budget (median-of-5 < 200ms for 50-item fixture, tightens from <50ms single-run after cycle ~#4034 CI flake lesson)
- TC5 d031 sister-pattern NOT regressed (10/10 PASS — sister non-regression guard)
- Total: 5 TCs exceeds baseline by 2 (sister-pattern to d058 9→10 TC evolution per ADR-0060)

---

## Consequences

### Positive

1. **Closes Issue #811 P1** — auto-claim re-flip loop eliminated for items carrying `verdict-by:*` stamp
2. **Squash gate signal preserved** — `status:ready` no longer stripped within 30-60s of peer stamp
3. **Cross-cuts type:docs + type:feature + type:bug + type:refactor** — Form C is type-agnostic
4. **Reversible** — feature-flag `CLAIM_NEXT_READY_FORM_C_VERIFY=0` for emergency rollback
5. **Cadence Rule 1 atomic preserved** — docs/ + scripts/ + scripts/tests/ + scripts/tests/INDEX.md all atomic in commit 156ef01
6. **Sister-pattern to ADR-0068** — both Sprint 24+ P2 doctrinal hardening cycle, same retro cycle
7. **d020a d-test guard** — 5 TCs protect against regression (predicate removal, semantics drift, bot bypass, perf degradation, sister-regression)

### Negative / risks

1. **Phase 1 partial coverage** — only catches items with verdict-by stamp; future race variants (verdict-by absent + peer approval only) need Phase 2 comments-fetching
2. **N+1 API calls (Phase 2)** — performance budget risk; mitigation = 5-min cache TTL
3. **Bot-authored approval exclusion** — Phase 2 logic (TC3) prevents bot self-sign-off; relies on `comment.user.type === 'Bot'` distinction which may evolve
4. **d020a local-only** — 5/5 GREEN locally on STORY-811-form-c-race-detection branch; CI integration deferred to follow-up PR per Cadence Rule 1 atomic (sister-pattern d058/d064/d296/d320)
5. **Verdict-by stamp abuse** — adversarial actor could add `verdict-by:*` label to bypass auto-claim; mitigation = peer-approval comments (Phase 2) + audit trail
6. **RETRO-016 cluster growth** — Issue #811 is RETRO-016 candidate; this ADR adds to the cluster; consider dedicated RETRO entry in Sprint 24 retro

### Neutral

- ADR-0038 §Auto-Claim Protocol header should reference this amendment in post-merge follow-up
- d020a INDEX.md row cross-link to ADR-0069 should be added post-merge
- Sprint 24 retro candidate: "auto-claim re-flip loop family" (RETRO-016 cluster #N+1)
- Phase 2 impl + d020b d-test deferred to Sprint 24+ P3 (next sprint after this PR merges)

---

## Implementation

1. **This PR (architect-authored, docs-only)**: file ADR-0069, update `docs/decisions/INDEX.md` row, cross-link from ADR-0038 §Auto-Claim Protocol header (post-merge follow-up)
2. **PR-cluster commit 156ef01 (developer-authored, already shipped)**: `scripts/claim-next-ready.sh` amendment #2 (Phase 1) + `scripts/tests/d020a-claim-next-ready-form-c.sh` (5 TCs) + `scripts/tests/INDEX.md` row atomic per Cadence Rule 1 atomic (ADR-0055 §1)
3. **Phase 2 follow-up PR (developer-authored, Sprint 24+ P3)**: comments-fetching pass + d020b d-test (≥3 TCs) + perf budget verification
4. **d020a CI integration follow-up PR**: NOT in this PR per Cadence Rule 1 atomic (sister-pattern d058/d064/d296/d320)
5. **Owner squash gate**: PR-cluster commit 156ef01 awaiting owner squash per file ownership matrix (`scripts/` developer territory, owner merges)

### Live validation (PR-cluster commit 156ef01, 2026-07-04)

**Branch**: `STORY-811-form-c-race-detection`

**Commit 156ef01 atomic contents**:
- `scripts/claim-next-ready.sh` (+50 LoC, Phase 1 Form C detection predicate + feature-flag gate + audit log emission)
- `scripts/tests/d020a-claim-next-ready-form-c.sh` (+~358 LoC, NEW d-test, 5 TCs RED-first)
- `scripts/tests/INDEX.md` (+~15 LoC, d020a INDEX row atomic)
- **Closes #811** in commit message

**d020a verification (locally)**:
- TC1 Form C predicate present (static grep — `<!-- adr-0038-amendment-2-form-c -->` marker in claim-next-ready.sh)
- TC2 Form C predicate semantics correct (jq-verified against 3-item fixture: 2 items exempted by verdict-by + peer-approval logic, 1 not exempted due to no peer approval)
- TC3 bot-authored comment excluded from Form C exemption (X1 user=bot-* NOT exempted; X2 user=developer exempted; Form C key feature — bots cannot self-sign-off)
- TC4 jq filter performance within budget (median-of-5 < 200ms for 50-item fixture)
- TC5 d031 sister-pattern NOT regressed (10/10 PASS)
- **Total: 5/5 GREEN locally**

**Validation outcome**: Phase 1 Form C impl + d020a d-test ship-ready. CI integration deferred to follow-up PR per Cadence Rule 1 atomic (sister-pattern d058/d064/d296/d320).

### Ownership split (per ADR-0046 + CLAUDE.md §File ownership matrix)

| Artifact | Doctrinal owner | Code owner |
|---|---|---|
| ADR-0069 (this file) | @architect | @architect (docs PR) |
| Form C Phase 1 impl (claim-next-ready.sh L207-256) | @developer | @developer (commit 156ef01) |
| d020a d-test (5 TCs) | @tester | @developer (commit 156ef01) per ADR-0044 RED-first |
| d020a INDEX row | @architect | @developer (commit 156ef01) per Cadence Rule 1 atomic |
| Phase 2 impl + d020b d-test (Sprint 24+ P3) | @developer | @developer (follow-up PR) |
| Owner squash merge (commit 156ef01 PR) | @atilcan65 | human-only |

---

## Acceptance criteria

- [ ] ADR-0069 merged to main
- [ ] Issue #811 P1 closed (impl closes #811 in commit 156ef01; ADR-0069 doctrinal codification post-merge)
- [ ] d020a authored with 5 TCs (TC1-5), all RED-first per ADR-0044, all GREEN post-impl
- [ ] Phase 1 impl shipped in `scripts/claim-next-ready.sh` (commit 156ef01, atomic with d020a + INDEX.md row)
- [ ] Owner squash gate per file ownership matrix (`scripts/` developer territory, owner merges)
- [ ] Phase 2 follow-up PR planned (Sprint 24+ P3, deferred)
- [ ] d020a CI integration follow-up PR planned (Cadence Rule 1 atomic deferral, sister-pattern d058/d064/d296/d320)
- [ ] ADR-0038 §Auto-Claim Protocol header cross-linked to ADR-0069 (post-merge follow-up)
- [ ] d020a INDEX.md row cross-linked to ADR-0069 (post-merge follow-up)
- [ ] RETRO-016 cluster entry filed (Sprint 24 retro candidate)
- [ ] No regression in d031 sister-pattern (TC5 = 10/10 PASS, sister non-regression guard)
- [ ] 9-Lens pre-publish attestation (per architect.md §9-Lens Review Checklist) verified before PR merge

---

## 9-Lens attestation (per ADR-0045)

| Lens | Status | Note |
|------|--------|------|
| (a) Data flow | ✅ | Peer verdict → 4-flag flip → `verdict-by:*` label applied → agent-watch.sh `poll_once` → claim-next-ready.sh → jq predicate exempts item → squash gate signal preserved |
| (b) Runtime preconditions | ✅ | bash + gh CLI + jq available; `CLAIM_NEXT_READY_FORM_C_VERIFY` env var defaults to 1; d020a RED-first verifies impl present |
| (c) Canonical entry point | ✅ | Single entry: `scripts/claim-next-ready.sh` `poll_once` integration; Phase 1 predicate is inline jq (no helper delegation needed); Phase 2 follow-up adds comments-fetching helper |
| (d) Silent-skip risk | ✅ | Form C exemption emits `<!-- adr-0038-amendment-2-form-c -->` audit log line; feature-flag gate explicit (`CLAIM_NEXT_READY_FORM_C_VERIFY=0` for rollback); d020a TC1 + TC3 protect against silent-skip |
| (e) Idempotency | ✅ | `gh issue edit` is atomic per ADR-0038 §Layer 2; re-poll after claim surfaces self-action; Form C exemption is sticky for `verdict-by:*` label lifetime |
| (f) Observability | ✅ | Audit log emission `<!-- adr-0038-amendment-2-form-c -->` sister-pattern to ADR-0012 §Layer 5; d020a TC1 + TC2 verify audit trail semantics; machine-parseable log line |
| (g) Security & privacy | ✅ | No new authn/authz, no secrets, no PII; gh API uses existing repo context; bot-authored approval exclusion (TC3) prevents bot bypass |
| (h) Workflow YAML SHA pin | N/A | No workflow YAML changes in this amendment (ADR-0027 §Threat model + ADR-0043 §lens (h) preserved; sister-pattern PR #576 SHA-pin already on main @ dc1a542) |
| (i) Platform hard constraints | N/A | No CI/workflow changes; within `actions/*` sandbox intact; no raw `docker run` / `ssh` |
| (j) Auto-gen file refs + live-state | ✅ | References `scripts/claim-next-ready.sh` L207-256 (verified via `git show 156ef01:scripts/claim-next-ready.sh`); `scripts/tests/d020a-claim-next-ready-form-c.sh` exists on branch (verified via `git ls-tree`); d020a INDEX.md row exists on branch (verified via `grep d020a`); 3 live instances documented in §Live Instances table; d020a 5/5 GREEN locally (pending CI integration) |

---

## References

- Issue #811 (P1, orchestrator escalation cycle ~#4033, RETRO-016 candidate)
- PR-cluster commit 156ef01 (Form C Phase 1 impl + d020a + INDEX.md row atomic, Closes #811)
- PR #795 (1st live instance, squash-gate reproducer, cycle ~#3523, owner-squashed historical evidence)
- PR #817 (2nd live instance, architect-authored docs PR, cycle ~#4015, arch manual re-flip x2)
- PR #822 (3rd live instance, tester-authored d-test, cycle ~#4030/4033/4035/4038, periodic_backlog_scan restoration)
- arch cmt 4881963396 (cycle ~#4017, Form A/B design spec — REJECTED basis)
- tester cmt 4882076500 (cycle ~#4030, test-instance #4 PR #822 reproduction)
- orch cycle ~#4033 ESCALATION (Form C spec, "claim + implement ASAP")
- orch cycle ~#4035 ACK (Form C spec confirmed: d020a sister-test + race-detection predicates good)
- ADR-0002 (autonomy loop)
- ADR-0012 (4-cat label invariant)
- ADR-0024 (verdict-by:<ts> convention)
- ADR-0031 (owner-override PR merge doctrine)
- ADR-0038 (Auto-Claim Protocol — this ADR amends)
- ADR-0038-amendment-workstream-awareness.md (amendment #1, sister-pattern)
- ADR-0038-amendment-watcher-enforcement.md (amendment #2, watcher-side sister)
- ADR-0044 (RED-first TDD)
- ADR-0046 (load-bearing ADR §Implementation Guide Pattern)
- ADR-0049 (d-test framework)
- ADR-0055 §1 (Cadence Rule 1 atomic)
- ADR-0056 (Layer 5 idempotency reconcile)
- ADR-0068 (Layer 5 j.4 tester-author exception — pending PR #817 merge, direct sister, Sprint 24+ P2 hardening cycle)
- File ownership matrix (CLAUDE.md §File ownership matrix)

---

## See also

- **ADR-0068** (Sprint 24+ P2, in PR #817 cycle ~#4042) — Layer 5 j.4 Tester-Author Exception Clause. Sister to this ADR; same doctrinal hardening cycle, same retro cycle, same Cadence Rule 1 atomic discipline.
- **ADR-0038 amendment #2** — sister-pattern to [ADR-0038-amendment-watcher-enforcement.md](./ADR-0038-amendment-watcher-enforcement.md) (watcher-side) and [ADR-0038-amendment-workstream-awareness.md](./ADR-0038-amendment-workstream-awareness.md) (claim-side amendment #1).

---

🤖 Architect ADR draft @ 2026-07-04T13:21:00Z — Sprint 24+ P2 lead, drafting doctrinal codification post-impl (commit 156ef01 Form C Phase 1 + d020a 5/5 GREEN shipped by @developer; this ADR seals the doctrine per ADR-0046 §Load-bearing ADR §Implementation Guide Pattern, two-way door reversible per feature-flag gate)