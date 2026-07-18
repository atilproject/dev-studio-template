# ADR-0055: d-test ID uniqueness invariant + sub-pattern remediation matrix (codifies Issue #551)

- **Status**: Proposed
- **Date**: 2026-06-27
- **Deciders**: @architect (doctrine/spec), @developer (d-test family extension + Cadence Rule 1 enforcement), @tester (d059 TC5 STRICT INVARIANT sign-off — already implemented in PR #544), @product-manager (Sprint 16 P1 workshop ratification), @atilcan65 (owner squash gate)
- **Closes**: Issue #551 (RETRO-010 §18 NEW, arch-promoted per PR #547 cmt 4820973931 + PR #548 §18)
- **Sister-patterns**: ADR-0049 (d050b behavioral workflow test framework), ADR-0050 (d053 pre-merge 4-cat verification), ADR-0053 (Layer 5 race pattern codification), ADR-0054 (d055 9-Lens enforcement), RETRO-009 §6 (d-test family drift home, RESOLVED Sprint 15 chain), Issue #533 (batch d-test INDEX drift findings)

> **Doctrine reference note**: PR #548 §18 entry (PM-authored, RETRO-010 catalog) references "ADR-0049 §ID uniqueness invariant" — this reference is INCORRECT. ADR-0049 is the "Behavioral Workflow Test Framework" (d050b), not the d-test ID uniqueness codification. The ID uniqueness invariant is currently embedded in d046/d048/d050b/d051/d052/d053/d054/d056/d057/d059 family ADRs (ADR-0050-0054) but has no canonical home. **This ADR-0055 codifies the invariant for the first time + adds sub-pattern remediation matrix.**

## Context

### Sprint 15 §6 drift home (RETRO-009) — RESOLVED via 5-PR sequential chain

Sprint 15 cluster surfaced 2 d-test ID-collision instances in RETRO-009 §6 drift home (originally `drift home: post-squash #530/#536`):

| ID | Files | Pattern | Resolution PR |
|----|-------|---------|---------------|
| d031 | `d031-claim-next-ready.sh` + `d031-claim-next-ready-stub.sh` | 1 impl + 1 stub (legacy shadowed) | PR #545 (delete the stub) |
| d046 | `d046-expansion-adr-0044-literal-form.sh` + `d046-js-syntactic-check.sh` + `d046-peer-poke-canonical-parity.sh` | 3 functional impls (genuine work) | PR #541 (rename to d046a/b/c) |

**Both instances resolved** in Sprint 15 sequential Option A chain (PR #536 → PR #541 → PR #544 → PR #545 → PR #547), confirmed by PR #547 (RETRO-009 §6 cross-ref, my arch 🟢 verdict cmt 4820973931).

### Pattern observed: distinct sub-patterns require distinct remediation paths

The 2 instances had **different sub-patterns**:

- **d031×2** = 1 impl + 1 stub → **delete** the stub (arch Option B verdict, simplest remediation)
- **d046×3** = 3 functional impls → **rename** to d046a/d046b/d046c (Cadence Rule 1 atomic per docs/index-cadence.md §1, preserves the work)

**Architectural gap**: ADR-0049 (d050b framework) does not codify ID uniqueness as a doctrine invariant. ADR-0050 (d053) references "ADR-0012 4-cat invariant" but no d-test ID uniqueness invariant has a canonical home. d059 TC5 STRICT INVARIANT (PR #544) implements the check at the d-test level but does not elevate it to doctrine.

### Pattern validation across Sprint 13-15

The ID uniqueness invariant has been **empirically validated** across 3 sprints:

- **Sprint 13**: d046/d048/d050b/d051/d052 (5-sister d-test framework, no collisions)
- **Sprint 14**: + d053/d054/d056/d057 (9-sister framework, no collisions — RETRO-008 §6 confirms)
- **Sprint 15**: d031×2 + d046×3 violations surfaced, resolved via 5-PR sequential chain

**Sprint 15 d046→d046a/b/c rename** established a sub-pattern codification precedent — the precedent exists, but the doctrine does not.

## Decision

Adopt **ADR-0049 §ID uniqueness invariant** + **§Sub-pattern remediation matrix** as the canonical d-test ID collision doctrine. This ADR-0055 codifies what ADR-0049 was incorrectly referenced as having, and adds the missing remediation matrix.

### §ID uniqueness invariant (codified)

**Rule**: Every d-test ID in the `FAMILY_IDS` set (d046, d048, d050b, d051, d052, d053, d054, d055, d056, d057, d058, d059, d031, d060, d061, etc.) maps to **exactly 1 file** under `scripts/tests/`. Violations are STRICT INVARIANT FAIL — no exceptions, no whitelist.

**Doctrine level**: **invariant not policy** (RETRO-010 #19 NEW, codification per Issue #539 cmt + PR #544 arch refinement). Sister-pattern to ADR-0012 §4-cat invariant (invariant, not policy, enforced via label-check workflow).

**Enforcement**: d059 TC5 STRICT INVARIANT (PR #544 squash @ 4b3b42c) + Cadence Rule 1 atomic (docs/index-cadence.md §1 — every d-test impl/add = INDEX.md update in same PR) + architect 9-Lens (j) auto-gen file refs + live-state verification (per ADR-0045).

### §Sub-pattern remediation matrix (NEW)

When the ID uniqueness invariant is **violated**, the remediation path depends on the sub-pattern:

| Sub-pattern | Symptom | Remediation | Example |
|-------------|---------|-------------|---------|
| **A** | 1 impl + 1 stub (legacy shadowed) | **Delete** the stub | d031×2 → PR #545 (Issue #537) |
| **B** | N functional impls (genuine work) | **Rename** to a/b/c with Cadence Rule 1 atomic | d046×3 → PR #541 (Issue #539) |
| **C** | N+M mixed (some impl, some stub) | **Arch lane decision** per-case (Option A or B based on case breakdown) | (hypothetical — not yet observed) |

**Why sub-pattern matters**: A single remediation rule (e.g., "always delete") would either destroy legitimate work (Sub-pattern B violation) or leave the invariant perpetually violated (Sub-pattern A violation with "rename" rule applied to stub). The sub-pattern matrix lets the architect choose the right tool for the case.

### §Cadence Rule 1 atomic (refined)

Per docs/index-cadence.md §1 (PR #532 §1 codification): every d-test impl/add/rename/delete = INDEX.md update in **same PR** (atomic). This applies to:

- New d-test file added → INDEX.md row added in same PR
- d-test file renamed → INDEX.md row updated in same PR
- d-test file deleted → INDEX.md row removed in same PR
- d-test ID split (sub-pattern B) → INDEX.md updated for all new IDs in same PR

**Sister-pattern**: d046×3 → d046a/b/c rename in PR #541 (single commit `231047d`, 3 renames + 1 INDEX.md 3-row split + 3 cross-ref lines = atomic).

### §Verification: d059 TC5 STRICT INVARIANT (already implemented)

The verification mechanism exists at PR #544 (squash @ 4b3b42c, arch 🟢 verdict cmt 4819508452):

```bash
# d059 TC5 (paraphrased from PR #544 impl)
for ID in "${FAMILY_IDS[@]}"; do
  count=$(find scripts/tests/ -name "${ID}-*.sh" | wc -l)
  if [[ "$count" -ne 1 ]]; then
    echo "FAIL: ID=$ID has $count files (expected 1)"
    exit 1
  fi
done
```

**No whitelist** (acknowledged_collisions map was dropped per PR #544). Sister-pattern to RETRO-010 #19 NEW codification (invariant not policy).

### §Workflow YAML guard (proposed — owner merge required)

Per file ownership matrix, `.github/workflows/` is human-only territory. The following CI integration is **proposed** for owner merge:

- **CI trigger**: `paths: scripts/tests/d059-**` OR `paths: scripts/tests/d046-**` OR `paths: scripts/tests/d031-**`
- **Action**: Run d059 self-test on every PR that touches d-test files
- **Failure mode**: TC5 RED → label-check FAIL → squash-block

**Owner gate**: this requires a new workflow file OR amendment to `.github/workflows/lint-and-test.yml`. Per CLAUDE.md §File ownership matrix + ADR-0031 owner-override doctrine, architect + tester draft, owner merges.

## Rationale

### Why invariant not policy

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **Invariant** (this ADR) | Single rule, no exceptions, d-test enforces | Requires sub-pattern remediation matrix (more doctrine) | ✅ Adopt |
| Policy (whitelist) | Simple impl | Permits violations via exception lists (PR #544 already removed whitelist — REJECTED) | ❌ Rejected |
| Lint-only (no enforcement) | Cheapest | Drift home re-occurs (Sprint 15 §6 evidence) | ❌ Rejected |
| Manual review only | Zero tooling | Sprint 15 caught 2 instances after merge — too late | ❌ Rejected |

### Why sub-pattern matrix (not single rule)

A single rule (e.g., "always rename") would have:

- **Applied to d031×2**: rename `d031-claim-next-ready-stub.sh` → `d031a-stub-legacy.sh` → preserves dead code forever, invariant still violated (1 ID : 2 files unless rename ALSO changes ID)

Wait — actually if rename changes ID, the original ID has only 1 file (the impl) and the new ID has 1 file (the stub). But then the stub is still in scripts/tests/, still executable, still d-test-like. **The stub needs to be deleted, not renamed, because it's a shadowed legacy artifact.**

- **Applied to d046×3**: delete 2 of the 3 impls → destroys legitimate work

**Single rule cannot serve both sub-patterns**. Sub-pattern matrix is necessary.

### Why d059 TC5 (not a new d-test)

d059 (d-test family persistence) already exists per PR #536 (squash @ 77acc1d) + PR #544 (TC5 STRICT INVARIANT). Adding TC5 STRICT INVARIANT to d059:

- Avoids new d-test proliferation (currently 9-sister family, this keeps it stable)
- Reuses existing CI integration (d059 already CI-integrated)
- Sister-pattern to d046/d048/d050b/d051/d052/d053/d054/d055/d056/d057 → keeps 9-sister pattern

A new d-test (e.g., d062-id-uniqueness-check) would expand the family to 10-sister unnecessarily.

## Consequences

### Positive

- **Doctrinal home for ID uniqueness**: ADR-0055 codifies what ADR-0049 was incorrectly referenced as having. Issue #551 closes cleanly.
- **Sub-pattern codification**: future d-test ID collisions (Sprint 16+) have a documented remediation matrix. Sister-pattern: RETRO-009 §6 lineage expansion (PR #541, PR #547).
- **Invariant not policy**: whitelist pattern (PR #536 originally) is now doctrinally rejected. Sister-pattern: ADR-0012 4-cat invariant.
- **Cadence Rule 1 atomic**: refined in this ADR for all d-test impl/add/rename/delete operations.

### Negative

- **CI integration deferred**: workflow YAML change requires owner merge. Until owner merges, d059 TC5 is locally-enforced only.
- **Sub-pattern C unvalidated**: the N+M mixed case has no observed instances yet. If Sprint 16+ surfaces a sub-pattern C instance, arch lane decision is required per-case.
- **INDEX.md maintenance burden**: Cadence Rule 1 atomic adds 1-3 lines per d-test PR. Mitigated by `scripts/index-cadence.sh` automation (planned Sprint 16+).

### Sprint boundary

- `docs/decisions/ADR-0055-*.md` (this file) = **architect** lane (doctrine)
- `scripts/tests/d059-dtest-family-persistence.sh` (TC5 STRICT INVARIANT impl) = **developer + tester** joint — **already shipped via PR #544**
- `.github/workflows/lint-and-test.yml` (paths trigger refinement for d059) = **human-only** territory (architect + tester draft, owner merges per file ownership matrix)
- Issue #551 priority flip + label transitions = **PM** lane

## Alternatives considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **ADR-0055 (this file)** | Codifies invariant + matrix, closes Issue #551, no impl change needed | Doctrine-only (workflow YAML gate deferred to owner) | ✅ Adopt |
| Amend ADR-0049 | Could append to existing behavioral framework | ADR-0049 is about d050b, not ID uniqueness — semantically wrong home | ❌ Rejected |
| Amend ADR-0050 (d053) | Sister to d-test framework | d053 is pre-merge 4-cat verification, not ID uniqueness — different concern | ❌ Rejected |
| New d-test (d062) | Forces CI integration via new file | d059 already does the check; new d-test inflates family | ❌ Rejected |
| No ADR (use Issue #551 as living doc) | No ceremony | Doctrine must be in ADRs per ADR-0017 tech stack + INDEX.md conventions | ❌ Rejected |

## Open questions

- [ ] **Q1**: Workflow YAML gate — does owner prefer new file (`.github/workflows/d059-self-test.yml`) OR amendment to `lint-and-test.yml` paths trigger? (Owner decides per ADR-0031)
- [ ] **Q2**: Sub-pattern C remediation — should the matrix specify "arch lane decides based on case breakdown" (current draft) OR force a default (e.g., "prefer delete over rename for safety")? (Architect + PM workshop discussion in Sprint 16 P1)
- [ ] **Q3**: Should ADR-0049 INDEX.md entry be amended to clarify it does NOT contain §ID uniqueness (prevent future doctrine reference errors like PR #548 §18)? (Arch lane, low-priority follow-up)

## References

- **Issue #551** (RETRO-010 §18 NEW) — this ADR's container, arch-promoted per PR #547 cmt 4820973931
- **Issue #533** (batch d-test INDEX drift findings) — sub-pattern A + B origin
- **Issue #537** (d031×2 historical drift remediation) — sub-pattern A carrier
- **Issue #539** (d046×3 file rename) — sub-pattern B carrier
- **PR #541** (d046×3 rename, squash @ 6369633) — Cadence Rule 1 atomic carrier
- **PR #544** (d059 TC5 STRICT INVARIANT, squash @ 4b3b42c) — invariant impl, arch refinement cmt 4819508452
- **PR #545** (d031 stub retire, squash @ e8ff51a) — sub-pattern A impl, arch Option B verdict cmt 4819491495
- **PR #547** (RETRO-009 §6 cross-ref, my arch 🟢 verdict cmt 4820973931) — promotion-lane confirmation
- **PR #548** (RETRO-010 Sprint 15 codifications catalog, §18 entry) — this ADR's filing trigger (PM-authored, arch-promoted)
- **ADR-0012** — 4-cat invariant (invariant not policy sister-pattern)
- **ADR-0017** — Tech stack (Python + pytest, d-test framework territory)
- **ADR-0045** — 9-Lens (j) auto-gen file refs + live-state verification
- **ADR-0049** — Behavioral Workflow Test Framework (d050b) — NOT the ID uniqueness home (doctrine reference error in PR #548 §18)
- **ADR-0050** — d053 pre-merge 4-cat verification (sister d-test framework)
- **ADR-0054** — d055 9-Lens enforcement (sister d-test framework)
- **RETRO-009 §6** — d-test family drift home (Sprint 14-15 lineage)
- **RETRO-010 #18 NEW** — sub-pattern codification (this ADR's predecessor)
- **RETRO-010 #19 NEW** — invariant not policy codification
- **docs/index-cadence.md §1** — Cadence Rule 1 atomic

## §9-Lens Review Checklist (doctrinal self-application)

| Lens | Status | Note |
|------|--------|------|
| (a) Data flow | ✅ | Doctrine-only ADR, no runtime data flow. ID uniqueness invariant verifiable via d059 TC5 → scripts/tests/ filesystem scan → INDEX.md cross-ref. |
| (b) Runtime preconditions | ✅ | d059 TC5 pre-flight: bash + find + grep (sister-pattern d058/d060). No new deps. |
| (c) Canonical entry point | ✅ | Single ADR file, no side-channels. |
| (d) Silent-skip risk | ✅ | STRICT INVARIANT = no skip paths, no whitelist (PR #544 removed whitelist). |
| (e) Idempotency | ✅ | Read-only filesystem scan + grep. Idempotent re-runs. |
| (f) Observability | ✅ | PASS/FAIL binary output + section headers + colored output (TTY-aware). |
| (g) Security & privacy | N/A | bash filesystem scan, no auth/PII surface |
| (h) Workflow YAML SHA pin | N/A | no workflow changes in this ADR (workflow YAML change deferred to owner per file ownership matrix) |
| (i) Platform hard constraints | ✅ | Pure bash + find + grep. No platform changes. |
| (j) Auto-gen file refs + live-state | ✅ | INDEX.md is auto-gen (Cadence Rule 1 carrier); TC9 verifies live-state; FAMILY_IDS references live files. |
| (k) JS syntactic correctness | N/A | no JS in this ADR |

— @architect, 2026-06-27T20:30+03:00, ADR-0055 d-test ID uniqueness invariant + sub-pattern remediation matrix (Sprint 16 P1 Tier 1 candidate, closes Issue #551, arch lane doctrine)
