#!/usr/bin/env bash
# d081-auto-verdict-by-hook.sh — regression test for ADR-0024 §Path 2 (Auto-Verdict-By hook)
# Sister-pattern to calc's d081 (same contract). Source-of-truth: atilcan65/AtilCalculator
# scripts/peer-poke.sh (commit 981a9c1d, 6284 bytes, Issue #681, RETRO-016 #2).
#
# Why this test exists
# --------------------
# PR #296 (peer-poke.sh script) shipped in calc with the Auto-Verdict-By hook as
# sister-defensive code per ADR-0024 §Path 2. Sprint 28 S28-007 ports the whole
# peer-poke.sh wrapper (including the hook) from calc to tmpl's scripts/peer-poke.sh.tmpl.
# Without this d-test, future refactors + cross-repo drift can silently drop the
# hook → re-introduce the RETRO-016 #2 pathology (cc:<peer> without verdict-by:<ts>).
#
# Doctrinal contract (per ADR-0024 amendment §Path 2 + ADR-0044 ≥3 TCs RED-first):
#   TC1: peer-poke.sh.tmpl file exists + is executable (post-render: peer-poke.sh)
#   TC2: verdict-by + add-label pair invocation present (hook fires on target issue/PR)
#   TC3: atomic pairing doctrine — paired cc:<role> + verdict-by:<ts> in same gh edit
#   TC4: VERDICT_BY_DEFAULT_HOURS=24 (default deadline = +24h)
#   TC5: silent-skip idempotency on verdict-by:<ts> already present (no double-deadline overwrite)
#   TC6: gh-label-create pre-flight guard (Issue #1070) — pre-create verdict-by label if absent
#        in repo catalog before `gh issue/pr edit --add-label`, with `--force` for idempotency.
#
# Scope notes (per architect verdict on Issue #991, Path A approval):
#   - This d-test covers PATH 2 only (peer-poke.sh agent-side helper).
#   - PATH 1 (Layer 5 YAML hook in .github/workflows/label-check.yml) is
#     architect-owned territory per file ownership matrix — NOT covered here.
#   - Layer 5 YAML hook coverage belongs in a sister d-test (deferred to
#     a separate PR if/when the YAML hook is added to tmpl).
#
# Exit code: 0 = all pass, 1 = at least one fail.
# Run standalone: bash scripts/tests/d081-auto-verdict-by-hook.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PEER_POKE_TMPL="$SCRIPT_DIR/../peer-poke.sh.tmpl"
PEER_POKE_RENDERED="$SCRIPT_DIR/../peer-poke.sh"

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

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required" >&2; exit 127
fi

# Resolve which file to test: prefer the .tmpl source (Path A renders .tmpl → final).
# If only the rendered file is present (post-init repo), test that instead.
if [ -f "$PEER_POKE_TMPL" ]; then
  TARGET="$PEER_POKE_TMPL"
  TARGET_LABEL="scripts/peer-poke.sh.tmpl"
elif [ -f "$PEER_POKE_RENDERED" ]; then
  TARGET="$PEER_POKE_RENDERED"
  TARGET_LABEL="scripts/peer-poke.sh (rendered)"
else
  echo "ERROR: peer-poke.sh.tmpl (or peer-poke.sh post-render) not found" >&2
  echo "  Expected: $PEER_POKE_TMPL OR $PEER_POKE_RENDERED" >&2
  echo "  Per Issue #991 verdict Path A: peer-poke.sh.tmpl MUST be present in tmpl after S28-007." >&2
  exit 127
fi

# ============================================================================
# TC1: peer-poke.sh.tmpl file exists + is executable
# ============================================================================
section "TC1: peer-poke.sh target file exists + is executable"
if [ ! -f "$TARGET" ]; then
  fail "$TARGET_LABEL missing" "expected post-S28-007 Path A port (Issue #991 architect verdict)"
elif [ ! -x "$TARGET" ]; then
  fail "$TARGET_LABEL not executable" "expected +x bit preserved (dev-studio-init.sh §render_one preserves +x for *.tmpl shell templates)"
else
  pass "$TARGET_LABEL present + executable (6284 bytes expected, matches calc source-of-truth 981a9c1d)"
fi

# ============================================================================
# TC2: verdict-by + add-label pair invocation present (hook fires on target issue/PR)
# ============================================================================
section "TC2: verdict-by + add-label pair invocation present"
# Pattern: a paired gh issue edit / gh pr edit call that includes both the
# verdict-by label and the cc:<role> label in the same invocation (atomic per ADR-0015).
if ! grep -Eq 'verdict-by' "$TARGET"; then
  fail "verdict-by label reference missing" "expected 'verdict-by' string in hook payload (ADR-0024 §Schema additions)"
elif ! grep -Eq '_pair_verdict_by' "$TARGET"; then
  fail "_pair_verdict_by function missing" "expected helper function for verdict-by pairing per ADR-0024 §Path 2"
elif ! grep -Eq 'gh (issue|pr) edit.*--add-label' "$TARGET"; then
  fail "gh edit --add-label invocation missing" "expected atomic add-label call (ADR-0015 §Sıra zorunlu)"
else
  pass "verdict-by + add-label pair invocation present (atomic per ADR-0015)"
fi

# ============================================================================
# TC3: atomic pairing doctrine — paired cc:<role> + verdict-by:<ts> in same gh edit
# ============================================================================
section "TC3: atomic pairing doctrine (paired cc:<role> + verdict-by:<ts> in same gh edit)"
# Per ADR-0015 §Sıra zorunlu + ADR-0024 §Auto-Verdict-By Hook Contract §1.
# Pattern: labels_to_add variable concatenates both cc:<role> and verdict-by:<ts>
# before passing to a SINGLE --add-label invocation.
# Pattern A: `labels_to_add="cc:${role} ${verdict_by_label}"` on a single line
#            (verdict_by_label is the var that holds "verdict-by:<ts>")
# Pattern B: every `gh (issue|pr) edit ... --add-label` invocation must also
#            reference `$labels_to_add` on the same line (atomic per ADR-0015)
ASSIGN_OK=0
EDIT_OK=0
EDIT_USES_LABELS=0
if grep -Eq 'labels_to_add=.*cc:.*verdict_by_label' "$TARGET"; then
  ASSIGN_OK=1
fi
if grep -Eq 'gh (issue|pr) edit .*--add-label' "$TARGET"; then
  EDIT_OK=1
fi
# Check that AT LEAST ONE gh-edit line passes $labels_to_add
if grep -E 'gh (issue|pr) edit ' "$TARGET" | grep -qE 'labels_to_add'; then
  EDIT_USES_LABELS=1
fi
if [ "$ASSIGN_OK" -eq 0 ]; then
  fail "atomic pairing payload missing" "expected 'labels_to_add=\"cc:\${role} \${verdict_by_label}\"' single-line assignment (per ADR-0015 + ADR-0024)"
elif [ "$EDIT_OK" -eq 0 ]; then
  fail "atomic invocation gh-edit form missing" "expected 'gh (issue|pr) edit ... --add-label' invocation"
elif [ "$EDIT_USES_LABELS" -eq 0 ]; then
  fail "labels_to_add not used in gh edit invocation" "expected '\$labels_to_add' to be passed to 'gh (issue|pr) edit --add-label'"
else
  pass "atomic pairing doctrine present (cc:<role> + verdict-by:<ts> in single gh edit)"
fi

# ============================================================================
# TC4: VERDICT_BY_DEFAULT_HOURS=24 (default deadline = +24h)
# ============================================================================
section "TC4: VERDICT_BY_DEFAULT_HOURS=24 default deadline"
# Pattern: env var declaration with default value 24, used to compute ISO timestamp.
if ! grep -Eq 'VERDICT_BY_DEFAULT_HOURS.*24' "$TARGET"; then
  fail "VERDICT_BY_DEFAULT_HOURS default missing" "expected 'VERDICT_BY_DEFAULT_HOURS=\"${VERDICT_BY_DEFAULT_HOURS:-24}\"' per ADR-0024 §2"
elif ! grep -Eq '\+.*VERDICT_BY_DEFAULT_HOURS.*hour|timedelta.*hours.*VERDICT_BY_DEFAULT_HOURS|date.*VERDICT_BY_DEFAULT_HOURS' "$TARGET"; then
  fail "deadline computation missing" "expected python3 timedelta OR date -d to add VERDICT_BY_DEFAULT_HOURS to now()"
else
  pass "VERDICT_BY_DEFAULT_HOURS=24 default deadline present (ADR-0024 §2)"
fi

# ============================================================================
# TC5: silent-skip idempotency on verdict-by:<ts> already present
# ============================================================================
section "TC5: silent-skip idempotency (no double-deadline overwrite)"
# Per ADR-0024 §Auto-Verdict-By Hook Contract §3 (override allowed) + §4 (silent-skip).
# Pattern: grep existing labels for verdict-by: prefix; if present, exit early
# WITHOUT overwriting.
if ! grep -Eq 'verdict-by:.*already|silent_skip.*verdict-by|grep.*verdict-by' "$TARGET"; then
  fail "silent-skip idempotency check missing" "expected 'grep verdict-by' on existing labels with early-return branch (ADR-0024 §3 + §4)"
else
  pass "silent-skip idempotency present (verdict-by:<ts> already-set → no overwrite)"
fi

# ============================================================================
# TC6: gh-label-create pre-flight guard (Issue #1070)
# ============================================================================
section "TC6: gh label create pre-flight guard (Issue #1070 silent-failure fix)"
# Per Issue #1070: gh CLI refuses to add labels that don't exist in the repo's
# label catalog (returns "label not found"). peer-poke.sh's verdict-by auto-pair
# silently failed every invocation where the deadline timestamp was new (label
# had never been seen in the repo). Fix: peer-poke.sh must `gh label create`
# the verdict-by:<ts> label BEFORE `gh (issue|pr) edit --add-label`, with
# `--force` for idempotency on subsequent calls.
#
# Probe: both `gh label view` (presence check) AND `gh label create` (creation)
# must be present in peer-poke.sh. The view call guards against unnecessary
# create attempts; the create call is what actually populates the catalog.
LABEL_VIEW_GUARD=$(grep -cE 'gh label view' "$TARGET" || true)
LABEL_CREATE_GUARD=$(grep -cE 'gh label create' "$TARGET" || true)
LABEL_FORCE_GUARD=$(grep -cE -- '--force' "$TARGET" || true)
if [ "$LABEL_VIEW_GUARD" -ge 1 ] && [ "$LABEL_CREATE_GUARD" -ge 1 ] && [ "$LABEL_FORCE_GUARD" -ge 1 ]; then
  pass "gh label view + gh label create + --force pre-flight guard present (view=$LABEL_VIEW_GUARD, create=$LABEL_CREATE_GUARD, force=$LABEL_FORCE_GUARD)"
else
  fail "gh label create pre-flight guard absent" "expected 'gh label view' (presence check) + 'gh label create' (creation) + '--force' (idempotency) in peer-poke.sh before gh (issue|pr) edit --add-label per Issue #1070 fix"
fi

# ============================================================================
# Summary
# ============================================================================
echo
printf "${B}==== Summary ====${D}\n"
printf "  PASS: ${G}%d${D}\n" "$PASS"
printf "  FAIL: ${R}%d${D}\n" "$FAIL"
printf "  Target tested: %s\n" "$TARGET_LABEL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0