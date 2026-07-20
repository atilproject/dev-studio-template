# ADR-0048 — `label-check.yml` Layer 5: `status:ready` Auto-Add Gating (Type-Driven Reviewer Chain)

- **Status:** Proposed (2026-06-26)
- **Date:** 2026-06-26
- **Deciders:** @architect (design) + @product-manager (business call) + @tester (d-test contract) + @developer (impl) + @atilcan65 (owner squash gate)
- **Supersedes:** none (extends ADR-0012 §Cascade-strip Part 2 with formal type-driven table + codifies Issue #425 spec)
- **Related:** ADR-0012 (Required Label Set), ADR-0012 §Cascade-strip Part 1 (PR #426), ADR-0012 §Cascade-strip Part 2 (this ADR codifies), ADR-0012 §Security note (PR #428), ADR-0021 (Docs PR Convention), ADR-0044 (TDD RED contract discipline), ADR-0046 (Load-bearing ADR §Implementation Guide Pattern), ADR-0047 (Cross-Repo Watcher sister), Issue #213 (TEST-WAKE-ENFORCE doctrine gap), Issue #393 (PR #393 canonical cascade-strip case — silent-skip observation), Issue #423 (Workflow Part 1 spec, PR #426 impl), Issue #425 (this ADR's trigger, PR #430 design doc), PR #426 (Layer 4 cascade-strip yaml, sister-pattern), PR #428 (§Security note sister-pattern), PR #430 (this ADR's design doc)

---

## Context

**Problem**: The `label-check.yml` workflow currently auto-adds `status:ready` on arch verdict alone (per PR #393 canonical case, 2026-06-25). For non-docs PRs (type:feature, type:bug, etc.), this prematurely signals "ready for owner merge gate" BEFORE the tester verdict lands. Owner sees `status:ready + cc:human` and may merge without tester signoff — breaking the tester's correctness principle (label-driven wake per ADR-0002) and bypassing defense-in-depth.

**Observed doctrine gap** (per Issue #393 §Problem):
- Arch verdict auto-cleanup added `status:ready` while `status:in-review` was still present
- The auto-add logic does NOT distinguish between docs PRs (arch verdict sufficient per ADR-0021) and non-docs PRs (tester verdict required per Issue #213 TEST-WAKE-ENFORCE doctrine gap)
- The tester's `needs-tester-signoff` label is the canonical reviewer-chain gate; auto-add of `status:ready` should NOT fire until that gate clears

**Constraint**: The fix MUST be additive to the existing Layer 1-4 cascade (do not regress PR #426 Part 1 scope-tightening) and MUST respect ADR-0021 docs PR convention (arch verdict alone sufficient for docs PRs).

---

## Decision

**Extend `label-check.yml` with Layer 5 (NEW) — type-driven `status:ready` auto-add gating.** Layer 5 reads the PR `type:*` label + reviewer chain state (presence of `needs-tester-signoff` / `needs-architect-review` / `cc:tester` / `cc:architect` / `cc:human`) and decides whether to auto-add `status:ready` based on the type-driven table below.

### Type-driven reviewer chain table (canonical)

| `type:*` value | Required cleared state for `status:ready` auto-add | ADR reference |
|---|---|---|
| `type:docs` + `agent:architect` | `needs-architect-review` removed by arch verdict — NO tester prereq (docs PR convention) | ADR-0021 |
| `type:docs` + `agent:product-manager` | PM verdict posted — NO tester prereq (docs PR convention extends to PM author) | ADR-0021 + Issue #430 PM NIT-1 ack |
| `type:docs` + `agent:orchestrator` | Orchestrator verdict posted — NO tester prereq (sister-pattern to arch) | ADR-0021 + Issue #430 §Sister-pattern |
| `type:bug` | `needs-tester-signoff` cleared by tester APPROVED verdict (arch verdict alone INSUFFICIENT) | Issue #213 TEST-WAKE-ENFORCE |
| `type:feature` | `needs-tester-signoff` cleared by tester APPROVED verdict (arch verdict alone INSUFFICIENT) | Issue #213 + ADR-0002 |
| `type:refactor` | `needs-tester-signoff` cleared by tester APPROVED verdict | Issue #213 |
| `type:chore` | `needs-tester-signoff` cleared by tester APPROVED verdict | Issue #213 |
| `type:incident` | `needs-tester-signoff` cleared by tester APPROVED verdict (URGENCY: tester signoff can be post-hoc for live incidents) | ADR-0012 §Type-driven invariants |
| All other / unknown `type:*` | Default to non-docs path (tester prereq) — defensive default | ADR-0012 §Type-driven invariants §Enforcement |

### Pseudocode (for owner-approved workflow update)

```yaml
# pseudocode for Layer 5 status:ready auto-add gating
if (pr_type == "type:docs" AND agent in [architect, product-manager, orchestrator]):
    # docs PR convention — no tester prereq
    if (needs-architect-review is ABSENT OR pm_verdict_posted OR orch_verdict_posted):
        gh_pr_add_label("status:ready")
        gh_pr_remove_label("status:in-review")  # atomic transition (sister-pattern to PR #428)
        create_audit_comment(marker="adr-0012-status-ready-gating", reason="docs PR, arch/PM/orch verdict sufficient")
    else:
        # Silent skip — log audit comment with skip marker
        create_audit_comment(marker="adr-0012-status-ready-gating-skip", reason="docs PR but no verdict yet")
elif (pr_type in [type:bug, type:feature, type:refactor, type:chore, type:incident]):
    # Non-docs — tester prereq mandatory
    if (needs-tester-signoff is ABSENT):
        gh_pr_add_label("status:ready")
        gh_pr_remove_label("status:in-review")  # atomic transition
        create_audit_comment(marker="adr-0012-status-ready-gating", reason="non-docs PR, tester verdict posted")
    else:
        # Silent skip — log audit comment with skip marker
        create_audit_comment(marker="adr-0012-status-ready-gating-skip", reason=f"non-docs PR, tester prereq missing (needs-tester-signoff present)")
else:
    # Unknown type — default to non-docs path (defensive)
    if (needs-tester-signoff is ABSENT):
        gh_pr_add_label("status:ready")
        gh_pr_remove_label("status:in-review")
        create_audit_comment(marker="adr-0012-status-ready-gating", reason="unknown type, default non-docs path")
    # else: skip
```

### Marker pattern (sister-pattern to PR #426 + PR #428)

- Success: `<!-- adr-0012-status-ready-gating -->`
- Skip (silent-skip event per ADR-0012 §d lens): `<!-- adr-0012-status-ready-gating-skip -->`
- Fail-check (Q5a sister-pattern from PR #426): `<!-- adr-0012-status-ready-gating-error -->`

Idempotency via `comments.find(c => c.user.type === 'Bot' && c.body.includes(marker))` (sister-pattern to PR #426 Layer 4).

### Sister-pattern: 5-layer defense-in-depth (PR #428 §Security note)

Layer 5 inherits the 5-layer defense-in-depth pattern from PR #428:

| Layer | Surface | Mitigation |
|---|---|---|
| 1. Trigger scope | `pull_request_target` event | Consistent with Layers 1-4 |
| 2. Code checkout | NO `actions/checkout` of PR head ref | Prohibited (pwn-request mitigation) |
| 3. Token scope | Top-level `permissions:` block (contents:read, issues:write, pull-requests:write) | Minimum scope enforced |
| 4. Script-only execution | `actions/github-script@v7` only (no shell, no `child_process`) | All mutations via `github.rest.*` |
| 5. Audit trail | Marker pattern + idempotent bot-attributed comments | Sister-pattern to PR #426 + PR #428 |

### Concurrency (sister-pattern to PR #426 L42-46)

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.event.issue.number }}
  cancel-in-progress: false
```

Prevents race conditions when arch + tester verdict posted simultaneously. Serializes per PR/issue.

---

## Rationale

**Why type-driven (not universal) gating**:
1. **Docs PR convention (ADR-0021)** — owner-merge-gated by default; tester signoff NOT required. Applying universal tester prereq would block legitimate docs PRs.
2. **Tester correctness principle (Issue #213)** — non-docs PRs need tester verdict before owner merge gate. Tester's `needs-tester-signoff` is the canonical gate.
3. **Type-driven is well-defined** — `type:*` is already a required label (ADR-0012), so the type-driven table is a strict superset of existing labels (no new label required).

**Why a new ADR (not amend ADR-0012)**:
- ADR-0012 §Cascade-strip Part 2 already references "type-driven table" but does NOT codify it (per Issue #394 follow-up + PR #424 §Part 1 clarification)
- The type-driven table is LOAD-BEARING — it determines the auto-add logic, which is the primary fix for the PR #393 regression
- Per ADR-0046 §Load-bearing ADR §Implementation Guide Pattern, load-bearing ADRs warrant their own file for traceability

**Why Layer 5 (NEW, not extension of Layer 4)**:
- Layer 4 (PR #426) = cascade-strip Part 1 (scope-tightening of duplicate status:* removal)
- Layer 5 (this ADR) = status:ready auto-add gating (NEW logic, different concern)
- Per ADR-0046 §Sister-pattern: separation of concerns = easier d-test, easier peer review, easier rollback

**Alternatives considered**:

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **A) Layer 5 NEW (this ADR)** | Sister-pattern to PR #426; clean separation; easier d-test | One more step (~30 LoC) | ✅ **Adopted** |
| **B) Extend Layer 4 with Layer 5 logic** | Single workflow step; less code | Conflates cascade-strip (Part 1) with status:ready gating (Part 2) — different concerns; harder to d-test | ❌ Rejected (separation of concerns) |
| **C) Universal tester prereq for ALL `status:ready` auto-adds** | Simplest impl; symmetric | Blocks docs PRs (per ADR-0021, no tester signoff required) | ❌ Rejected (breaks ADR-0021) |
| **D) No auto-add — only manual flip to `status:ready`** | No regression risk | Breaks PR-merge-atomicity for owner; agent burden | ❌ Rejected (loses PR #393 fix) |
| **E) Implement Layer 5 in `scripts/agent-watch.sh` (orchestrator domain)** | Different code path | Per file ownership matrix, `scripts/` = developer territory | ❌ Rejected (doctrinal ownership split) |
| **F) PM verdict extension to docs PRs (Issue #430 PM NIT-1) — codify as 2nd row in type-driven table** | Reflects docs PR convention extends to PM author | None — natural extension | ✅ **Adopted** (per PM NIT-1 ack) |

---

## Consequences

### Positive

1. **Closes PR #393 regression** — non-docs PR `status:ready` auto-add now respects tester prereq
2. **Respects tester's correctness principle** (Issue #213) — `needs-tester-signoff` is canonical reviewer-chain gate
3. **Preserves docs PR convention** (ADR-0021) — arch/PM/orch verdict sufficient for docs PRs
4. **Sister-pattern with PR #426** — same marker pattern, concurrency block, Q5a fail-check, Q5b early-return, audit trail template
5. **5-layer defense-in-depth preserved** (PR #428 §Security note cross-link) — all 5 layers maintained
6. **Discovered via Issue #393 + RETRO-005 family** — doctrinal feedback loop, not architect-imposed
7. **PM verdict extension documented** (Issue #430 PM NIT-1) — docs PR convention extends to PM author

### Negative / risks

1. **d-test mandatory before impl** — 3 minimum TCs (TC1: docs PR + arch verdict → status:ready; TC2: non-docs + tester verdict → status:ready; TC3: non-docs + arch verdict alone → status:ready NOT auto-added) per ADR-0044 TDD RED discipline. TC4 bonus (reversal handler) per DEV verdict ack.
2. **Cascade-strip Part 1 conflict** (Risk R5 from Issue #425 design) — atomic transition `status:in-review → status:ready` MUST be remove-first-then-add (gh batches into one PATCH, sister-pattern to PR #428)
3. **Concurrency race** (Risk R3) — arch + tester verdict posted simultaneously. Mitigated by per-PR concurrency block (sister-pattern to PR #426)
4. **Silent-skip observability** — when reviewer chain incomplete, Layer 5 emits `silent_skip` audit event with marker variant `adr-0012-status-ready-gating-skip` (per ADR-0012 §d lens + Issue #213 silent-skip doctrine gap)
5. **Label lifecycle** — `needs-tester-signoff` / `needs-architect-review` removal triggers Layer 5 re-evaluation. Concurrent labels (3+) trigger Q5a fail-check.
6. **Unknown type defensive default** — falls back to non-docs path (tester prereq). May block PRs with unusual `type:*` values. Non-blocking — owner can override via PR body rationale per ADR-0012 §Owner override.

### Neutral

- ADR-0012 §Cascade-strip Part 2 type-driven table reference should be updated to point to this ADR (post-merge follow-up)
- Issue #393 PR will need re-validation against new logic (regression test)
- RETRO-006 candidate: "type-driven auto-add vs universal auto-add" (doctrinal lesson learned)

---

## Implementation

1. **This PR (architect-authored)**: file ADR-0048, update `docs/decisions/INDEX.md` row, cross-link from ADR-0012 §Cascade-strip Part 2
2. **Owner-gated workflow update** (per file ownership matrix `.github/workflows/` = human-only territory): owner implements Layer 5 in `label-check.yml` per the pseudocode above, AFTER peer reviews + d-test GREEN
3. **Orchestrator handoff** (peer awareness): update `scripts/agent-watch.sh` `query_stale_verdict` to recognize `adr-0012-status-ready-gating-skip` audit events (sister-pattern to PR #426 audit trail)
4. **Developer companion** (Sprint 11 P2): d-test (tester-authored per ADR-0044) MUST pass before impl PR opens
5. **PM-spec ratification** (Issue #425 PM owner): already given via Issue #430 PM verdict 🟢

### Live validation (PR #446, 2026-06-26T16:18Z) — FIRST live PR

**First live PR to exercise the full silent-skip → success chain** (per §Consequences §4 silent-skip observability pattern):

- **Silent-skip phase**: cmt 4811369157 — `action=unlabeled, label=cc:architect` triggered Layer 5 silent-skip (reviewer chain incomplete on arch verdict). Marker: `<!-- adr-0012-status-ready-gating-skip -->`. Audit body per §Marker pattern emitted with Type=`type:docs`, Agent=`agent:developer`, Decision=`skip status:ready auto-add (reviewer chain incomplete)`.
- **Success phase**: cmt 4811415708 — `action=labeled, label=status:ready` triggered Layer 5 success auto-add (reviewer chain cleared after arch verdict). Marker: `<!-- adr-0012-status-ready-gating -->`. Audit body per §Marker pattern emitted with Decision=`addLabel('status:ready') + removeLabel('status:in-review') (atomic transition, sister-pattern PR #428)`.

**Validation outcome**: Type-driven table worked exactly as designed. Silent-skip → success chain observed end-to-end on a live PR. Sister-pattern to PR #426 canonical case (Issue #423 Part 1 application, 2026-06-25).

**Known refinement candidate** (🟡 OBS, RETRO-007 follow-up, NOT blocking): silent-skip reason text "non-docs PR (type=type:docs)" is internally contradictory — for type:docs, ADR-0048 §Type-driven reviewer chain table says arch verdict alone is sufficient. Recommend differentiating:
- Docs-path skip: "type:docs PR, arch verdict not yet posted (arch prereq missing)"
- Non-docs-path skip: "non-docs PR (type=bug/feature/refactor/chore/incident), tester signoff not yet posted (tester prereq missing)"

Workflow yaml Layer 5 silent-skip reason text fix is owner-gated per file ownership matrix (`.github/workflows/` = human-only territory). Sprint 12 P2 candidate per PM disposition (cmt 4811432966 ratifies).

### Ownership split (per ADR-0046 + CLAUDE.md §File ownership matrix + Issue #319 §Implementation step 3)

| Artifact | Doctrinal owner | Code owner |
|---|---|---|
| ADR-0048 (this file) | @architect | @architect (docs PR) |
| Design doc (Issue #425, PR #430) | @architect | @architect (docs PR) |
| d-test TCs (TC1/2/3/4) | @tester | @tester (per ADR-0044) |
| Workflow impl (Layer 5 yaml) | @developer | @developer (impl PR) |
| Owner squash merge | @atilcan65 | human-only |

---

## Acceptance criteria

- [ ] ADR-0048 merged to main
- [ ] Issue #425 closed (this ADR is the doctrinal deliverable for Issue #425 AC #2)
- [ ] d-test authored by @tester with 3 minimum TCs (TC1/2/3) + TC4 bonus, all RED
- [ ] Workflow impl PR by @developer makes all 4 TCs GREEN (TDD)
- [ ] Owner approval per file ownership matrix (`.github/workflows/` = human-only territory; this ADR is the architect-authored doctrine/spec, owner approves + merges the workflow impl PR)
- [ ] PR #393 regression test added to d-test TC4 (reversal handler)
- [ ] ADR-0012 §Cascade-strip Part 2 cross-link updated to reference this ADR (post-merge follow-up)
- [ ] 5-layer defense-in-depth pattern preserved (PR #428 §Security note cross-link)
- [ ] No regression in Part 1 cascade-strip behavior (PR #426 pattern preserved)

---

## References

- Issue #393 (PR #393 canonical cascade-strip case — silent-skip observation)
- Issue #213 (TEST-WAKE-ENFORCE doctrine gap — 3-layer solution)
- Issue #423 (Workflow Part 1 spec, PR #426 impl)
- Issue #425 (this ADR's trigger, PR #430 design doc)
- Issue #430 (PR #430 PM NIT-1 — PM verdict extension for docs PRs)
- PR #393 (canonical cascade-strip case)
- PR #426 (Layer 4 cascade-strip yaml, sister-pattern)
- PR #428 (ADR-0012 §Security note, sister-pattern + 5-layer defense-in-depth)
- PR #430 (this ADR's design doc, peer-merged 3/3 🟢)
- ADR-0012 §Cascade-strip Part 1 + Part 2 (doctrine spec — Part 2 codifies here)
- ADR-0012 §Security note (5-layer defense-in-depth, PR #428)
- ADR-0012 §Type-driven invariants (Issue #213 3-layer solution)
- ADR-0021 (Docs PR Convention — owner-merge-gated by default)
- ADR-0044 (TDD RED contract discipline — tester authors d-test)
- ADR-0046 (Load-bearing ADR §Implementation Guide Pattern — sister)
- ADR-0047 (Cross-Repo Watcher — sister ADR)
- File ownership matrix: CLAUDE.md §File ownership matrix (`.github/workflows/` = human-only; ADR = architect-owned)

---

## Amendment: Layer 5 Label-Change Event Verdict-Gate Extension

- **Status:** Proposed (amendment — folded into this ADR per ADR-0057 §amendment-via-parent; canonical home = this section)
- **Date:** 2026-06-30
- **Origin:** Sprint 22 P2 doctrine hardening (RETRO-016 #5 cluster)
- **Closes (calc-side):** Issue #696 (PR #695 LIVE INSTANCE — `status:ready` false-positive on 🔴 verdict)
- **Source (calc canonical):** [AtilCalculator ADR-0062-amendment-layer-5-label-change-verdict-gate.md](https://github.com/atilcan65/AtilCalculator/blob/main/docs/decisions/ADR-0062-amendment-layer-5-label-change-verdict-gate.md) — folded into this section on tmpl per ADR-0057 §amendment-via-parent pattern. NOTE: tmpl standalone `ADR-0062-*.md` file does NOT exist (will be removed from tmpl INDEX.md); amendment lineage trace via `ADR-0062` reference in this section.
- **Sister-patterns:** ADR-0057 (amendment-via-parent), ADR-0056 (Layer 5 idempotency reconcile, WARN-not-FAIL proven), ADR-0012 (cascade-strip Part 1 + Part 2 + Part 2.5 sibling amendment)

### Amendment decision

Extend Path A's verdict-emoji check (in §Implementation above) from `pull_request_target` events at `opened`/`reopened` action to **all `cc:<peer>` and `needs-*-signoff` label-change events** (`labeled` action on label name matching the patterns).

### Triggering LIVE INSTANCE (RETRO-016 #5 carrier)

**PR #695** (2026-06-29, tester triage cmt 4835036231):
- 16:52:18Z — PR-creation path: Layer 5 Path A verdict-emoji gate correctly REFUSED (no `status:ready`)
- 16:56:42Z — Label-change path: tester delivered 🔴 CHANGES REQUESTED verdict; tester flipped labels per tester.md table: `--remove-label needs-tester-signoff --remove-label cc:tester --add-label cc:developer`
- 16:56:52Z — Layer 5 saw: `needs-tester-signoff` absent + `cc:developer` present → "reviewer chain complete" → auto-ADDED `status:ready` (**FALSE POSITIVE** — verdict was 🔴)
- 16:57:14Z — Dev manually re-ADDED `status:in-review`
- 16:57:23Z — Layer 5 cascade-strip removed `status:ready` (correct outcome, wrong reason — should have been verdict-emoji check, not cascade-strip)

**Net pathology**: `status:ready` was added on a 🔴 verdict PR, signaling "ready for owner merge gate" when in reality the reviewer was asking for changes. Owner could have merged broken code.

### Amendment rationale

The original Path A binding (PR-creation events only) closed the PR #655 + #657 pathology but left label-change events unguarded. A 🔴 verdict followed by an atomic label flip (`needs-tester-signoff` remove + `cc:developer` add) is **functionally a `pull_request_target` event** semantically — Layer 5 SHOULD treat it identically.

### Amendment implementation diff

In the §Implementation `if:` clause, add an `issues` event binding (PR-creation path remains as-is):

```yaml
# Original (PR-creation only):
on:
  pull_request_target:
    types: [opened, reopened, synchronize]

# Amendment (PR-creation + label-change):
on:
  pull_request_target:
    types: [opened, reopened, synchronize]
  issues:
    types: [labeled]
```

Filter to `cc:*` or `needs-*-signoff` label events via the same verdict-emoji gate (path gate + label name regex). WARN-not-FAIL maintained per ADR-0056.

### Amendment acceptance criteria

- AC1: Layer 5 reads verdict emoji from PR `comments[]` on `issues` event when label matches `cc:*` or `needs-*-signoff`
- AC2: If verdict 🔴 on label-change path, Layer 5 does NOT auto-add `status:ready` (cascade-strip path remains as fallback)
- AC3: d-test `d164-s32-027-b-deferred.sh` TC2 verifies this section exists + references `ADR-0062` for lineage

### Amendment references

- Issue #696 (RETRO-016 #5 origin)
- PR #695 (LIVE INSTANCE)
- ADR-0062 (calc canonical amendment file — folded here, NOT ported as standalone tmpl file)
- ADR-0057 (§amendment-via-parent — fold pattern codification)
- ADR-0056 (Layer 5 idempotency reconcile, WARN-not-FAIL proven)
- ADR-0012 (cascade-strip Part 1 + Part 2; sibling amendment Part 2.5 also folded)
- RETRO-016 #5 (Issue #696, origin carrier)

---

## See also

- **ADR-0046** (Sprint 9 P1, PR #409 in-review) — Load-Bearing ADR §Implementation Guide Pattern. Sister to this ADR; provides §A literal jq filter, §B ownership-split decision tree, §C companion-ADR template. Cited because this ADR is load-bearing (codifies type-driven table that determines auto-add logic).
- **ADR-0047** (Sprint 10 P2, PR #420 MERGED) — Cross-Repo Watcher Architecture. Sister-pattern to this ADR (both authored as part of Sprint 10/11 P2 doctrinal codification).

---

🤖 Architect ADR draft @ 2026-06-26T11:10Z — Sprint 11 P2 lead, drafting in parallel with PR #430 owner squash (two-way door, reversible if PR #430 owner requests design changes)
