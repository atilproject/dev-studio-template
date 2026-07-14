# STORY-S29-016 — pyproject.toml.tmpl + LICENSE.tmpl + .template-version.tmpl render path

> **Test plan (sister-doc to d1027-s29-016-template-pyproject-render.sh).**
> Created as part of Cadence Rule 1 atomic cluster per ADR-0049 (d-test framework, template-side, ≥5 TCs + sister-pattern + same-commit cluster rule; calc-side doctrinal ancestor is ADR-0055 §1).
> Revision 2026-07-14 (cycle #1833): NIT-1..NIT-4 fixes per arch 9-Lens PR #104 cycle #1832.

## §Forward-Reference — S29-018 docs sub-dir skeletons forward-port (Issue #1077)

This test plan file **is the first concrete content under `docs/test-plans/`** in the template repo. The `docs/test-plans/` directory was not previously created — that is S29-018's sister work (Issue #1077, P1), which is the **docs sub-dir skeletons forward-port**. S29-018 will:

1. Sister the `docs/test-plans/` skeleton template (TC-matrix layout, story heading format, §Forward-Reference header convention) to the other 7 docs sub-dir skeletons forward-ported in that batch.
2. Backfill this STORY-S29-016 file to follow the now-LOCKED skeleton convention (naming, section order, why-this-d-test-exists block).

Until S29-018 lands, **this file is the de facto skeleton template** — sister-pattern to how d1025/d1026/d1027 informed later dev-studio-template d-tests on format conventions (e.g., 6-TC baseline per ADR-0049, §Why this d-test exists block per Issue #1071 fixture gap).

**Sister-pattern lineage**:
- Issue #1075 (S29-016 P0, CRITICAL BLOCKER) — this d-test
- Issue #1077 (S29-018 P1) — docs sub-dir skeletons forward-port
- Issue #1076 (S29-017 P1) — calctl CLI surface + d-tests (gap-closing in dev lane, blockers S29-019)
- Issue #1078 (S29-019 P2) — calculator RPC HTTP surface + d-tests
- **Template-side ADRs (load-bearing)**: ADR-0046 (d-test convention), ADR-0049 (d-test framework ≥5 TCs baseline, ≥3 sister-patterns), ADR-0040 (cross-repo-pr-auto-close), ADR-0059 (cluster-squash)
- **Calc-side ADRs (cross-reference only)**: ADR-0044 (RED-first TDD — calc-side doctrinal home), ADR-0055 §1 (Cadence Rule 1 atomic — calc-side; template-side equivalent is ADR-0049 d-test framework + the established cluster pattern), ADR-0045 (9-Lens pre-publish — calc-side; arch applied 9-Lens to PR #104 cycle #1832, surfaced NIT-1/NIT-2/NIT-3/NIT-4 hygiene findings)
- **NIT-1 corrections (per arch 9-Lens PR #104 review, cycle #1832)**: ADR-0050 ≠ render path doctrine (actual: `pre-merge-4-cat-verification.md`); ADR-0057 ≠ cross-repo anchor convention (actual: `closes-anchor-guard.md`). Both incorrectly cited in initial commit; corrected in this revision.

---

## Story summary

**Sprint 29 W2B+ S29-016 P0 CRITICAL BLOCKER**: ship `pyproject.toml.tmpl` + `LICENSE.tmpl` + `.template-version.tmpl` at the template root + extend `scripts/dev-studio-init.sh` to render all 3 `.tmpl` files idempotently to their final paths. Without these, downstream projects created via the launcher cannot `pip install -e .[dev]`, cannot run `pytest/ruff/mypy`, lack LICENSE for legal distribution, and lack version marker that downstream owners use as drift-prevention signal.

## Acceptance criteria (from Issue #1075)

1. **AC1**: `pyproject.toml.tmpl` exists at template root, is PEP 621-parseable, contains `[project]` table with `name` + `version` fields and `[project.optional-dependencies.dev]` for `[dev]` extra (sister to AtilCalculator's existing `pyproject.toml`).
2. **AC2**: `LICENSE.tmpl` exists at template root, contains MIT license text + Copyright line + `{{YEAR}}` + `{{OWNER_NAME}}` placeholders, default MIT per owner directive #6.
3. **AC3**: `.template-version.tmpl` exists at template root, contains STRICT semver `^[0-9]+\.[0-9]+\.[0-9]+$` (matches current `scripts/dev-studio-template` version, NO pre-release/build suffix per AC3 idempotency constraint — NIT-4 tightened from d320's looser regex to enforce idempotent re-renders).
4. **AC4**: `bash scripts/dev-studio-init.sh --dry-run` reports it WOULD render the 3 template files to final paths. Re-running with already-rendered outputs is a no-op (idempotent — sister to existing `.claude/CLAUDE.md.tmpl` render line in dev-studio-init.sh; no ADR-X citation per NIT-1).
5. **AC5**: rendered outputs are installable / legally valid / version-marker-readable downstream:
   - (a) `pip install -e .[dev]` succeeds (NOT covered by d1027 — static only; full e2e in S29-020 follow-up).
   - (b) `LICENSE` file at rendered path is a valid MIT license (`SPDX-License-Identifier: MIT` + Copyright + year).
   - (c) `.template-version` at rendered path reads as strict semver `^[0-9]+\.[0-9]+\.[0-9]+$`.
   - (d) static installable validation on template source `pyproject.toml.tmpl` with `{{...}}` → PLACEHOLDER substitution (NIT-3 fix: header now reflects body, no rendered-output claim) — `python -c "import tomllib; tomllib.loads(open('pyproject.toml.tmpl').read().replace('{{...}}', 'PLACEHOLDER'))"` returns no errors, contains `[project]` table + dependencies, no orphan placeholders in critical fields (covered by TC6 in d1027 d-test).

## d-test architecture (per Issue #1071 fixture gap doctrine)

d-test must satisfy ADR-0049 ≥5 TCs baseline + ≥3 sister-patterns + ADR-0046 d-test convention (template-side). d1027 ships 6 TCs + TC0 preflight:

| TC  | Purpose | Sister-pattern reference |
|-----|---------|--------------------------|
| TC0 | `bash -n` syntactic self-check (preflight per d058 + d081 convention — IS the d-test's self-test per NIT-2, no separate `--self-test` flag) | d058 (fake-session isolation), d081 (tmpl-side d-test conventions) |
| TC1 | All 3 `.tmpl` files exist at template root (AC1/AC2/AC3 pre-impl all FAIL) | d1018 (S29-006 ADR-port `docs/decisions/` files), d1025 (agent-wake-hotfix tmpl-side file presence) |
| TC2 | `pyproject.toml.tmpl` is PEP 621-parseable via Python `tomllib` after `{{...}}` substitution | d1020 (S29-010 workflow-port-parity config TOML parse via python), d1018 (toml config sanity) |
| TC3 | `LICENSE.tmpl` contains MIT text + Copyright + `{{YEAR}}` placeholder | d1025 (README + LICENSE fixture pattern — tmpl-side sister), d058 (file content cross-check) |
| TC4 | `.template-version.tmpl` contains STRICT semver per `^[0-9]+\.[0-9]+\.[0-9]+$` regex (NIT-4: tightened from d320's looser regex; divergence is intentional — AC3 idempotency constraint is stricter than d320's date tolerance window) | d320 (stale-verdict-contract — date/version regex conventions), d1018 (semver in ADR header) |
| TC5 | `bash scripts/dev-studio-init.sh --dry-run` mentions all 3 templates in would-render output | d1026 (S29-template-env-decoupling-port-parity — `dry-run` script-shape), d983 (forward-port-parity sister) |
| TC6 | Template source `pyproject.toml.tmpl` (with `{{...}}` → PLACEHOLDER substitution, NIT-3 fix) is installable per static validation: PEP 621 parse, `[project]` table present, dependencies declared, no orphan placeholders in critical fields | d1018 (config-parity post-port validation), d1026 (installable-state validation) |

≥3 sister-pattern coverage per ADR-0049 met (d1026 + d1018 + d1020 = 3 + d1024 + d058 + d081 = 6 total).

## Pre-impl RED state (verified 2026-07-14 by @tester, cycle #1708; re-verified post-NIT-fixes cycle #1833)

```
PASS: 1 (TC0 preflight only)
FAIL: 6 (TC1: 3/3 template files absent, TC2: parse fails on missing file, TC3: MIT text absent, TC4: semver absent, TC5: --dry-run does NOT list the 3 files, TC6: source pyproject.toml.tmpl absent)
```

Post-impl (when architect lands `pyproject.toml.tmpl` + `LICENSE.tmpl` + `.template-version.tmpl` + extends `dev-studio-init.sh` to render all 3): all 6 TCs GREEN.

## Cadence Rule 1 atomic per ADR-0049 + ADR-0046 (template-side equivalents of calc-side ADR-0055 §1) — single-commit cluster

PR must include:
1. `scripts/tests/d1027-s29-016-template-pyproject-render.sh` (NEW, ~270 LOC, 6 TCs + TC0 preflight)
2. `scripts/tests/INDEX.md` (Cadence Rule 1 atomic sister-row, insert after d1026 row at line 167)
3. `docs/test-plans/STORY-S29-016-pyproject-tmpl-render-tests.md` (this file)

Plus implicit:
4. `docs/test-plans/` directory creation (this file is the first content under it)

All 4 land in same commit per Cadence Rule 1.

## Cross-references

- **Issue #1075** (S29-016, P0 CRITICAL BLOCKER, arch scope sign-off posted cmt IC_kwDOS9WE8s8AAAABKHG1LA) — cluster coord on calc side
- **Issue #1071** (d1026 TC2 fixture gap — doctrine basis for why-this-d-test-exists block)
- **Issue #1077** (S29-018, P1) — sister, docs sub-dir skeletons forward-port (will backfill skeleton conventions)
- **Issue #1076** (S29-017, P1) — calctl CLI surface
- **Issue #1078** (S29-019, P2) — calculator RPC HTTP surface

**Template-side ADRs (load-bearing, all verified to exist on template `docs/decisions/` per arch 9-Lens PR #104 cycle #1832)**:
- **ADR-0040** (cross-repo-pr-auto-close — bridges `Closes atilcan65/AtilCalculator#1075` syntax)
- **ADR-0046** (d-test convention — structural requirements: `set -uo pipefail`, "Why this d-test exists" narrative ≥2-5 lines, PASS/FAIL counters, TC0 preflight, standalone run command)
- **ADR-0049** (d-test framework — ≥5 TCs baseline + ≥3 sister-pattern baseline + same-commit cluster rule)
- **ADR-0059** (cluster-squash — d-test ships BEFORE impl, sister-PR must land same merge-day as calc-side)
- **ADR-0031** (owner merge gate — only human squash-merges impl PR; load-bearing for Phase B)

**Calc-side ADRs (cross-reference only, NOT load-bearing on template side)**:
- **ADR-0044** (RED-first TDD — calc-side doctrinal home; template-side equivalent is ADR-0046 + ADR-0049 cluster)
- **ADR-0055 §1** (Cadence Rule 1 atomic — calc-side; template-side equivalent is ADR-0049 d-test framework)
- **ADR-0045** (9-Lens pre-publish — calc-side; arch applied 9-Lens to PR #104 cycle #1832, surfaced NIT-1/NIT-2/NIT-3/NIT-4)

**NIT-1 corrections (arch 9-Lens cycle #1832, applied in this revision)**:
- ADR-0050 ≠ ".claude/CLAUDE.md.tmpl render path doctrine" — actual content is `pre-merge-4-cat-verification.md` (no render-path mention)
- ADR-0057 ≠ "Refs cross-repo anchor convention" — actual content is `closes-anchor-guard.md` (covers parser-friendly multi-Closes formats, not cross-repo anchor convention)
- Both corrected citations removed; load-bearing citations re-aligned to actual template-side ADRs (ADR-0040 + ADR-0046 + ADR-0049)

## Sister-test on this d-test file

After d1027 merges, follow-up sister-d-tests to verify (post-impl):
- `d1027-s29-016-template-pyproject-render.sh` RED-by-deletion: delete `pyproject.toml.tmpl` → TC1/TC2 FAIL 5/7; restore GREEN.
- Issue #1071 fixture gap doctrine self-check: every TC must cite which sister d-test it mirrors (≥3 per ADR-0049).
- NIT-4 RED-by-tampering: bump `.template-version.tmpl` to `2.1.207-rc1` (pre-release) → TC4 FAIL → confirm regex tightened correctly (sister-pattern for AC3 idempotency enforcement).

## Lane attribution

- **Test plan author**: @tester (cycle #1708, 2026-07-14) — sister to d1027 d-test authorship
- **Test plan owner**: @tester (sign-off lane per ADR-0046 d-test convention + ADR-0044 RED-first TDD calc-side ancestor)
- **d-test author**: @tester (this PR)
- **d-test owner**: @tester
- **d-test impl handoff**: @architect (post-PR, AC1-AC4 impl — blocked on Phase A GREEN per ADR-0046 + ADR-0044)

## Open follow-ups (out-of-scope for S29-016, defer to S29-020+)

- S29-020: full e2e `pip install -e .[dev]` after template init (currently AC5(a) is out-of-scope per arch scope sign-off)
- S29-020: cross-render parity test — verify `pyproject.toml.tmpl` renders to byte-identical `pyproject.toml` as AtilCalculator currently has (i.e., zero diff on the calc side)
- S29-020: drift-prevention marker semantic — confirm `.template-version` semantics match d320 stale-verdict tolerance window (note: d1027 TC4 tightened regex is stricter than d320's window; both can coexist if d320 stays for date-stamps and d1027 owns version-stamps)
