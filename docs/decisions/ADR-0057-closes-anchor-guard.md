# ADR-0057: Closes-anchor guard — codify parser-friendly issue close formats (closes Issue #560 AC1, RETRO-010 #33 NEW Bug variant)

- **Status**: Accepted (ratified 2026-07-07 cycle ~#5079 per Issue #877 Phase 2 v1.0.0 audit; was Sprint 16 P1 doctrine hardening workshop, Closes Issue #560 AC1; 6-sprint adoption window validated)
- **Date**: 2026-06-28
- **Deciders**: @architect (doctrine/spec), @developer (label-check.yml parser-friendly integration — owner merge required), @tester (d-test framework integration), @product-manager (Sprint 16 P1 workshop ratification per Issue #560 kickoff), @atilcan65 (owner squash gate)
- **Sister-patterns**: ADR-0015 (atomic 4-flag handoff = terminal hand-off fallback), ADR-0045 (9-Lens (j) auto-gen file refs + live-state), ADR-0056 (Layer 5 idempotency reconcile — cheaper fix sister-pattern), RETRO-010 #33 NEW (false-positive auto-add codification cluster)
- **PM framing**: PM PICKUP-41 dispatch (Issue #560 kickoff, cycle 243) — "Closes-anchor guard (GitHub '+' parser limitation, LIVE INSTANCE PR #554 manual close)"

> **Doctrine reference note**: This ADR codifies a **parser-friendly Closes anchor doctrine** for the FIRST time. The `+` separator limitation was discovered LIVE in PR #554 squash (2026-06-27T21:08:31Z, Issue #546 + Issue #551 manual close via ADR-0015 terminal hand-off — Closes anchor with `+` separator NOT recognized by GitHub's auto-close parser). This ADR-0057 prevents future recurrences via canonical format guidance + verification.

## Context

### RETRO-010 #33 NEW codification candidate — Closes-anchor parser limitation

Sprint 15 PR #554 squash (cycle 229, 2026-06-27T21:08:31Z) surfaced a **GitHub parser limitation** for multi-issue Closes anchors in PR bodies. The root cause:

| Action | Expected by arch | Actual GitHub behavior |
|--------|------------------|------------------------|
| Body text: `Closes: Issue #546 + Issue #551` | Both issues auto-close on PR squash | Only #546 closes; #551 manual `gh issue close` required |
| Anchor format: `Closes #546 + #551` | Same as above | Same — `+` is not a valid separator in GitHub's Closes anchor parser |

**GitHub-recognized Closes anchor formats** (verified per docs):

1. **Single keyword, comma-separation**: `Closes #1, #2, #3` ✅
2. **Multiple keywords**: `Closes #1, Closes #2, Closes #3` ✅ (verbose but explicit)
3. **Multi-line keywords**: each on own line, any of `Closes`/`Fixes`/`Resolves` ✅
4. **Single issue, single keyword**: `Closes #1` ✅ (baseline)

**Non-recognized formats**:

- `Closes #1 + #2` ❌ (PR #554 LIVE INSTANCE)
- `Closes #1 and #2` ❌ (no documented recognition)
- `Closes: #1 + #2` ❌ (colon does not enable `+`)

### LIVE INSTANCE: PR #554 squash (cycle 229)

PR #554 squash @ `1456d97` (2026-06-27T21:08:31Z) had the following body Closes anchor (cycle 223 edit, Option (a) attribution decision):

```
**Closes**: Issue #546 (Sprint 16 P1 doctrine hardening workshop, RETRO-010 #34 NEW) **+ Issue #551** (RETRO-010 §18 NEW, sub-pattern codification — closes via PR #554 subsumption of PR #553, see attribution note below)
```

**GitHub auto-close result**: ❌ Only #546 closed (the `+` separator prevented parser recognition of #551 as a Closes target).

**Manual recovery**: orchestrator executed ADR-0015 terminal hand-off via `gh issue close 551` (cycle 229 ORCH action), per Option (a) attribution decision rationale (cmt 4821647280).

### Pattern validation across Sprint 14-15

The Closes-anchor parser limitation has been **observed empirically** in 1 LIVE INSTANCE (PR #554), but the **risk surface is broader**:

- **Future PRs** that subsume multiple issues (e.g., PR #556-style close-outs covering 5+ Issues) MUST use parser-friendly formats
- **PM-led retro/close-out PRs** (like PR #556, Sprint 15 PM-lane close-out) are highest-risk for parser failures because they list many Issues in a single body
- **Architect-led doctrine PRs** (like PR #554) carry the same risk when subsuming older PR scope (PR #554 subsumed PR #553)

### Why this matters for Sprint 16 P1 doctrine hardening workshop

PM PICKUP-41 dispatch (Issue #560 kickoff) identified Closes-anchor guard as **AC1** of the 2-ADR workshop scope (after PM EXTENSION v5 MERGE reduced 4-ADR → 2-ADR). The risk is **silent attribution loss**: if `gh issue close` is not executed as fallback, issues that SHOULD close via PR squash remain open, breaking attribution chains.

## Decision

Adopt **parser-friendly Closes anchor formats** as the canonical doctrine for multi-issue PR bodies. This ADR-0057 codifies:

### §Parser-friendly Closes anchor formats (canonical)

**Rule**: All PR bodies that close multiple Issues MUST use one of the following parser-friendly formats:

| Format | Example | Verdict |
|--------|---------|---------|
| **Comma-separation** | `Closes #1, #2, #3` | ✅ **Adopt (preferred)** |
| **Multiple keywords** | `Closes #1, Closes #2, Closes #3` | ✅ Adopt (verbose but explicit) |
| **Multi-line keywords** | `Closes #1\nCloses #2\nCloses #3` | ✅ Adopt (one per line) |
| **Single issue, single keyword** | `Closes #1` | ✅ Adopt (baseline) |

**Rejected formats** (doctrinally):

| Format | Example | Why rejected |
|--------|---------|--------------|
| `+` separator | `Closes #1 + #2` | **PR #554 LIVE INSTANCE** — parser does NOT recognize |
| `and` separator | `Closes #1 and #2` | No documented recognition; risk of partial recognition |
| `,` with prose | `Closes #1, Issue #2, #3` | Parser recognizes the leading `#N`, not subsequent `Issue #N` |

### §Verification pattern (canonical)

**Pre-squash verification step** (architect lane, before owner squash):

1. List all Closes anchor variants in PR body (`grep -E '^(\*\*)?Closes'`)
2. Verify each `#N` is on a line that begins with a recognized keyword (`Closes`/`Fixes`/`Resolves`)
3. For each `#N`, confirm Issue is OPEN in tracker (`gh issue view N --json state`)
4. **If any Issue is OPEN after squash**: execute ADR-0015 terminal hand-off (`gh issue close N --reason "PR #M squash, attribution via PR body Closes anchor"`)

### §ADR-0015 terminal hand-off fallback (codified)

When the parser-friendly formats above are NOT used (e.g., `+` separator, body edit during review), the **fallback is ADR-0015 terminal hand-off**:

```bash
# Post-PR-squash, before declaring "Done":
gh issue close <N> --reason "PR #M squashed, Closes anchor via PR body (parser-friendly doctrine per ADR-0057)"
```

**This is a SAFETY NET, not a primary mechanism**. The doctrine target is parser-friendly format compliance (preventive). Terminal hand-off is recovery.

### §Workflow YAML guard (proposed — owner merge required)

Per file ownership matrix, `.github/workflows/` is human-only territory. The following CI integration is **proposed** for owner merge:

- **CI trigger**: `paths: docs/decisions/ADR-*.md` OR `paths: .github/workflows/closes-anchor-check.yml` (NEW file proposed)
- **Action**: Lint PR body for Closes anchor formats; emit `silent_skip` log on unrecognized format (lens (d) compliance, ADR-0048)
- **Failure mode**: WARN (not FAIL) — doctrine is advisory; ADR-0015 terminal hand-off fallback handles failures

**Owner gate**: this requires a new workflow file OR amendment to existing workflow. Per CLAUDE.md §File ownership matrix + ADR-0031 owner-override doctrine, architect + tester draft, owner merges.

### §Edge cases (codified)

| Edge case | Doctrine |
|-----------|----------|
| Body edit mid-review changes Closes anchor | Mechanical edit OK; **must re-verify** per §Verification pattern before squash |
| PR subsumes earlier PR (e.g., PR #554 ⊇ PR #553) | Body edit can add Closes anchor for subsumed Issues; ADR-0015 fallback if parser fails |
| Multiple keywords for same Issue (e.g., `Closes #1, Closes #1`) | Idempotent — duplicate Issue auto-close is no-op |
| Body has `Closes` but no `#N` | Doctrine violation — must be fixed before squash (no silent skip) |

## Rationale

### Why comma-separation (vs other parser-friendly formats)

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **Comma-separation** (preferred) | Compact, single line, widely-used, parser-verified | Requires careful prose (no `Issue #N` between `#N`) | ✅ Adopt (preferred) |
| Multiple keywords | Verbose but explicit (each Issue has own keyword) | Repetitive for 5+ Issues | ✅ Adopt (verbose alt) |
| Multi-line keywords | Clear visual grouping | Uses more vertical space | ✅ Adopt (multi-line alt) |
| `+` separator (current PR #554) | Compact (prose-like) | **Parser does NOT recognize** (LIVE INSTANCE) | ❌ Rejected |
| `and` separator | Prose-natural | No documented recognition | ❌ Rejected |

**Verdict**: comma-separation is the **default preferred format**. Other parser-friendly formats are acceptable per case.

### Why ADR-0015 fallback (not silent skip)

The `+` separator pattern is **not silent** — it surfaces via:
1. Manual check of open Issues post-squash
2. PR close-out verification (PM lane, Sprint ceremony)
3. CI workflow (proposed, owner merge required)

ADR-0015 terminal hand-off is the **recovery mechanism**, not silent skip. Doctrine target is **preventive compliance** (use parser-friendly formats) + **reactive recovery** (terminal hand-off if prevention fails).

### Why WARN (not FAIL) in workflow YAML

The proposed CI guard emits **WARN**, not FAIL, because:
- Doctrine is **advisory** — some PRs legitimately close 1 Issue only (no multi-issue risk)
- **Architectural decision** (comma-separation vs multi-line) is a **style preference**, not correctness
- ADR-0015 fallback handles parser failures gracefully (no squash-block needed)

Sister-pattern: ADR-0056 Layer 5 idempotency reconcile — cheaper fix (WARN + fallback) over FAIL (squash-block).

## Consequences

### Positive

- **Parser-friendly doctrine**: PR bodies use canonical formats; `+`/`and` separators doctrinally rejected
- **Verification pattern codified**: pre-squash check + ADR-0015 fallback = dual-defense
- **PR #554 LIVE INSTANCE documented**: prevents recurrence, attribution chain preserved
- **Workshop scope reduced**: 2-ADR Sprint 16 P1 workshop scope preserved (PM EXTENSION v5 MERGE pre-applied)
- **Workflow YAML guard (proposed)**: CI integration via owner merge (WARN, not FAIL)

### Negative

- **Doctrine adoption friction**: existing PR body templates may use `+`/`and` separators (PM lane retro update candidate)
- **Body edit verification burden**: mid-review Closes anchor edits MUST be re-verified (architect lane discipline)
- **Workflow YAML deferred**: silent_skip log + parser-friendly lint = owner merge required
- **WARN-only CI integration**: doctrine advisory, not enforced (architectural choice — sister-pattern to ADR-0056)

### Sprint boundary

- `docs/decisions/ADR-0057-*.md` (this file) = **architect** lane (doctrine)
- `.github/workflows/closes-anchor-check.yml` (silent_skip log + parser-friendly lint, NEW proposed) = **human-only** territory (architect + tester draft, owner merges per file ownership matrix)
- d-test integration (d062-closes-anchor-parser.sh, candidate) = **developer + tester** joint (Sprint 16+ candidate, NOT in this PR)
- PM retro update for PR body templates = **PM** lane (Sprint 16 retro candidate)

## Alternatives considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **ADR-0057 (this file)** | Parser-friendly doctrine + verification + fallback dual-defense | Workflow YAML deferred to owner | ✅ Adopt |
| Force `+` parser recognition (file GitHub issue) | Theoretical GitHub support | Out of team control; 6+ month timeline; doesn't help current PRs | ❌ Rejected |
| Silent skip on parser failure | Hides symptom | Violates ADR-0048 (silent_skip log mandatory, lens (d)); hides attribution loss | ❌ Rejected |
| No ADR (use Issue #560 as living doc) | No ceremony | Doctrine must be in ADRs per ADR-0017 + INDEX.md conventions | ❌ Rejected |
| Amend ADR-0015 (atomic 4-flag handoff) | Sister to hand-off | ADR-0015 is hand-off protocol, not Closes anchor doctrine — different concern | ❌ Rejected |

## Open questions

- [ ] **Q1**: Workflow YAML guard file — should it be a NEW file (`closes-anchor-check.yml`) OR amendment to `label-check.yml` paths trigger? (Owner decides per ADR-0031)
- [ ] **Q2**: PR body templates — should the PM retro update `docs/PULL_REQUEST_TEMPLATE.md` (if exists) to use comma-separation by default? (PM lane, Sprint 16 retro candidate)
- [ ] **Q3**: d-test framework — should a new d-test (d062-closes-anchor-parser) be added to verify parser-friendly format compliance? (Tester lane decision, Sprint 16+ candidate)

## References

- **Issue #560** (Sprint 16 P1 doctrine hardening workshop, Closes-anchor + Comment-trigger scope) — this ADR's container
- **PR #554** (ADR-0056 squash @ 1456d97) — Closes-anchor parser limitation LIVE INSTANCE (Issue #546 auto-closed; Issue #551 manual close via ADR-0015)
- **Issue #546** (Sprint 16 P1 doctrine hardening, RETRO-010 #34 NEW) — auto-closed via PR #554 squash
- **Issue #551** (RETRO-010 §18 NEW, sub-pattern codification) — manually closed via ADR-0015 terminal hand-off (PR #554 squash body edit `+` separator not parser-recognized)
- **ADR-0015** — atomic 4-flag handoff (terminal hand-off fallback doctrine, this ADR's safety net)
- **ADR-0045** — 9-Lens (j) auto-gen file refs + live-state verification (doctrinal self-attestation per §9-Lens)
- **ADR-0048** — silent_skip log mandatory (lens (d) compliance, this ADR's workflow YAML guard reference)
- **ADR-0056** — Layer 5 idempotency reconcile (cheaper fix sister-pattern, WARN-not-FAIL doctrine)
- **RETRO-010 #33 NEW** — false-positive auto-add codification cluster (this ADR's codification target)
- **RETRO-010 #34 NEW** — auto-cascade self-reversal + double-removal (sister codification cluster, ADR-0056)
- **PM PICKUP-41** (Issue #560 kickoff, cycle 243) — workshop scope = 2-ADR after PM EXTENSION v5 MERGE

## §9-Lens Review Checklist (doctrinal self-application)

| Lens | Status | Note |
|------|--------|------|
| (a) Data flow | ✅ | Doctrine-only ADR. PR body → GitHub Closes anchor parser → Issue auto-close (or fallback ADR-0015). Traceable via PR #554 LIVE INSTANCE (Issue #546 auto-closed, Issue #551 manual). |
| (b) Runtime preconditions | ✅ | No runtime deps. Verification step uses `gh issue view` + `grep` (existing). Workflow YAML guard (proposed) = bash + grep. |
| (c) Canonical entry point | ✅ | Single ADR file + PR body template. No side-channels. |
| (d) Silent-skip risk | ✅ | Doctrine REQUIRES `silent_skip` log on parser failure (lens (d) compliance, ADR-0048). Proposed workflow YAML guard emits `silent_skip` log on unrecognized format. |
| (e) Idempotency | ✅ | Re-verification pre-squash is idempotent. ADR-0015 fallback is idempotent (`gh issue close` on already-closed Issue is no-op). |
| (f) Observability | ✅ | PR #554 LIVE INSTANCE documented (Issue #546 auto-closed, Issue #551 manual, attribution note in body). Proposed workflow YAML guard = WARN log + silent_skip log. |
| (g) Security & privacy | N/A | PR body parser has no auth/PII surface |
| (h) Workflow YAML SHA pin | N/A | no workflow changes in this ADR (workflow YAML guard proposed but owner gate) |
| (i) Platform hard constraints | ✅ | Doctrine-only. Workflow YAML guard (proposed) = bash + grep, no platform changes. |
| (j) Auto-gen file refs + live-state | ✅ | INDEX.md is auto-gen (Cadence Rule 1 carrier, ADR-0055); ADR-0057 row added in same PR; live-state references PR #554 SHA `1456d97` (verifiable via `git log --grep`). |
| (k) JS syntactic correctness | N/A | no JS in this ADR |

— @architect, 2026-06-28T<draft-cycle>+03:00, ADR-0057 Closes-anchor guard (Sprint 16 P1 doctrine hardening, Closes Issue #560 AC1, codifies parser-friendly Closes anchor doctrine + ADR-0015 fallback + verification pattern, arch lane doctrine)

---

## Amendment

Folded amendments per **ADR-0057 §amendment-via-parent** (Path A v26 source-of-truth = calc-side standalone amendment file; tmpl-side = section in parent ADR).

### Amendment ?: closes-vs-refs intent (folded per ADR-0057 §amendment-via-parent)

- **Status:** Accepted (amendment — folded into this ADR per ADR-0057 §amendment-via-parent; canonical home = this section)
- **Date:** 2026-07-07
- **Origin:** (see calc source)
- **Source (calc canonical):** [ADR-0057-amendment-closes-vs-refs-intent](https://github.com/atilcan65/AtilCalculator/blob/main/docs/decisions/ADR-0057-amendment-closes-vs-refs-intent.md) — folded into this section on tmpl per ADR-0057 §amendment-via-parent pattern. NOTE: tmpl standalone `ADR-0057-amendment-closes-vs-refs-intent.md` file does NOT exist (will not be created); amendment lineage trace via slug reference in this section.
- **Sister-patterns:** ADR-0057 (§amendment-via-parent — fold pattern codification), ADR-0024 §Watchdog logic, ADR-0038 §WIP cap, ADR-0049 §d-test framework, ADR-0055 §1 Cadence Rule 1 atomic

#### Amendment doctrine (extracted from calc canonical §Decision)

Adopt **§Closes-vs-Refs Intent Rule (canonical)** as a new sub-section of ADR-0057. The rule codifies that the choice between `Closes:`/`Fixes:`/`Resolves:` vs `Refs:` depends on **CLOSE INTENT**, not on fix type or PR description conventions.

### §Closes-vs-Refs Intent Rule (canonical)

**Rule**: The choice between `Closes:` (and equivalents `Fixes:`, `Resolves:`) vs `Refs:` depends on whether the PR **RESOLVES** the referenced issue.

| Anchor | Intent | Auto-close on merge? | When to use |
|--------|--------|----------------------|-------------|
| **`Closes:`** (or `Fixes:`, `Resolves:`) | **CLOSE INTENT** — PR resolves the issue | ✅ Yes | PR fixes, resolves, or otherwise closes the issue |
| **`Refs:`** | **INFORMATIONAL** — PR is RELATED but does NOT close | ❌ No | Pure cross-reference; PR mentions/depends on the issue but does not close it |

### Key clarifications

1. **Fix type doesn't matter**: Whether the PR is `impl` (code change), `test` (d-test PR), `docs` (ADR/doc change), `chore` (refactor), or `type:refactor` (test-data migration) — if it RESOLVES the issue, use `Closes:`. **Test-data-migration PRs closing bug issues MUST use `Closes:`.** The migration IS the fix.

*(Doctrine elided for brevity — see calc canonical source for full text)*

