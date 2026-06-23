#!/usr/bin/env bash
# scripts/owner-apply-soul-patch.sh (TEMPLATE PORT for Issue #287)
#
# Owner-only command to verify §Doctrine Reminder is in all 4 shared soul
# .tmpl files. Idempotent — if already present, this is a no-op (4/4 covered).
#
# Closes Issue #287 (template port of Issue #280 AtilCalc soul-patch).
# Sister script: AtilCalculator scripts/owner-apply-soul-patch.sh.
#
# File ownership matrix: .claude/ is human-only territory. This script is
# INTENDED to be run by owner, but is idempotent + safe (no-ops if already
# patched, validates 4/4 coverage otherwise).
#
# TEMPLATE ADAPTION vs AtilCalculator version:
#   - Targets .md.tmpl files (template storage format), not .md (rendered)
#   - Branch name references Issue #287 (template port), not #280 (AtilCalc)
#   - Does NOT push or open PR (template is owner-gated; human runs bootstrap)
#   - Verifies 5/5 coverage (developer/architect/product-manager/tester +
#     orchestrator — orchestrator already has the section per template design)
#
# USAGE: bash scripts/owner-apply-soul-patch.sh
#
# This script:
#   - Validates current state of 4 target .tmpl files
#   - Reports any missing §Doctrine Reminder sections
#   - Exits 0 if 4/4 covered (idempotent no-op)
#   - Exits 1 if any .tmpl file is missing the section (needs owner apply)

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SOUL_DIR=".claude/agents"
# Template port targets .tmpl files (template storage format).
# orchestrator.md.tmpl already has the section per template design (skip).
TARGETS=("developer.md.tmpl" "architect.md.tmpl" "product-manager.md.tmpl" "tester.md.tmpl")
SECTION_HEADING="## Doctrine Reminder — no self-standby"

echo "→ verifying §Doctrine Reminder coverage in 4 shared soul .tmpl files"
echo "  target dir: $SOUL_DIR"
echo "  targets: ${TARGETS[*]}"

# Idempotent verify: 4/4 .tmpl files must already have the section.
# If any missing, report and exit 1 (owner decides whether to apply).
uncovered=()
for f in "${TARGETS[@]}"; do
  TARGET="$SOUL_DIR/$f"
  if [ ! -f "$TARGET" ]; then
    echo "  ✗ MISSING: $TARGET"
    uncovered+=("$f")
    continue
  fi
  if ! grep -qF "$SECTION_HEADING" "$TARGET" 2>/dev/null; then
    echo "  ✗ UNCOVERED: $TARGET (no §Doctrine Reminder section)"
    uncovered+=("$f")
  else
    echo "  ✓ covered: $TARGET"
  fi
done

if [ "${#uncovered[@]}" -gt 0 ]; then
  echo ""
  echo "ERROR: ${#uncovered[@]} .tmpl file(s) missing §Doctrine Reminder:"
  echo "  ${uncovered[*]}"
  echo ""
  echo "This is the template-side equivalent of AtilCalc Issue #280."
  echo "Per Issue #287 spec, this script is INTENDED to be idempotent no-op"
  echo "because the template's .tmpl files already contain the section."
  echo ""
  echo "If you see this error, manually patch the missing .tmpl files with"
  echo "the same §Doctrine Reminder block from AtilCalc .claude/agents/orchestrator.md"
  echo "(or reference PR #288's commit content)."
  exit 1
fi

COVERED=$(grep -lF "$SECTION_HEADING" $SOUL_DIR/*.md.tmpl | wc -l)
echo ""
echo "✅ 4/4 .tmpl files covered: $(grep -lF "$SECTION_HEADING" $SOUL_DIR/*.md.tmpl | xargs -n1 basename | sort | tr '\n' ',' | sed 's/,$//')"
echo "  (total .tmpl files with §Doctrine Reminder: $COVERED — includes orchestrator.md.tmpl)"
echo ""
echo "Idempotent no-op — template soul-coverage invariant satisfied."
echo "Next: run 'bash scripts/tests/d033-4-soul-coverage.sh' to verify regression test passes."
exit 0