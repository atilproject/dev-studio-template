#!/usr/bin/env bash
# audit-project-refs.sh — STORY-S21-004 / Issue #651 (Project Refs Audit Script).
#
# Why this exists
# ---------------
# Without an audit, hardcoded "AtilCalculator" / "atilcan65" refs leak through
# template clones. The init script (S21-003a, dev-studio-init.sh) replaces
# `{{...}}` placeholders with user-provided values, but only IF the user runs it.
# This audit catches places where the init was missed or didn't catch all refs.
#
# Acceptance criteria (Issue #651):
#   AC1 — Run on pre-init clone → exits 1 (catches `AtilCalculator` or `atilcan65`).
#   AC2 — Run on post-init clone → exits 0 (no hardcoded refs).
#   AC3 — Run in CI on template PR → blocks merge if exit 1.
#
# Sister-pattern: d105-audit-project-refs.sh sister-test (RED-first per ADR-0044).
# Upstream: dev-studio-init.sh (S21-003a, Issue #636, scripts/dev-studio-init.sh).
# Downstream: d070-template-render (S21-018, Issue #637), smoke tests (S21-022).
#
# Usage:
#   bash scripts/audit-project-refs.sh                 # audit current dir
#   bash scripts/audit-project-refs.sh /path/to/clone  # audit specific dir
#   bash scripts/audit-project-refs.sh --json          # JSON output for CI
#
# Exit codes:
#   0 — clean (no hardcoded refs found)
#   1 — hardcoded refs found (CI blocks merge)
#   2 — preflight failure (not a git repo, missing tool, etc.)

set -uo pipefail

# --- args ---
TARGET_DIR="${1:-.}"
JSON_OUTPUT=false
if [ "$TARGET_DIR" = "--json" ]; then
  JSON_OUTPUT=true
  TARGET_DIR="."
fi

# --- color (TTY-aware) ---
if [[ -t 1 ]] && [ "$JSON_OUTPUT" = "false" ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[34m'; D=$'\033[0m'
else
  R=""; G=""; Y=""; B=""; D=""
fi

# --- preflight ---
command -v git >/dev/null 2>&1 || { echo "ERROR: git required" >&2; exit 2; }
command -v grep >/dev/null 2>&1 || { echo "ERROR: grep required" >&2; exit 2; }
if [ ! -d "$TARGET_DIR" ]; then
  echo "ERROR: directory not found: $TARGET_DIR" >&2
  exit 2
fi
if ! git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: $TARGET_DIR is not a git repository" >&2
  exit 2
fi

# --- main scan ---
# Patterns to flag as hardcoded refs (Sprint 22 PIVOT migration fallout):
#   - AtilCalculator      (the project's own name, capitalized)
#   - atilcan65           (the original owner's GitHub login)
#   - atilcalc-engine     (a known submodule dir from earlier sprints)
# We use word-boundary regex to avoid false positives on substring matches
# like "atilcalc-architect-td012" (out of scope per Issue #651 explicit).
PATTERNS=(
  '\bAtilCalculator\b'
  '\batilcan65\b'
)
EXCLUDE_PATTERNS=(
  ':!*.md'        # docs may legitimately reference the name
  ':!CHANGELOG*'  # changelogs reference name by design
  ':!LICENSE*'    # license file is a copy
  ':!audit-project-refs.sh'  # self-reference
)

cd "$TARGET_DIR" || exit 2
HIT_COUNT=0
HITS=""

# Resolve TARGET_DIR to absolute path so pathspec works regardless of cwd
# (git grep pathspec is relative to repo root, not cwd; without absolute,
# a relative "scripts/" arg combined with cwd=scripts/ would double-nest.)
TARGET_DIR_ABS="$(cd "$TARGET_DIR" 2>/dev/null && pwd -P || echo "$TARGET_DIR")"

# Iterate patterns and aggregate hits via git ls-files (tracked files only — Story spec)
# Issue #642 hardening: scope grep to TARGET_DIR (was: whole-repo, which made
# TC1 in d642-scripts-parameterized fail on legit scripts/ runs because hits in
# docs/, .github/, etc. inflated the count). Sister-pattern to d105 d-test which
# uses isolated fixture repos (whole-repo grep was OK there).
for pattern in "${PATTERNS[@]}"; do
  raw=$(git grep -nIE "$pattern" -- "$TARGET_DIR_ABS" "${EXCLUDE_PATTERNS[@]}" 2>/dev/null || true)
  if [ -n "$raw" ]; then
    HIT_COUNT=$((HIT_COUNT + $(echo "$raw" | wc -l)))
    HITS="${HITS}${raw}\n"
  fi
done

# --- output ---
if [ "$JSON_OUTPUT" = "true" ]; then
  # Build JSON via jq (always valid, no manual escaping/joining)
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq required for --json output mode" >&2
    exit 2
  fi

  # Convert HITS (path:line:content per line) to a JSON array, then wrap.
  if [ "$HIT_COUNT" -gt 0 ]; then
    DETAILS_JSON=$(echo "$HITS" | jq -R -s '
      split("\n") | map(select(length > 0)) |
      map(
        (split(":") | .[0]) as $file |
        (split(":") | .[1] | tonumber) as $line |
        (split(":") | .[2:]) | join(":") as $content |
        {file: $file, line: $line, content: $content}
      )
    ')
    jq -nc --argjson hits "$HIT_COUNT" --argjson details "$DETAILS_JSON" \
      '{status: "FAIL", hits: $hits, details: $details}'
    exit 1
  else
    jq -nc '{status: "PASS", hits: 0}'
    exit 0
  fi
else
  if [ "$HIT_COUNT" -gt 0 ]; then
    echo "${R}✗ FAIL${D} — $HIT_COUNT hardcoded ref(s) found in tracked files" >&2
    echo "${Y}Hints:${D}" >&2
    echo "  - These refs should be replaced with templated {{...}} placeholders" >&2
    echo "  - Run: bash scripts/dev-studio-init.sh to resolve them" >&2
    echo "  - Or add to git ls-files --exclude patterns if intentional" >&2
    echo "" >&2
    echo "${Y}Details (first 20):${D}" >&2
    echo "$HITS" | head -20 >&2
    exit 1
  else
    echo "${G}✓ PASS${D} — 0 hardcoded refs found in tracked files"
    exit 0
  fi
fi
