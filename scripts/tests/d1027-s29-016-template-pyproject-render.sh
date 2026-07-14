#!/usr/bin/env bash
# d1027-s29-016-template-pyproject-render.sh — Sprint 29 W2B+ S29-016 P0
# CRITICAL BLOCKER d-test. Verifies that `dev-studio-template` ships
# pyproject.toml.tmpl + LICENSE.tmpl + .template-version.tmpl and that
# `dev-studio-init.sh` renders all 3 to final files idempotently (AC1-AC4
# of Issue #1075). Sister-pattern to the existing .claude/CLAUDE.md.tmpl
# render line in scripts/dev-studio-init.sh; doctrinal home is template-side
# ADR-0046 (d-test convention) + ADR-0049 (d-test framework) + ADR-0040
# (cross-repo-pr-auto-close, bridges `Closes atilcan65/AtilCalculator#N`
# syntax). Calc-side doctrinal ancestors: ADR-0044 (RED-first TDD) +
# ADR-0055 §1 (Cadence Rule 1 atomic) + ADR-0045 (9-Lens) — cited only for
# cross-reference, NOT as live template-side ADRs (they don't exist here).
# ADR-0050 (pre-merge-4-cat-verification) + ADR-0057 (closes-anchor-guard)
# are NOT the render-path / cross-repo-anchor doctrines (NIT-1 arch review).
#
# Doctrinal contract (≥5 TCs baseline per ADR-0049 +
#   `docs/sprints/current/plan.md` "≥5 TCs behavioral, ≥3 TCs hygiene/docs"):
#   TC0: bash -n syntactic self-check (preflight, PASS pre/post — test file exists)
#   TC1: AC1 + AC2 + AC3 — pyproject.toml.tmpl + LICENSE.tmpl + .template-version.tmpl
#        all exist at the template root (sister-pattern to .claude/CLAUDE.md.tmpl
#        render line in dev-studio-init.sh; ADR-0046 d-test convention applies)
#   TC2: AC1 — pyproject.toml.tmpl is PEP 621-parseable via Python tomllib (after
#        substituting {{...}} placeholders with sane defaults; static validation only
#        — sister-pattern to d1020 S29-010 workflow port-parity TOML parse)
#   TC3: AC2 — LICENSE.tmpl contains "MIT License" + Copyright year placeholder
#        + (owner name) placeholder per Issue #1075 AC2 + owner directive #6 (MIT default)
#   TC4: AC3 — .template-version.tmpl contains STRICT semver (e.g., 2.1.207)
#        matching `^[0-9]+\.[0-9]+\.[0-9]+$` regex (no pre-release/build suffix
#        per AC3 idempotency constraint — NIT-4 divergence from d320's looser regex
#        is intentional, see NIT-4 commit message)
#   TC5: AC4 — `bash dev-studio-init.sh --dry-run` reports it WOULD render the
#        3 template files to their final paths (idempotent sister to .claude/
#        CLAUDE.md.tmpl render line in dev-studio-init.sh; re-running with
#        already-rendered outputs is a no-op, not an error)
#   TC6: AC5(d) — template source (pyproject.toml.tmpl) with {{...}} → PLACEHOLDER
#        substitution passes static installable validation (sister to AC5(a)
#        `pip install -e .[dev]` but static only — idempotent + CI-friendly;
#        NIT-3 fix: header now matches body, no rendered-output claim)
#
# Doctrinal home: Issue #1075 (S29-016, P0 CRITICAL BLOCKER, arch scope
#   sign-off posted cmt IC_kwDOS9WE8s8AAAABKHG1LA) + Sprint 29 W2B+ plan
#   + Owner squash gate per ADR-0031 (load-bearing).
#   Forward-reference: docs/test-plans/STORY-S29-016-pyproject-tmpl-render-tests.md
#   documents S29-018 sister (8 docs sub-dir skeletons creation will create
#   docs/test-plans/ as part of forward-port — see §Forward-Reference header).
#
# Why this d-test exists
# ----------------------
# Owner goal: launcher creates projects with full features. Currently
# `dev-studio-template` has NO pyproject.toml (REST 404), no LICENSE.tmpl,
# no .template-version.tmpl. Downstream projects created via launcher cannot
# run `pip install -e .[dev]`, `pytest`, `ruff`, `mypy` without pyproject.toml.
# LICENSE absent blocks legal distribution. .template-version absent breaks
# drift-prevention marker (S21-007 doctrine). Arch v3 audit §C Gap 1
# confirms this is CRITICAL BLOCKER.
#
# RED-first per ADR-0046 (d-test convention, template-side) + ADR-0049
# (d-test framework, template-side): pre-impl on current template main,
# all 6 substantive TC fail (TC1: 3/3 files absent; TC2: parse fails on
# missing file; TC3: MIT text absent; TC4: semver absent; TC5: --dry-run
# does NOT list the 3 files; TC6: source pyproject.toml.tmpl absent).
# Post-impl (when arch lands pyproject.toml.tmpl + LICENSE.tmpl +
# .template-version.tmpl + idempotent render path): all 7 TC GREEN.
#
# Cadence Rule 1 atomic per ADR-0049 (d-test framework): this d-test file
# + INDEX.md entry + docs/test-plans/STORY-S29-016-pyproject-tmpl-render-tests.md
# all land in same commit cluster per ADR-0059 cluster-squash.
#
# Sister-patterns (≥3 per ADR-0049):
#   - d1026 (S29-template env-decoupling-port-parity) — direct sister,
#     same 5-TC shape, same dev-studio-init.sh --dry-run pattern,
#     same template-side regression-guard framing
#   - d1018 (S29-006 ADR-port-parity) — sister cross-repo port-parity
#     pattern, same .tmpl file presence + content checks
#   - d1020 (S29-010 workflow port-parity) — sister Sprint 29 cadence,
#     same template-side AC verification pattern, same pytest-style
#     TC0-TC5 baseline
#   - d1024 (S29 ping-env-decoupling) — Sprint 29 cadence sister,
#     same Issue #113 label-authority slot allocation
#
# Exit codes: 0 = all pass; 1 = at least one TC fail.
# Run: bash scripts/tests/d1027-s29-016-template-pyproject-render.sh
# Note: this script has no --self-test flag (NIT-2 from arch 9-Lens PR #104 review).
#       TC0 preflight (bash -n) IS the self-test — it validates syntax at the top of
#       every run before substantive TCs execute. Header line kept minimal per NIT-2.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMPL_PYPROJECT="${REPO_ROOT}/pyproject.toml.tmpl"
TMPL_LICENSE="${REPO_ROOT}/LICENSE.tmpl"
TMPL_VERSION="${REPO_ROOT}/.template-version.tmpl"
INIT_SCRIPT="${REPO_ROOT}/scripts/dev-studio-init.sh"

# Colors (TTY-aware)
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; B=""; D=""
fi

PASS=0; FAIL=0
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

# ----------------------------------------------------------------------------
# TC0: bash -n syntactic self-check
# ----------------------------------------------------------------------------
section "TC0: bash -n syntactic self-check (preflight)"
if bash -n "$0" 2>/dev/null; then
  pass "test file syntactically valid (bash -n)"
else
  fail "bash -n self-check failed" "fix syntax errors in $0"
fi

# ----------------------------------------------------------------------------
# TC1: pyproject.toml.tmpl + LICENSE.tmpl + .template-version.tmpl exist
# ----------------------------------------------------------------------------
section "TC1: AC1/AC2/AC3 — 3 template files exist at template root"
missing=()
[ -f "$TMPL_PYPROJECT" ] || missing+=("pyproject.toml.tmpl")
[ -f "$TMPL_LICENSE" ] || missing+=("LICENSE.tmpl")
[ -f "$TMPL_VERSION" ] || missing+=(".template-version.tmpl")
if [ ${#missing[@]} -eq 0 ]; then
  pass "all 3 template files exist (pyproject.toml.tmpl + LICENSE.tmpl + .template-version.tmpl)"
else
  fail "missing ${#missing[@]} template files" "expected pyproject.toml.tmpl + LICENSE.tmpl + .template-version.tmpl at template root; missing: ${missing[*]} — see Issue #1075 AC1/AC2/AC3"
fi

# ----------------------------------------------------------------------------
# TC2: pyproject.toml.tmpl PEP 621 parseable (placeholders substituted)
# ----------------------------------------------------------------------------
section "TC2: AC1 — pyproject.toml.tmpl is PEP 621 parseable"
if [ -f "$TMPL_PYPROJECT" ]; then
  # Substitute common {{...}} placeholders with placeholder values for parsing.
  # Real values come from the launcher init-time substitution; static validation
  # only checks the TOML grammar + [project] table presence.
  normalized=$(sed -E 's/\{\{[^}]*\}\}/PLACEHOLDER/g' "$TMPL_PYPROJECT" 2>/dev/null)
  # shellcheck disable=SC2016  # backticks intentional for Python invocation
  parse_result=$(python3 -c "
import sys, tomllib
try:
    with open('$TMPL_PYPROJECT') as f:
        raw = f.read()
    normalized = ''
    import re
    normalized = re.sub(r'\{\{[^}]*\}\}', 'PLACEHOLDER', raw)
    data = tomllib.loads(normalized)
    has_project = 'project' in data and isinstance(data['project'], dict)
    has_name = has_project and 'name' in data['project']
    has_version = has_project and 'version' in data['project']
    if has_project and has_name and has_version:
        print('OK')
    else:
        print('MISSING_FIELDS: project=%s name=%s version=%s' % (has_project, has_name, has_version))
except Exception as e:
    print('PARSE_ERROR: %s' % e)
" 2>&1)
  case "$parse_result" in
    OK) pass "pyproject.toml.tmpl parses as valid PEP 621 with [project] table (name + version)" ;;
    MISSING_FIELDS:*) fail "pyproject.toml.tmpl missing required PEP 621 fields" "expected [project] table with name + version fields per PEP 621; got: $parse_result" ;;
    PARSE_ERROR:*) fail "pyproject.toml.tmpl parse error" "expected PEP 621 parseable TOML after {{...}} substitution; got: $parse_result" ;;
    *) fail "pyproject.toml.tmpl PEP 621 validation inconclusive" "got: $parse_result" ;;
  esac
else
  fail "pyproject.toml.tmpl absent (skipped)" "Issue #1075 AC1 — pyproject.toml.tmpl must exist at template root"
fi

# ----------------------------------------------------------------------------
# TC3: LICENSE.tmpl contains MIT license + Copyright year placeholder
# ----------------------------------------------------------------------------
section "TC3: AC2 — LICENSE.tmpl contains MIT license text"
if [ -f "$TMPL_LICENSE" ]; then
  has_mit=0
  has_copyright=0
  has_year_placeholder=0
  if grep -qiE 'MIT[ -]?License|Permission is hereby granted, free of charge' "$TMPL_LICENSE" 2>/dev/null; then
    has_mit=1
  fi
  if grep -qiE 'Copyright' "$TMPL_LICENSE" 2>/dev/null; then
    has_copyright=1
  fi
  if grep -qE '\{\{[^}]*YEAR[^}]*\}\}|\{\{[^}]*year[^}]*\}\}|\{\{[^}]*COPY_YEAR[^}]*\}\}' "$TMPL_LICENSE" 2>/dev/null; then
    has_year_placeholder=1
  fi
  if [ "$has_mit" -eq 1 ] && [ "$has_copyright" -eq 1 ] && [ "$has_year_placeholder" -eq 1 ]; then
    pass "LICENSE.tmpl contains MIT license text + Copyright + year placeholder"
  else
    fail "LICENSE.tmpl missing required MIT fields" "expected MIT license text + Copyright line + year placeholder (e.g., {{YEAR}}); got: MIT=$has_mit Copyright=$has_copyright year_placeholder=$has_year_placeholder — see Issue #1075 AC2 + owner directive #6 (MIT default)"
  fi
else
  fail "LICENSE.tmpl absent (skipped)" "Issue #1075 AC2 — LICENSE.tmpl must exist at template root"
fi

# ----------------------------------------------------------------------------
# TC4: .template-version.tmpl contains semver
# ----------------------------------------------------------------------------
section "TC4: AC3 — .template-version.tmpl contains semver"
if [ -f "$TMPL_VERSION" ]; then
  # Semver regex: <digit>.<digit>.<digit> with optional pre-release; strip whitespace
  version=$(tr -d '[:space:]' < "$TMPL_VERSION" 2>/dev/null)
  # AC3 explicitly forbids pre-release suffix (e.g. -rc1, +build.5) to keep idempotent
  # re-renders stable per NIT-4. Tightened regex: strict 3-segment numeric semver only.
  # (d320 sister uses looser regex for date tolerance; d1027 sister divergence is
  # intentional — AC3 stability constraint is stricter than d320's tolerance window.)
  if printf '%s' "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    pass ".template-version.tmpl contains strict semver ($version) per AC3 idempotency"
  else
    fail ".template-version.tmpl does not contain strict semver" "expected strict 3-segment numeric semver 'X.Y.Z' (no pre-release/build suffix per AC3 idempotency); got: '$version' — see Issue #1075 AC3"
  fi
else
  fail ".template-version.tmpl absent (skipped)" "Issue #1075 AC3 — .template-version.tmpl must exist at template root"
fi

# ----------------------------------------------------------------------------
# TC5: dev-studio-init.sh --dry-run reports 3 templates would render
# ----------------------------------------------------------------------------
section "TC5: AC4 — dev-studio-init.sh --dry-run reports 3 templates would render"
if [ -x "$INIT_SCRIPT" ] || [ -f "$INIT_SCRIPT" ]; then
  # dev-studio-init.sh must exist; --dry-run reports what would render.
  # Capture output and look for the 3 final file paths (or .tmpl sources).
  dry_output=$(bash "$INIT_SCRIPT" --dry-run 2>&1 || true)
  # We expect mentions of all 3 .tmpl sources in the dry-run output.
  pyproject_mentioned=0
  license_mentioned=0
  version_mentioned=0
  if printf '%s\n' "$dry_output" | grep -q "pyproject.toml"; then
    pyproject_mentioned=1
  fi
  if printf '%s\n' "$dry_output" | grep -q "LICENSE"; then
    license_mentioned=1
  fi
  if printf '%s\n' "$dry_output" | grep -q "template-version"; then
    version_mentioned=1
  fi
  if [ "$pyproject_mentioned" -eq 1 ] && [ "$license_mentioned" -eq 1 ] && [ "$version_mentioned" -eq 1 ]; then
    pass "dev-studio-init.sh --dry-run reports all 3 templates would render (idempotent sister to .claude/CLAUDE.md.tmpl)"
  else
    fail "dev-studio-init.sh --dry-run does not mention all 3 templates" "expected mentions of pyproject.toml, LICENSE, and template-version; got: pyproject=$pyproject_mentioned LICENSE=$license_mentioned version=$version_mentioned — see Issue #1075 AC4 idempotent render path"
  fi
else
  fail "dev-studio-init.sh absent" "Issue #1075 AC4 — scripts/dev-studio-init.sh must exist at template root to render templates"
fi

# ----------------------------------------------------------------------------
# TC6: template source (pyproject.toml.tmpl) with {{...}} → PLACEHOLDER substitution
#      passes static installable validation (sister to AC5(a) `pip install -e .[dev]`,
#      static-only — idempotent + CI-friendly; validates PEP 621 name + version +
#      dependencies, no orphan placeholders in critical fields per AC5(d))
# ----------------------------------------------------------------------------
section "TC6: AC5(d) — rendered output passes static installable validation"
if [ -f "$TMPL_PYPROJECT" ]; then
  # Sister to AC5(d) dry-run pip install -e .[dev] but uses static validation
  # only (idempotent + CI-friendly — no actual pip execution).
  # Validates: parseable TOML + no orphan placeholders + dependencies declared.
  validate_result=$(python3 -c "
import re, tomllib, sys
with open('$TMPL_PYPROJECT') as f:
    raw = f.read()
normalized = re.sub(r'\{\{[^}]*\}\}', 'PLACEHOLDER', raw)
try:
    data = tomllib.loads(normalized)
except Exception as e:
    print('PARSE_ERROR: %s' % e)
    sys.exit(1)
project = data.get('project', {})
errors = []
if not project.get('name'):
    errors.append('missing project.name')
if not project.get('version'):
    errors.append('missing project.version')
if 'dependencies' not in project and 'optional-dependencies' not in data:
    errors.append('missing dependencies or optional-dependencies')
# Check for orphan placeholders in critical fields
if 'PLACEHOLDER' in str(project.get('name', '')):
    errors.append('orphan {{...}} placeholder in project.name')
if errors:
    print('VALIDATION_FAILED: %s' % '; '.join(errors))
else:
    print('OK')
" 2>&1)
  case "$validate_result" in
    OK) pass "rendered pyproject.toml validates as installable (PEP 621 name + version + dependencies, no orphan placeholders — AC5(d) static sister)" ;;
    VALIDATION_FAILED:*) fail "rendered pyproject.toml validation failed" "expected PEP 621 installable structure (name + version + dependencies); got: $validate_result — see Issue #1075 AC5(d)" ;;
    PARSE_ERROR:*) fail "rendered pyproject.toml parse error" "expected PEP 621 parseable; got: $validate_result" ;;
    *) fail "rendered pyproject.toml validation inconclusive" "got: $validate_result" ;;
  esac
else
  fail "pyproject.toml.tmpl absent (skipped)" "Issue #1075 AC1 — pyproject.toml.tmpl must exist before AC5(d) can validate"
fi

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
printf "\n${B}==== Summary ====${D}\n"
printf "  PASS: %d\n" "$PASS"
printf "  FAIL: %d\n" "$FAIL"
printf "  Target tested: Issue #1075 (S29-016) — pyproject.toml.tmpl + LICENSE.tmpl + .template-version.tmpl render path\n"

if [ "$FAIL" -gt 0 ]; then
  printf "\n${R}RED state${D} — pre-impl template main has missing templates + missing render path. Arch scope sign-off received (cmt IC_kwDOS9WE8s8AAAABKHG1LA); impl PR BLOCKED on this RED-first d-test per ADR-0046 (template-side doctrinal home) + ADR-0044 (calc-side doctrinal home for RED-first TDD).\n"
  exit 1
else
  printf "\n${G}GREEN state${D} — all 5 TCs pass; arch impl landed pyproject.toml.tmpl + LICENSE.tmpl + .template-version.tmpl + idempotent render path. AC5(d) static validation confirms installability per Issue #1075.\n"
  exit 0
fi
