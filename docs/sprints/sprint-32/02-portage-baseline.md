# S32-002 — Baseline portage report

**Story**: S32-002 (tmpl#128) — Sprint 32 Wave 1 — Baseline portage report (template finalize gap inventory)
**Date**: 2026-07-18T08:13:05Z
**Repo**: atilproject/dev-studio-template (calc#1149 closed as RETRO-024 work-tracked-elsewhere)
**Branch**: dev/s32-002-portage-baseline (from tmpl-official/main @ 52ed840 = PR #126 audit merge)
**Method**: `bash scripts/verify-portage.sh --report=/tmp/portage-sprint-32-baseline.txt`
**Script exit code**: 0 ✅ (AC1)

## AC Status

| AC | Status | Evidence |
|---|---|---|
| AC1 (script exits 0) | ✅ PASS | Script completed cleanly, exit code 0 |
| AC2 (report ≥1 line/gap category) | ✅ PASS | 8 lines, 4 gap categories enumerated |
| AC3 (report copy in tmpl repo) | ✅ PASS | This file = sanitized copy of /tmp/portage-sprint-32-baseline.txt |
| AC4 (gap count matches audit Top 6 + ~40 ADRs order-of-magnitude) | ❌ FAIL (placeholder gap discovered) | Report shows 0/0/0/0 — diff steps are placeholders, not wired |
| AC5 (d-test parity summary) | ⚠️ PARTIAL | See below |

## Raw report

```
verify-portage report — 2026-07-18T08:13:05Z
scratch_repo=verify-portage-scratch-2393549 atilcalc_ref=atilcan65/AtilCalculator
---
category_gaps:
  scripts: 0
  workflows: 0
  decisions: 0
  soul: 0
```

## Critical finding — AC4 placeholder gap

The verify-portage.sh script's step 3+4 (diff 4 paths) is currently a **placeholder** that emits `category_gaps: 0` for every category. This is a forward-path blocker:

- Audit PR #126 identified Top 6 gaps + ~40+ ADRs/scripts as portage delta
- verify-portage.sh is the script supposed to make this delta re-verifiable
- But the script's diff engine is not yet wired to real `diff` commands (per script log: "diffing scripts/ (category=scripts) — placeholder until step 1 network call is wired")
- Sister-pattern: Issue #1041 (claim-next-ready.sh incident) — script with green-looking output that doesn't actually verify

**Forward-path**: S32-002 baseline AC4 must be re-stated as "diff wiring" gap-closure story, candidate for Sprint 32 Wave 2 (dev lane). ORCH gate decision needed.

## AC5 d-test parity (partial)

calc repo `scripts/tests/` contains 80+ d-test files per STORY-S29-007 (forward-ported). tmpl repo `scripts/tests/` count not yet captured by wired diff. Approximate ratio: calc 80+ vs tmpl 80+ per Sprint 29 forward-port scope; actual delta = TBD pending diff wiring.

## Sister-pattern

- **tmpl#126 audit** (Top 6 gaps + ~40 ADRs/souls/scripts as scope baseline) — MERGED 52ed840
- **calc#1149** — CLOSED, RETRO-024 work-tracked-elsewhere
- **tmpl#128** (this story) — OPEN, Wave 1 dev lane
- **tmpl#127** (S32-001 arch lane, sister Wave 1 story) — sister-pattern

## Verification method

```bash
# From dev-studio-template worktree (Sprint 32):
bash scripts/verify-portage.sh --report=/tmp/portage-sprint-32-baseline.txt

# Re-run deterministic baseline:
diff /tmp/portage-sprint-32-baseline.txt docs/sprints/sprint-32/02-portage-baseline.md
# Expected: minor metadata drift (date/timestamp) only
```

## Done-Means

Partial: AC1-3 + AC5 partial ✅. AC4 fails by design — placeholder diff wiring discovered as forward-path item. Wave 1 baseline = "verify-portage.sh is the right tool but its diff engine needs wiring (Gap X = placeholder closure)."
