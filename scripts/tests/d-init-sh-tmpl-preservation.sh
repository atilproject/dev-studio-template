#!/usr/bin/env bash
# d-init-sh-tmpl-preservation.sh — Issue #201 / scripts/dev-studio-init.sh
#   regression guard: init.sh MUST preserve .tmpl source files when run in the
#   dev-studio-template source repo (where .tmpl files are git-tracked source).
#
# Why this test exists
# --------------------
# Sister-pattern to RETRO-022 / Issue #1023 (reflex-class damage — tool's
# "helper" pass destroys user state). Issue #201 documents that
# `scripts/dev-studio-init.sh` deletes `.tmpl` source files when rendering `.md`
# output. This breaks every soul-amend PR cycle because `.tmpl` files are the
# very files the PR commits, and init.sh is run between branch-open and
# `.tmpl` edit.
#
# Root cause: `render_one` in scripts/dev-studio-init.sh unconditionally
#   `rm -f "$src"` after rendering, with the contract comment:
#     "rendered repos should contain ONLY final files — leftover .tmpl files
#      are confusing for downstream consumers".
#   This contract is correct for CONSUMER projects (where .tmpl files are
#   ephemeral bootstrap inputs that should not leak into the rendered repo),
#   but WRONG for the TEMPLATE SOURCE REPO (where .tmpl files are committed
#   source of truth and must survive init.sh to support soul-amend PRs).
#
# Fix: gate the rm with a git-tracking check — only remove .tmpl files that
#   are NOT git-tracked. In source repos, .tmpl files are tracked → preserve.
#   In consumer projects, .tmpl files are untracked → rm as before.
#
# Test framework: bash + awk (extract render_one function) + temp git repo
#   (dynamic end-to-end on extracted function — bypasses init.sh's preflight
#   which requires real `gh` CLI + git config, sister-pattern to d1138 fake-tmux
#   in PATH idiom adapted to fake-render_one via subshell eval).
#
# ADR-0044 RED-first TDD: pre-impl on tmpl main HEAD expected to FAIL on
#   TC1-TC6 (rm fires unconditionally, deletes tracked .tmpl files). Post-impl
#   expected: all 7 TCs GREEN.
#
# Template-specific notes:
# - Target file: scripts/dev-studio-init.sh (line ~464 `rm -f "$src"` block)
# - Test setup: temp git repo with .tmpl files committed (mimics tmpl source)
# - Run: bash scripts/tests/d-init-sh-tmpl-preservation.sh
# - Cadence Rule 1 atomic per ADR-0055 §1: this file + INDEX.md row + impl
#   fix + CHANGELOG entry all in same commit
#
# Sister-pattern lineage:
#   - d1138-template-agent-wake-fix-4b.sh (direct sister — Issue #123 / ADR-0066
#     Fix 4b forward-port template regression guard, dynamic end-to-end idiom)
#   - d-s32-024-new-project-bootstrap-dry-run.sh (S32-024 / Issue #162 Phase A
#     e2e bootstrap verifier — temp-dir + real-invocation pattern)
#   - d024-agent-wake.sh (tmpl-local pre-existing dual-channel wake regression
#     test — grep-assertion idiom for static checks)
#
# Refs: Issue #201 (owner-filed P1 bug, 2026-07-20T17:53:17Z), arch 9-Lens
#       advisory cmt 5025488624 (NIT 1-4 application plan), RETRO-022 /
#       Issue #1023 (reflex-class damage sister-pattern), ADR-0044 (RED-first
#       TDD), ADR-0049 (d-test framework ≥5 baseline), ADR-0055 §1 (Cadence
#       Rule 1 atomic), ADR-0057 (Closes anchor strict format).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INIT_SH="$REPO_ROOT/scripts/dev-studio-init.sh"

# Pre-flight: ensure init.sh exists and is readable
if [ ! -f "$INIT_SH" ]; then
  echo "FATAL: $INIT_SH not found" >&2
  exit 99
fi

# Extract the render_one function from init.sh. This bypasses init.sh's
# preflight (gh CLI / git config checks) and tests the actual rm guard logic.
RENDER_ONE_FUNC=$(awk '/^render_one\(\)/{flag=1} flag{print} /^}/{if(flag){flag=0; exit}}' "$INIT_SH")

if [ -z "$RENDER_ONE_FUNC" ]; then
  echo "FATAL: could not extract render_one function from $INIT_SH" >&2
  exit 99
fi

# Set up isolated temp git repo mimicking dev-studio-template source layout
TMPDIR=$(mktemp -d -t d-init-sh-tmpl-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"
git init -q
git config user.email "d-init-sh-test@example.com"
git config user.name "d-init-sh-tmpl-preservation-test"

# Create .tmpl files matching dev-studio-template's actual structure
mkdir -p .claude/agents
TMPL_FILES=(
  ".claude/agents/architect.md.tmpl"
  ".claude/agents/developer.md.tmpl"
  ".claude/agents/orchestrator.md.tmpl"
  ".claude/agents/product-manager.md.tmpl"
  ".claude/agents/tester.md.tmpl"
  "CLAUDE.md.tmpl"
)
for tmpl_file in "${TMPL_FILES[@]}"; do
  echo "{{TEMPLATE_VERSION}}" > "$tmpl_file"
done

# Commit .tmpl files as git-tracked source (this is the source-repo condition
# that the fix must detect)
git add "${TMPL_FILES[@]}"
git commit -q -m "init: tracked .tmpl source files for d-init-sh test"

PASS=0
FAIL=0
FAILS=()

# Helper: invoke render_one against a tracked .tmpl file in the temp repo.
# We use bash -c with eval so the function's local vars (src, dst) work
# in the same subshell, and REPO_ROOT/DRY_RUN globals are exported.
invoke_render_one() {
  local tmpl_relpath="$1"
  local dst_relpath="$2"
  (
    # shellcheck disable=SC2030
    REPO_ROOT="$TMPDIR"
    DRY_RUN=0
    # Template variables used by render_one's sed pipeline — must be set to
    # avoid `set -u` abort before rm fires. Real init.sh populates these via
    # preflight; test bypasses preflight by supplying safe defaults.
    GITHUB_OWNER="${GITHUB_OWNER:-atilproject}"
    GITHUB_REPO="${GITHUB_REPO:-test}"
    HUMAN_OWNER_NAME="${HUMAN_OWNER_NAME:-Test}"
    PROJECT_NAME="${PROJECT_NAME:-test}"
    HEARTBEAT_DIR="${HEARTBEAT_DIR:-/tmp/heartbeat}"
    YEAR="${YEAR:-2026}"
    TEMPLATE_VERSION="${TEMPLATE_VERSION:-1.0.0}"
    eval "$RENDER_ONE_FUNC"
    render_one "$TMPDIR/$tmpl_relpath" "$TMPDIR/$dst_relpath" 2>/dev/null || true
  )
}

# --- TC1: architect.md.tmpl preserved after render_one ---
invoke_render_one ".claude/agents/architect.md.tmpl" ".claude/agents/architect.md"
if [ -f "$TMPDIR/.claude/agents/architect.md.tmpl" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILS+=("TC1: architect.md.tmpl was deleted by render_one (fix not applied)")
fi

# --- TC2: developer.md.tmpl preserved after render_one ---
invoke_render_one ".claude/agents/developer.md.tmpl" ".claude/agents/developer.md" >/dev/null 2>&1 || true
if [ -f "$TMPDIR/.claude/agents/developer.md.tmpl" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILS+=("TC2: developer.md.tmpl was deleted by render_one (fix not applied)")
fi

# --- TC3: orchestrator.md.tmpl preserved after render_one ---
invoke_render_one ".claude/agents/orchestrator.md.tmpl" ".claude/agents/orchestrator.md" >/dev/null 2>&1 || true
if [ -f "$TMPDIR/.claude/agents/orchestrator.md.tmpl" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILS+=("TC3: orchestrator.md.tmpl was deleted by render_one (fix not applied)")
fi

# --- TC4: product-manager.md.tmpl preserved after render_one ---
invoke_render_one ".claude/agents/product-manager.md.tmpl" ".claude/agents/product-manager.md" >/dev/null 2>&1 || true
if [ -f "$TMPDIR/.claude/agents/product-manager.md.tmpl" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILS+=("TC4: product-manager.md.tmpl was deleted by render_one (fix not applied)")
fi

# --- TC5: tester.md.tmpl preserved after render_one ---
invoke_render_one ".claude/agents/tester.md.tmpl" ".claude/agents/tester.md" >/dev/null 2>&1 || true
if [ -f "$TMPDIR/.claude/agents/tester.md.tmpl" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILS+=("TC5: tester.md.tmpl was deleted by render_one (fix not applied)")
fi

# --- TC6: CLAUDE.md.tmpl preserved after render_one ---
invoke_render_one "CLAUDE.md.tmpl" "CLAUDE.md" >/dev/null 2>&1 || true
if [ -f "$TMPDIR/CLAUDE.md.tmpl" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILS+=("TC6: CLAUDE.md.tmpl was deleted by render_one (fix not applied)")
fi

# --- TC7: regression guard — untracked .tmpl IS still deleted (preserved behavior) ---
# In a consumer project, .tmpl files are NOT git-tracked. The fix must NOT
# preserve them — they should still be removed after rendering.
UNTRACKED_TMPL="$TMPDIR/.claude/agents/consumer-test.md.tmpl"
echo "{{TEMPLATE_VERSION}}" > "$UNTRACKED_TMPL"
# Note: do NOT git add — leave it untracked
invoke_render_one ".claude/agents/consumer-test.md.tmpl" ".claude/agents/consumer-test.md" >/dev/null 2>&1 || true
if [ ! -f "$UNTRACKED_TMPL" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILS+=("TC7: regression — untracked .tmpl was preserved (consumer behavior broken)")
fi

# --- AC7 root-cause-confirm (informational grep, not a PASS/FAIL TC) ---
echo "AC7 root-cause-confirm (informational):"
grep -nE 'rm -f "\$src"|git ls-files' "$INIT_SH" | head -5 || echo "  (no rm -f or git ls-files references found)"

echo ""
echo "==== SUMMARY ===="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  Failures:"
  for f in "${FAILS[@]}"; do
    echo "    - $f"
  done
  exit 1
fi
exit 0
