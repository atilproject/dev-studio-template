#!/usr/bin/env bash
# d-template-version-resolver.sh — Closes tmpl#185 init.sh {{TEMPLATE_VERSION}} gap
#
# Why this test exists
# --------------------
# `scripts/dev-studio-init.sh` resolves 7 placeholders in its sed block
# (REPO_ROOT, GITHUB_OWNER, GITHUB_REPO, HUMAN_OWNER_NAME, PROJECT_NAME,
# HEARTBEAT_DIR, YEAR). 5 soul `.tmpl` files (orchestrator/architect/developer/
# tester/product-manager) declare `{{TEMPLATE_VERSION}}` on line 1 as a header
# marker — but the placeholder is NOT defined in init.sh, so rendering the
# template emits a file with a literal `{{TEMPLATE_VERSION}}` header. The
# post-render `verify()` step (line 506) detects this orphan marker and
# `exit 2`s the script.
#
# The regression breaks:
#   - Fresh project bootstrap (init.sh fails at first render)
#   - Downstream consumers of `dev-studio-template` (any clone that runs init.sh)
#   - Cross-repo workstream Issue #160 S32-020 Phase B (d-smoke-bootstrap-v110.sh
#     d-test reported 0/5 RED with this as the failure mode)
#
# AC (from Issue #185):
#   AC1 `{{TEMPLATE_VERSION}}` resolved in init.sh sed block + resolver defined
#   AC2 5 soul files render without error on smoke bootstrap at v1.1.0
#   AC3 d-test verifies all known placeholders resolve + no orphan placeholders
#       remain in .tmpl sources (this file, ≥5 TCs per ADR-0049)
#   AC4 INDEX.md entry registered per ADR-0055 §1
#   AC5 d-test GREEN before tmpl#160 Phase B re-attempt
#
# TC list (6 + TC0 preflight, RED-first per ADR-0044):
#   TC0 bash -n syntactic self-check (PASS pre/post hygiene)
#   TC1 init.sh sed block contains the TEMPLATE_VERSION substitution literal
#      (RED pre-fix — line absent; GREEN post-fix)
#   TC2 init.sh `resolve_values()` defines the TEMPLATE_VERSION resolver
#      (RED pre-fix — variable never assigned; GREEN post-fix)
#   TC3 All 8 known sed-block placeholders have matching -e entries
#      (orphan-resolver detection: RED pre-fix — only 7 entries; GREEN post-fix
#      — 8 entries)
#   TC4 No orphan placeholders in any .tmpl source under REPO_ROOT (excluding
#      the deferred `{{GITHUB_PROJECT_NUMBER}}` case in status-label-to-board.yml.tmpl)
#   TC5 `bash scripts/dev-studio-init.sh --help` exits 0 (smoke regression —
#      verifies script parses + arg-parser works; --help is used instead of
#      --dry-run because the latter triggers preflight (requires gh auth) +
#      resolve_values (requires gh repo view) which are out of scope for this
#      template-resolver regression test)
#   TC6 Cadence Rule 1 atomic — `scripts/tests/INDEX.md` has a d-template-version-
#      resolver row (RED pre-fix — absent; GREEN post-fix per ADR-0055 §1)
#
# Run: bash scripts/tests/d-template-version-resolver.sh
# Exit: 0 = all pass, 1 = at least one fail.
#
# Sister-pattern: d1025/d1026/d1027 (template-side d-test authoring conventions
# + INDEX.md row format per ADR-0055 §1); d1027 TC5 (init.sh --dry-run smoke).
# Lane: architect (init.sh resolver is architect territory per file ownership matrix).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_SH="$SCRIPT_DIR/../dev-studio-init.sh"
INDEX_MD="$SCRIPT_DIR/INDEX.md"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; Y=$'\033[0;33m'; D=$'\033[0m'
else
  G=""; R=""; B=""; Y=""; D=""
fi

PASS=0; FAIL=0
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

# Patterns used to assert sed-block presence. Defined as variables here so
# double-quoted messages do not trigger `set -u` unbound-variable errors when
# variable references appear in test-output strings.
PAT_TPL_VERSION='s|{{TEMPLATE_VERSION}}|${TEMPLATE_VERSION}|g'
SED_ENTRY_FMT='s|{{%s}}|${%s}|g'
KNOWN_PLACEHOLDERS_REGEX='\{\{(REPO_ROOT|GITHUB_OWNER|GITHUB_REPO|HUMAN_OWNER_NAME|PROJECT_NAME|HEARTBEAT_DIR|YEAR|TEMPLATE_VERSION|GITHUB_PROJECT_NUMBER)\}\}'

# ---------------------------------------------------------------------------
# TC0 — bash -n syntactic self-check
# ---------------------------------------------------------------------------
section 'TC0 — bash -n syntactic self-check'
if bash -n "$0" >/dev/null 2>&1; then
  pass 'test file parses (bash -n)'
else
  fail 'test file has bash syntax error' "bash -n $0"
fi

# ---------------------------------------------------------------------------
# TC1 — init.sh sed block contains TEMPLATE_VERSION substitution literal
# ---------------------------------------------------------------------------
section 'TC1 — sed block contains TEMPLATE_VERSION entry (AC1)'
if grep -qF "$PAT_TPL_VERSION" "$INIT_SH"; then
  pass 'init.sh sed block has TEMPLATE_VERSION substitution entry'
else
  fail 'init.sh sed block missing TEMPLATE_VERSION substitution' \
       'Expected literal in render_one() sed block after the YEAR line'
fi

# ---------------------------------------------------------------------------
# TC2 — resolve_values() defines TEMPLATE_VERSION resolver
# ---------------------------------------------------------------------------
section 'TC2 — resolve_values() defines TEMPLATE_VERSION resolver (AC1)'
# Match `TEMPLATE_VERSION=<something>` declaration. Reject commented-out lines.
if grep -E '^[[:space:]]*TEMPLATE_VERSION=' "$INIT_SH" | grep -vqE '^[[:space:]]*#'; then
  pass 'init.sh declares TEMPLATE_VERSION resolver in resolve_values()'
else
  fail 'init.sh does not define TEMPLATE_VERSION resolver variable' \
       'Expected: TEMPLATE_VERSION="..." line inside resolve_values()'
fi

# ---------------------------------------------------------------------------
# TC3 — all 8 known sed-block placeholders have matching -e entries
# ---------------------------------------------------------------------------
section 'TC3 — orphan-resolver detection (8 sed-block placeholders match)'
SED_BLOCK_PLACEHOLDERS=(
  'REPO_ROOT'
  'GITHUB_OWNER'
  'GITHUB_REPO'
  'HUMAN_OWNER_NAME'
  'PROJECT_NAME'
  'HEARTBEAT_DIR'
  'YEAR'
  'TEMPLATE_VERSION'
)
orphan_resolvers=0
for ph in "${SED_BLOCK_PLACEHOLDERS[@]}"; do
  expected=$(printf "$SED_ENTRY_FMT" "$ph" "$ph")
  if ! grep -qF "$expected" "$INIT_SH"; then
    fail "missing sed entry for {{${ph}}}" "Expected: ${expected}"
    orphan_resolvers=$((orphan_resolvers + 1))
  fi
done
if [ "$orphan_resolvers" -eq 0 ]; then
  pass 'all 8 known sed-block placeholders have matching -e entries'
fi

# ---------------------------------------------------------------------------
# TC4 — no orphan placeholders in any .tmpl source (orphan-template detection)
# ---------------------------------------------------------------------------
section 'TC4 — no orphan placeholders in .tmpl sources (AC3)'
# Known placeholders: 8 in sed block + 1 deferred (status-label-to-board.yml.tmpl).
orphan_files=$(find "$REPO_ROOT" \
  -path "$REPO_ROOT/.git" -prune -o \
  -path "$REPO_ROOT/.worktrees" -prune -o \
  -path "$REPO_ROOT/.dev-studio" -prune -o \
  -path "$REPO_ROOT/.tmux-bootstrap" -prune -o \
  -type f -name '*.tmpl' -print0 2>/dev/null \
  | xargs -0 grep -lE '\{\{[A-Z_][A-Z_0-9]*\}\}' 2>/dev/null || true)

orphan_count=0
if [ -z "$orphan_files" ]; then
  pass 'no .tmpl files contain placeholder markers (vacuous — no .tmpl to check)'
else
  for f in $orphan_files; do
    # Extract only orphan placeholders (NOT in known list)
    file_orphans=$(grep -oE '\{\{[A-Z_][A-Z_0-9]*\}\}' "$f" 2>/dev/null \
      | sort -u \
      | grep -vE "^${KNOWN_PLACEHOLDERS_REGEX}\$" || true)
    if [ -n "$file_orphans" ]; then
      fail "orphan placeholders in $f" "$file_orphans"
      orphan_count=$((orphan_count + 1))
    fi
  done
  if [ "$orphan_count" -eq 0 ]; then
    file_count=$(echo "$orphan_files" | wc -l | tr -d ' ')
    pass "all ${file_count} .tmpl files use only known placeholders"
  fi
fi

# ---------------------------------------------------------------------------
# TC5 — bash scripts/dev-studio-init.sh --help exits 0 (smoke regression)
# ---------------------------------------------------------------------------
section 'TC5 — init.sh --help exits 0 (AC2 smoke — script parses cleanly)'
# Use --help instead of --dry-run: --help exits 0 immediately (line 44-46)
# without triggering preflight (requires gh auth) or resolve_values (requires
# gh repo view). This proves the script parses + arg-parser works post-fix,
# independent of gh CLI availability in test env.
if (cd "$REPO_ROOT" && bash "$INIT_SH" --help >/dev/null 2>&1); then
  pass 'init.sh --help exited 0'
else
  rc=$?
  fail "init.sh --help failed (exit $rc)" \
       'Script parse error post-edit; bash -n dev-studio-init.sh to diagnose'
fi

# ---------------------------------------------------------------------------
# TC6 — Cadence Rule 1 INDEX.md row exists
# ---------------------------------------------------------------------------
section 'TC6 — INDEX.md row registered per ADR-0055 §1 (AC4)'
if [ -f "$INDEX_MD" ] && grep -q 'd-template-version-resolver' "$INDEX_MD"; then
  pass 'INDEX.md has d-template-version-resolver row'
else
  fail 'INDEX.md missing d-template-version-resolver row' \
       'Add a row per ADR-0055 §1 Cadence Rule 1 atomic — d-test + INDEX.md row in same commit'
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n${B}==== Summary ====${D}\n' 2>/dev/null || printf '\n==== Summary ====\n'
printf '  PASS: %d  FAIL: %d\n' "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then
  printf '  all TCs GREEN — tmpl#185 regression pinned\n'
  exit 0
else
  printf '  TCs failing — see messages above\n'
  exit 1
fi
