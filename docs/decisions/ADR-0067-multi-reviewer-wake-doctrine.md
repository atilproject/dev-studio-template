# ADR-0067: Multi-Reviewer Wake Doctrine — needs-* labels must open+close via reviewer

**Status**: Accepted
**Date**: 2026-07-04
**Deciders**: @architect (closed PR #808 cascade-strip recovery), @tester (reported pathology + multi-reviewer doctrine reference), @owner (squash gate pending)
**Refs**: PR #805 (vacuous-pass sister-pattern), PR #804 (Layer 5.5 j.4 fix), Issue #806, cmt 4881363145

## Context

PR #808 cascade-strip incident (cycle ~#3731): PR was opened WITHOUT `needs-architect-review` label. On 9d6fb0c push, the workflow's PR-#804-fix (Layer 5.5 j.4) detected the missing wake cycle and stripped `status:in-review` + `cc:tester` + `needs-tester-signoff` from the PR.

This was **NOT** a vacuous-pass regression — PR #804's fix correctly identified an incomplete reviewer chain and triggered cascade-strip. The pathology was that the architect had reviewed (verdict-by stamp present) but had never opened+closed the `needs-architect-review` wake cycle that the workflow validator expects.

## Decision

**Wake labels (`needs-architect-review`, `needs-tester-signoff`) MUST be opened (added) AND closed (removed) by the reviewer in sequence for the workflow to validate the review happened.**

Concretely, per ADR-0045 §9-Lens:
1. Reviewer adds `needs-<self>-review` wake label when starting review
2. Reviewer posts verdict + verdict-by stamp
3. Reviewer REMOVES `needs-<self>-review` wake label to close the cycle
4. Label-check validates: wake opened AND closed → review considered complete

This is the **open/close pair** discipline that distinguishes "reviewer never acted" (label never added) from "reviewer approved" (label added then removed) — both are otherwise indistinguishable from a verdict-by stamp alone.

## Rationale

Without the open/close pair:
- A reviewer who never sees the PR (event missed, silent-drop, etc.) leaves the wake label absent
- A reviewer who completes review also leaves the wake label absent (after their remove)
- The label-check cannot distinguish these two states → strip pathology OR silent-skip, neither desired

With the open/close pair:
- Wake label absent + verdict-by present → review complete (label closed after open)
- Wake label absent + NO verdict-by → review never happened
- Wake label present (mid-cycle) → review in progress (label-check waits)

## Consequences

**Positive**:
- Label-check has unambiguous signal: wake open/close cycle is the canonical "review happened" marker
- Verdict-by stamp is sufficient semantic content (when is it, by whom)
- No false-positive cascade-strip on reviews that DID complete

**Negative**:
- Adds 2 tool calls to every review (add label + remove label)
- Reviewers must remember the discipline
- Race conditions possible if add+remove happen too fast for label-check to observe the "open" state

**Mitigation**:
- The pair-op is encoded in the soul file (`architect.md`, `tester.md`) §Handoff Discipline
- Sister-pattern d-test in d806 family to validate the discipline mechanically (deferred to follow-up)

## Follow-ups

- Sprint 24: extend d806 family with d808 (multi-reviewer wake pair-op discipline) — TDD RED-first per ADR-0044
- ADR-0067 INDEX update
- Soul file updates: architect.md §Code review + tester.md §Sign-off sections

## Cross-references

- PR #805 (d320 TC7 vacuous-pass regression — Layer 5.5 j.4) — sister-pattern
- PR #804 (Layer 5.5 j.4 fix — preserve reviewer chain) — workflow implementation
- ADR-0045 (9-Lens Review Checklist) — architectural contract
- ADR-0049 (d-test framework ≥3 TCs sister-pattern) — follow-up test pattern
- Issue #806 (silent-drop bug) — orthogonal, separate doctrine
- cmt 4881363145 — live instance of cascade-strip pathology + recovery