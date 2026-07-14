# STORY-S29-016 — pyproject.toml.tmpl + LICENSE.tmpl + .template-version.tmpl render path

> **Test plan (sister-doc to d1027-s29-016-template-pyproject-render.sh).**
> Created as part of Cadence Rule 1 atomic cluster per ADR-0055 §1 (d-test + INDEX.md row + test plan doc same commit).

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
- ADR-0049 (d-test framework ≥5 TCs baseline, ≥3 sister-patterns)
- ADR-0055 §1 (Cadence Rule 1 atomic — d-test + INDEX.md + test plan same commit)
- ADR-0050 (`.claude/CLAUDE.md.tmpl` render path doctrine — d1027 is the second `.tmpl` render-path d-test after d075's 7 TCs)

---

## Story summary

**Sprint 29 W2B+ S29-016 P0 CRITICAL BLOCKER**: ship `pyproject.toml.tmpl` + `LICENSE.tmpl` + `.template-version.tmpl` at the template root + extend `scripts/dev-studio-init.sh` to render all 3 `.tmpl` files idempotently to their final paths. Without these, downstream projects created via the launcher cannot `pip install -e .[dev]`, cannot run `pytest/ruff/mypy`, lack LICENSE for legal distribution, and lack version marker that downstream owners use as drift-prevention signal.

## Acceptance criteria (from Issue #1075)

1. **AC1**: `pyproject.toml.tmpl` exists at template root, is PEP 621-parseable, contains `[project]` table with `name` + `version` fields and `[project.optional-dependencies.dev]` for `[dev]` extra (sister to AtilCalculator's existing `pyproject.toml`).
2. **AC2**: `LICENSE.tmpl` exists at template root, contains MIT license text + Copyright line + `{{YEAR}}` + `{{OWNER_NAME}}` placeholders, default MIT per owner directive #6.
3. **AC3**: `.template-version.tmpl` exists at template root, contains semver `2.X.Y` (matches current `scripts/dev-studio-template` version, at least 3 segments numeric, no leading `v`, no pre-release suffix to keep idempotent re-renders stable).
4. **AC4**: `bash scripts/dev-studio-init.sh --dry-run` reports it WOULD render the 3 template files to final paths. Re-running with already-rendered outputs is a no-op (idempotent — sister to `.claude/CLAUDE.md.tmpl` render path per ADR-0050).
5. **AC5**: rendered outputs are installable / legally valid / version-marker-readable downstream:
   - (a) `pip install -e .[dev]` succeeds (NOT covered by d1027 — static only; full e2e in S29-020 follow-up).
   - (b) `LICENSE` file at rendered path is a valid MIT license (`SPDX-License-Identifier: MIT` + Copyright + year).
   - (c) `.template-version` at rendered path reads as semver `X.Y.Z`.
   - (d) static installable validation: `python -c "import tomllib; tomllib.loads(open('pyproject.toml').read().replace('{{...}}', 'default'))"` returns no errors, contains `[project]` + `[project.optional-dependencies.dev]` tables, no orphan placeholders in critical fields (covered by TC6 in d1027 d-test).

## d-test architecture (per Issue #1071 fixture gap doctrine)

d-test must satisfy ADR-0049 ≥5 TCs baseline + ≥3 sister-patterns. d1027 ships 6 TCs + TC0 preflight:

| TC  | Purpose | Sister-pattern reference |
|-----|---------|--------------------------|
| TC0 | `bash -n` syntactic self-check (preflight per d058 + d081 convention) | d058 (fake-session isolation), d081 (tmpl-side d-test conventions) |
| TC1 | All 3 `.tmpl` files exist at template root (AC1/AC2/AC3 pre-impl all FAIL) | d1018 (S29-006 ADR-port `docs/decisions/` files), d1025 (agent-wake-hotfix tmpl-side file presence) |
| TC2 | `pyproject.toml.tmpl` is PEP 621-parseable via Python `tomllib` after `{{...}}` substitution | d1020 (S29-010 workflow-port-parity config TOML parse via python), d1018 (toml config sanity) |
| TC3 | `LICENSE.tmpl` contains MIT text + Copyright + `{{YEAR}}` placeholder | d1025 (README + LICENSE fixture pattern — tmpl-side sister), d058 (file content cross-check) |
| TC4 | `.template-version.tmpl` contains valid semver per `^[0-9]+\.[0-9]+\.[0-9]+([+-][a-zA-Z0-9.-]+)?$` regex | d320 (stale-verdict-contract — date/version regex conventions), d1018 (semver in ADR header) |
| TC5 | `bash scripts/dev-studio-init.sh --dry-run` mentions all 3 templates in would-render output | d1026 (S29-template-env-decoupling-port-parity — `dry-run` script-shape), d983 (forward-port-parity sister) |
| TC6 | Rendered `pyproject.toml` (after `{{...}}` substitution) is installable (static validation: PEP 621 parse, `[project]` table present, dependencies declared, no orphan placeholders) | d1018 (config-parity post-port validation), d1026 (installable-state validation) |

≥3 sister-pattern coverage per ADR-0049 met (d1026 + d1018 + d1020 = 3 + d1024 + d058 + d081 = 6 total).

## Pre-impl RED state (verified 2026-07-14 by @tester, cycle #1708)

```
PASS: 1 (TC0 preflight only)
FAIL: 6 (TC1: 3/3 template files absent, TC2: parse fails on missing file, TC3: MIT text absent, TC4: semver absent, TC5: --dry-run does NOT list the 3 files, TC6: source pyproject.toml.tmpl absent)
```

Post-impl (when architect lands `pyproject.toml.tmpl` + `LICENSE.tmpl` + `.template-version.tmpl` + extends `dev-studio-init.sh` to render all 3): all 6 TCs GREEN.

## Cadence Rule 1 atomic (ADR-0055 §1) — single-commit cluster

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
- **ADR-0044** (RED-first TDD — d-test before impl lands)
- **ADR-0049** (d-test framework ≥5 TCs baseline, ≥3 sister-patterns)
- **ADR-0050** (`.claude/CLAUDE.md.tmpl` render path doctrine — sister-pattern render-path d-test)
- **ADR-0055 §1** (Cadence Rule 1 atomic)
- **ADR-0057** (`Refs atilcan65/AtilCalculator#1075` cross-repo anchor)
- **ADR-0059** (cluster-squash — d-test ships BEFORE impl, sister-PR must land same merge-day as calc-side)

## Sister-test on this d-test file

After d1027 merges, follow-up sister-d-tests to verify (post-impl):
- `d1027-s29-016-template-pyproject-render.sh` RED-by-deletion: delete `pyproject.toml.tmpl` → TC1/TC2 FAIL 5/7; restore GREEN.
- Issue #1071 fixture gap doctrine self-check: every TC must cite which sister d-test it mirrors (≥3 per ADR-0049).

## Lane attribution

- **Test plan author**: @tester (cycle #1708, 2026-07-14) — sister to d1027 d-test authorship
- **Test plan owner**: @tester (sign-off lane per ADR-0044)
- **d-test author**: @tester (this PR)
- **d-test owner**: @tester
- **d-test impl handoff**: @architect (post-PR, AC1-AC4 impl — blocked on Phase A GREEN per ADR-0044)

## Open follow-ups (out-of-scope for S29-016, defer to S29-020+)

- S29-020: full e2e `pip install -e .[dev]` after template init (currently AC5(a) is out-of-scope per arch scope sign-off)
- S29-020: cross-render parity test — verify `pyproject.toml.tmpl` renders to byte-identical `pyproject.toml` as AtilCalculator currently has (i.e., zero diff on the calc side)
- S29-020: drift-prevention marker semantic — confirm `.template-version` semantics match d320 stale-verdict tolerance window
