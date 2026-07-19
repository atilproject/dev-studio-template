# ADR-0024 Amendment: Work-Done-Elsewhere Predicate Spec (silent-skip canonical for 4-cat-repair)

- **Status:** Proposed (Issue #166 codification, Lane 2 architect docs/decisions/)
- **Date:** 2026-07-19
- **Deciders:** @architect (doctrine spec, docs/decisions/ lane per file ownership matrix)
- **Parent ADR:** [ADR-0024](./ADR-0024-stale-verdict-watchdog-schema.md) — Stale-Verdict Watchdog Schema + 4-cat-label-invariant
- **Amends:** ADR-0024 §4-cat-label-invariant by codifying the work-done-elsewhere **predicate spec** (canonical filter pattern for 4-cat-repair helpers + sister-pattern codification)
- **Closes:** Issue #166 Lane 2 (architect docs/decisions/ lane)
- **Sister-patterns:** [ADR-0024-amendment-auto-verdict-by-hook](./ADR-0024-amendment-auto-verdict-by-hook.md) (auto-pair on `cc:<peer>` add — same family, §4 silent_skip contract), [ADR-0024-amendment-stale-verdict-supersede](./ADR-0024-amendment-stale-verdict-supersede.md) (multi-label canonical max-timestamp, Issue #828 — same family)
- **Related:** Issue #1027 (RETRO-024 canonical doctrine, CLOSED 2026-07-13 — this amendment ratifies the predicate spec); Issue #1081 (Lane 1 script bug — RETRO-024 filter too aggressive); PR #1165 (Lane 1 SQUASH-MERGED sha `6d9779f` at 2026-07-19T04:37:05Z — implements the predicate in `scripts/claim-next-ready.sh`); Issue #154 (S32-025 apply-vm-hardening port — live instance that exposed the bug at cycle ~#3468)

---

## Context

ADR-0024 §4-cat-label-invariant codifies the four-category label requirement (`type:*`, `status:*`, `agent:*`, `cc:*`). RETRO-022 (predecessor) established that the invariant is satisfied by `agent:* OR status:done OR (status:ready + cc:human + NO agent:*)`. RETRO-024 (Issue #1027, CLOSED 2026-07-13) ratified the work-done-elsewhere terminal state pattern but did **NOT** codify the **filter predicate** for 4-cat-repair helpers.

**Live instance** (Issue #1081, cycle ~#3468):

- Manual claim of Issue #154 (S32-025 apply-vm-hardening port) bypassed `scripts/claim-next-ready.sh` because the RETRO-024 work-done-elsewhere filter incorrectly rejected all 5 ready items in the dev queue.
- **Root cause**: `scripts/claim-next-ready.sh` line ~423 filters ANY issue with `cc:human` label as work-done-elsewhere, **ignoring the `(NO agent:*)` constraint**.
- **Impact**: every `agent:developer + status:ready` story with `cc:human` (the canonical pre-merge gate per ADR-0012 §Handoff Label Discipline) gets silent-skipped.
- **Fix**: PR #1165 SQUASH-MERGED at sha `6d9779f` with explicit predicate extension.

This amendment closes **Issue #166 Lane 2** (architect docs/decisions/ lane) by codifying the canonical filter predicate that PR #1165 implements. The implementation is in code; the **predicate spec** belongs in doctrine so future 4-cat-repair helpers (orchestrator hygiene loops, post-PR label normalization, reflexive invariant-repair, silent-skip filters) MUST follow the same canonical pattern.

---

## Decision

**§Work-Done-Elsewhere Predicate** — amend ADR-0024 §4-cat-label-invariant with the following canonical filter pattern:

### 1. Canonical predicate spec

The work-done-elsewhere terminal state is identified by the **conjunction (AND)** of:

```
type:<*>        present (any type label)
status:ready    present (literal — terminal of cross-repo workstream)
cc:human        present (literal — owner-merge-gate signal)
agent:<*>       ABSENT (NO agent:* label — the distinguishing constraint)
```

Predicate (canonical bash form, sister to PR #1165 implementation in `scripts/claim-next-ready.sh`):

```bash
# is_work_done_elsewhere <labels_json_array>
# Returns 0 if labels match the RETRO-024 work-done-elsewhere pattern, 1 otherwise.
is_work_done_elsewhere() {
    local labels_json="$1"
    local has_type=$(echo "$labels_json" | jq '[.[] | select(.name | startswith("type:"))] | length > 0')
    local status_is_ready=$(echo "$labels_json" | jq '[.[] | select(.name == "status:ready")] | length > 0')
    local has_cc_human=$(echo "$labels_json" | jq '[.[] | select(.name == "cc:human")] | length > 0')
    local has_no_agent=$(echo "$labels_json" | jq '[.[] | select(.name | startswith("agent:"))] | length == 0')

    if [[ "$has_type" == "true" && "$status_is_ready" == "true" \
          && "$has_cc_human" == "true" && "$has_no_agent" == "true" ]]; then
        return 0  # work-done-elsewhere
    fi
    return 1
}
```

The same predicate in jq (single-expression form, useful for inline filter):

```jq
. as $labels
| ($labels | map(select(.name | startswith("type:"))) | length > 0) as $has_type
| ($labels | map(select(.name == "status:ready")) | length > 0) as $status_is_ready
| ($labels | map(select(.name == "cc:human")) | length > 0) as $has_cc_human
| ($labels | map(select(.name | startswith("agent:"))) | length == 0) as $has_no_agent
| $has_type and $status_is_ready and $has_cc_human and $has_no_agent
```

### 2. Sister-pattern codification

**Any future 4-cat-repair helper** (orchestrator hygiene loop, post-PR label normalization, reflexive invariant-repair, silent-skip filter) **MUST** use the canonical predicate above.

**Single-label `cc:human` check is INSUFFICIENT and DEPRECATED** as a work-done-elsewhere indicator. It is a **RETRO-024 anti-pattern violation** to use single-label `cc:human` as the sole distinguishing criterion.

Mandatory checks (in this order, all four required):

1. `type:*` label present (any type — `type:feature`, `type:chore`, `type:bug`, etc.)
2. `status:ready` label present (literal)
3. `cc:human` label present (literal)
4. **NO `agent:*` label present** — the actual distinguishing constraint

Any implementation that omits constraint #4 MUST be flagged in code review per **ADR-0045 §Lens (d) Silent-skip risk** as a **RETRO-024 anti-pattern violation** (sister-class to Issue #798 verdict-authority false-positive + Issue #828 stale_verdict hook false-positive).

### 3. Audit trail

When the predicate matches a work-done-elsewhere issue, the 4-cat-repair helper MUST emit a `silent_skip` log event per **ADR-0024-amendment-auto-verdict-by-hook §4 contract**:

```
silent_skip: issue=#<n> reason=work-done-elsewhere labels=[type:<*>,status:ready,cc:human,no-agent:*]
```

This preserves observability for post-mortem analysis without triggering wake loops or peer-poke noise.

### 4. Cross-cutting guarantees

- **No breaking change** to existing RETRO-024 terminal states — predicate is a **no-op** when constraint #4 (NO `agent:*`) fails.
- **Pre-merge stories protected** — `agent:developer + status:ready + cc:human` is **NOT** silent-skipped (the post-PR-#1165 fix).
- **Sister-pattern codified** — Issue #798 verdict-authority false-positive, Issue #828 stale_verdict hook false-positive, Issue #1081 RETRO-024 filter false-positive all share the root cause: predicate logic that **omits the distinguishing constraint**.
- **Cross-ADR alignment** — predicate spec aligns with `CLAUDE.md §Work-done-elsewhere terminal state` (RETRO-024 / Issue #1027) AND `ADR-0012 §Handoff Label Discipline` (atomic 4-flag hand-off).
- **Idempotent** — pure predicate (no side effects on issue state); safe to call multiple times.

---

## Alternatives considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **A. Full predicate spec (this amendment)** — 4-condition AND with explicit distinguishing constraint | Codifies canonical pattern; future 4-cat-repair helpers MUST use it; observability via silent_skip log; sister-pattern with PR #1165 implementation | Slightly more verbose than single-label check; requires amendment doc | **ADOPTED** |
| **B. Single-label `cc:human` check** — pre-fix implementation in `scripts/claim-next-ready.sh` line ~423 | Simplest implementation | **Insufficient** — silent-skips pre-merge stories (the live instance bug from cycle ~#3468); violates RETRO-024 canonical pattern | **REJECTED** (current bug) |
| **C. Strict AND of `cc:human + status:done`** — semantic shortcut | Tight scope; one less constraint to check | `status:done` is for OWNER terminal hand-off (post-merge); work-done-elsewhere uses `status:ready` per RETRO-024 (pre-merge tracked-elsewhere) | **REJECTED** (semantic mismatch) |
| **D. Regex-based label-set match** — `^(type:.*,)?(status:ready,)?(cc:human,)?(?!(agent:.*,))` | Concise | Harder to debug; silent failure modes on edge cases (e.g., `agent:human` vs `agent:developer` prefix collision); observability cost | **REJECTED** (observability cost) |
| **E. Comment-only documentation in `scripts/claim-next-ready.sh`** — inline explanation | Zero new doc | Does not codify for sister-pattern; future helpers at filing time would not have the canonical reference | **REJECTED** (doctrinal gap) |

---

## Consequences

### Positive outcomes

1. **Doctrinal closure** — RETRO-024 work-done-elsewhere terminal state now has explicit **predicate spec**; future 4-cat-repair helpers MUST follow the same canonical pattern.
2. **Sister-pattern family consolidation** — Issue #798 + Issue #828 + Issue #1081 = 3-cluster predicate-false-positive family. This amendment completes the doctrinal codification triad; future helpers inheriting the bug class will be caught at code review per ADR-0045 §Lens (d).
3. **Live-instance root cause fixed at architecture level** — PR #1165 fixed the implementation; this amendment fixes the **doctrine** so the same bug class can't recur in future helpers.
4. **Cross-ADR cross-link** — ADR-0024 §4-cat-label-invariant + ADR-0012 §Handoff Label Discipline + ADR-0038 §Auto-Claim + Issue #1027 (RETRO-024) all linked via this amendment.
5. **Audit trail codified** — `silent_skip` log line per predicate match enables post-mortem analysis (lens (f) Observability green).

### Negative tradeoffs

1. **Migration cost** — any existing 4-cat-repair helper using single-label `cc:human` check MUST be updated. PR #1165 fixed `scripts/claim-next-ready.sh`; future helpers at filing time MUST follow this spec (caught at code review).
2. **Slight verbosity** — 4-condition AND vs single-label check. Acceptable per observability + correctness gain.
3. **Cross-repo port** — this amendment lands in tmpl first (Issue #166 scope); calc-side port is a follow-up (see Follow-up #4).

### Follow-up tickets to file

1. **d-test sister-pattern** (optional) — `scripts/tests/d-XXX-retro-024-predicate-spec.sh` — codify the predicate spec as a regression pin per ADR-0049 + ADR-0044. (Optional — the canonical predicate is short enough to verify by code review; PR #1165 already has its own d-test per Issue #1081 close path.)
2. **INDEX.md update** (conditional) — `scripts/tests/INDEX.md` row if d-test #1 is filed (Cadence Rule 1 atomic per ADR-0055 §1).
3. **Umbrella ADR-0038-amendment-3** (deferred) — this + ADR-0024-amendment-auto-verdict-by-hook + ADR-0024-amendment-stale-verdict-supersede = 3 sibling races under one umbrella. Defer to next sprint backlog.
4. **calc-side port** — sister amendment needed in atilproject/AtilCalculator `docs/decisions/`. File as Issue #166 follow-up after this amendment lands in tmpl (separate PR per cluster-squash cadence).
5. **CLAUDE.md §Work-done-elsewhere cross-link** — add 1-line reference to this amendment in `CLAUDE.md` §Work-done-elsewhere terminal state (propose via PR per file ownership matrix; CLAUDE.md is human-only source → auto-rendered by init script per ADR-0013 + ADR-0050).

---

## 9-Lens Pre-Publish Attestation (per architect.md §9-Lens Review Checklist)

> **Note**: the "9-Lens" checklist is a composite of multiple ADRs — lenses (a)–(g) per `.claude/agents/architect.md` §9-Lens Review Checklist, lens (h) Workflow YAML SHA pin per ADR-0027, lens (i) Platform hard constraints per ADR-0043, lens (j) Auto-generated file refs + live-state verification per ADR-0045. There is no single "ADR-0045 9-Lens pre-publish gate" ADR; the prior reference was doctrinally imprecise (corrected cycle #4108).

| Lens | Verdict | Note |
|---|---|---|
| (a) Data flow | ✅ GREEN | predicate operates on label set; observable via `gh issue view --json labels`; no hidden state |
| (b) Runtime preconditions | ✅ GREEN | no new deps; `jq` + `bash` existing in `scripts/`; pure predicate (no side effects) |
| (c) Canonical entry point | ✅ GREEN | single canonical predicate (bash + jq forms); no side-channel implementations; sister-pattern with PR #1165 implementation |
| (d) Silent-skip risk | ✅ GREEN | explicit `silent_skip` log emit per amendment-auto-verdict-by-hook §4 contract; lens (d) guard codified; **anti-pattern documented** (single-label `cc:human` check flagged at code review) |
| (e) Idempotency | ✅ GREEN | pure predicate (no side effects on issue state); safe to call multiple times; deterministic |
| (f) Observability | ✅ GREEN | `silent_skip` log line per predicate match; live-state verification via gh API on Issue #166 + Issue #1027 + Issue #1081 |
| (g) Security & privacy | ✅ GREEN | no PII; no secrets; labels are public per ADR-0012 4-cat invariant |
| (h) Workflow YAML SHA pin | ✅ GREEN | no workflow YAML change required; existing `label-check.yml` already SHA-pinned per ADR-0027 + TD-028 sister-pattern |
| (i) Platform hard constraints | ✅ GREEN | no platform changes; documentation-only amendment; pure bash + jq |
| (j) Auto-generated file refs + live-state verification | ✅ GREEN | HAND-WRITTEN amendment; live-state verified via gh API on Issue #166 (state=open, agent:architect, status:in-progress) + Issue #1027 (state=closed, RETRO-024 ratified) + Issue #1081 (Lane 1 script bug closed via PR #1165) |

**Net**: 10 GREEN, 0 RED, 0 needs-mitigation. Doctrinally + operationally ready.

---

## Cross-references

- [ADR-0024](./ADR-0024-stale-verdict-watchdog-schema.md) (parent — stale-verdict watchdog schema + 4-cat-label-invariant)
- [ADR-0024-amendment-auto-verdict-by-hook](./ADR-0024-amendment-auto-verdict-by-hook.md) (sister amendment — auto-pair on `cc:<peer>` add, §4 silent_skip contract)
- [ADR-0024-amendment-stale-verdict-supersede](./ADR-0024-amendment-stale-verdict-supersede.md) (sister amendment — multi-label canonical max-timestamp, Issue #828)
- [ADR-0012](./ADR-0012-4-cat-label-invariant.md) (4-cat label invariant — Handoff Label Discipline)
- [ADR-0038](./ADR-0038-auto-claim-protocol.md) (Auto-Claim protocol — `claim-next-ready.sh` parent)
- ADR-0044 (text-only — RED-first TDD doctrinal home, no link per fix cycle #4108)
- ADR-0049 (text-only — d-test framework, ≥5 TCs baseline + ≥3 sister-pattern, no link per fix cycle #4108)
- ADR-0045 (text-only — 9-Lens pre-publish checklist per architect.md, no link per fix cycle #4108)
- ADR-0013 (text-only — init-script rendering for `.tmpl` files, no link per fix cycle #4108)
- ADR-0050 (text-only — multi-project CLAUDE.md rendering, no link per fix cycle #4108)
- Issue #1027 (RETRO-024 canonical doctrine — CLOSED 2026-07-13, this amendment ratifies the predicate spec)
- Issue #166 (Sprint 32 Cadence Rule 2 dispatch — Lane 2 architect docs/decisions/ lane, this amendment closes it)
- Issue #1081 (Lane 1 script bug — RETRO-024 filter too aggressive; PR #1165 SQUASH-MERGED sha `6d9779f` at 2026-07-19T04:37:05Z)
- PR #1165 (Lane 1 SQUASH-MERGED — implements the predicate in `scripts/claim-next-ready.sh`)
- Issue #154 (S32-025 apply-vm-hardening port — live instance that exposed the bug at cycle ~#3468)
- RETRO-022 (text-only — original doctrine, predecessor to RETRO-024)
- RETRO-023 (text-only — cluster codification, predecessor to RETRO-024)
- Cycle ~#3468 (bug discovery — manual claim bypass revealed silent-skip over-filter)
- Cycle ~#3673 (this amendment's drafting cycle — picked up from orchestrator dual-channel dispatch)
- c3.71, c3.72, c3.74, c3.75, c3.78 (architect deferred umbrella ADR-0038-amendment-3 carrier notes)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
