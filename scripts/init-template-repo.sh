#!/usr/bin/env bash
# init-template-repo.sh — STORY-S21-001 Template Flag Setup
#
# Why this script exists
# -----------------------
# Sprint 21 E1 (Template Repository Structure) S21-001 (Issue #630) demands
# that the `multi-agent-dev-studio-template` repo carry `is_template=true`
# so that GitHub UI shows the "Use this template" button and downstream
# `gh repo create --template` works end-to-end. Per ADR-0001 §1 (single-repo
# template architecture), the template IS AtilCalculator + its sister repo,
# and template flag is the operational gate. Without it, downstream adoption
# is blocked (S21-002..S25 are unreachable for end users).
#
# Sister-pattern: d073 RED-first regression guard (scripts/tests/d073-template-flag.sh)
# verifies 5 TCs (TC1-TC5) pass after this script runs. Pre-impl RED state:
# all 5 TCs FAIL because template flag is unset or repo missing.
#
# ADR-0045 lens (e) idempotency doctrine: re-running this script MUST be safe.
# Multiple invocations converge to the same end state (is_template=true).
#
# Usage:
#   MULTI_AGENT_DEV_STUDIO_TEMPLATE_REPO=foo/bar bash scripts/init-template-repo.sh
#   bash scripts/init-template-repo.sh --dry-run        # show what would happen, no API calls
#
# Exit codes:
#   0  success (is_template=true verified)
#   1  preflight failure (gh CLI missing, not authenticated, repo missing, etc.)
#   2  API call failure (PATCH rejected, etc.)
#   3  post-condition verification failure (flag not set after PATCH)
#
# Sister-patterns:
#   - scripts/dev-studio-init.sh (renders .tmpl files, similar preflight pattern)
#   - scripts/d070-init-template.sh (S21-005 LICENSE sister-pattern, deferred to Sprint 21+)
#
# Cross-references:
#   - Issue #630 — STORY-S21-001 carrier
#   - PR #655 — d073 d-test RED-first sister (tester lane)
#   - ADR-0001 — single-repo template architecture
#   - ADR-0016 — public-by-default visibility
#   - ADR-0045 — 9-Lens Review Checklist (lens e idempotency)
#   - ADR-0049 — d-test framework sister-pattern
#
# Pre-flight: must be run by repo OWNER (gh CLI authenticated as the org owner).
# Default org is `atilproject` (canonical for dev-studio-template); override via
# the ORG env var if your downstream repo lives under a different org. PAT requires
# `repo` scope for PATCH endpoint.

set -euo pipefail

# --- Configuration --------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Help handler first — must short-circuit BEFORE the required-env-var check
# so `bash scripts/init-template-repo.sh --help` works without setting vars.
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

# Source ~/.dev-studio-env (AC3 contract from STORY-S21-010 / Issue #642) —
# best-effort; absent file is OK (this script may run before dev-studio-init).
[ -f "${HOME}/.dev-studio-env" ] && . "${HOME}/.dev-studio-env" 2>/dev/null || true
# Required env var, no hardcoded default. Sister-pattern: agent-watch.sh
# (e48dd96). Clone projects must opt-in via env or --repo-style flag.
TEMPLATE_REPO="${MULTI_AGENT_DEV_STUDIO_TEMPLATE_REPO:?MULTI_AGENT_DEV_STUDIO_TEMPLATE_REPO env var required (e.g., \${GITHUB_OWNER}/multi-agent-dev-studio-template)}"

DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

# --- Pre-flight -----------------------------------------------------------

# 1. gh CLI present and authenticated
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI required (https://cli.github.com)" >&2; exit 1; }
if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh not authenticated — run 'gh auth login' first" >&2
  exit 1
fi

# 2. jq present (used for --jq queries)
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required for JSON parsing" >&2; exit 1; }

# 3. Verify TEMPLATE_REPO owner matches authenticated user (auth boundary)
AUTH_USER=$(gh api user --jq .login)
EXPECTED_OWNER="${TEMPLATE_REPO%%/*}"
if [ "$AUTH_USER" != "$EXPECTED_OWNER" ]; then
  echo "ERROR: authenticated as '$AUTH_USER', but TEMPLATE_REPO='$TEMPLATE_REPO' requires owner '$EXPECTED_OWNER'" >&2
  echo "       either re-authenticate as '$EXPECTED_OWNER' or set MULTI_AGENT_DEV_STUDIO_TEMPLATE_REPO=${AUTH_USER}/<repo>" >&2
  exit 1
fi

# --- Main -----------------------------------------------------------------

echo "TEMPLATE_REPO=$TEMPLATE_REPO (owner: $AUTH_USER)"
echo

# Step 1: Verify repo exists
echo "[1/3] Verifying repo exists..."
if ! gh api "repos/${TEMPLATE_REPO}" >/dev/null 2>&1; then
  echo "ERROR: ${TEMPLATE_REPO} does not exist or is not accessible" >&2
  echo "       Owner must create the repo first:" >&2
  echo "         gh repo create ${TEMPLATE_REPO} --public \\" >&2
  echo "           --description 'Multi-Agent Dev Studio Template' \\" >&2
  echo "           --clone=false" >&2
  echo "       Then re-run this script." >&2
  exit 1
fi
echo "  ✓ repo exists"

# Step 2: Read current is_template state
echo "[2/3] Reading current is_template state..."
CURRENT_FLAG=$(gh api "repos/${TEMPLATE_REPO}" --jq .is_template)
echo "  current is_template=$CURRENT_FLAG"

# Step 3: PATCH is_template=true (idempotent — re-PATCH true stays true per ADR-0045 lens e)
if [ "$CURRENT_FLAG" = "true" ]; then
  echo "[3/3] is_template already true — no-op (idempotent per ADR-0045 lens e)"
else
  echo "[3/3] PATCHing is_template=true..."
  if [ "$DRY_RUN" = "1" ]; then
    echo "  (dry-run: would PATCH repos/${TEMPLATE_REPO} -f is_template=true)"
  else
    PATCH_RESULT=$(gh api -X PATCH "repos/${TEMPLATE_REPO}" -f is_template=true)
    NEW_FLAG=$(echo "$PATCH_RESULT" | jq -r .is_template)
    if [ "$NEW_FLAG" != "true" ]; then
      echo "ERROR: PATCH did not set flag (got is_template=$NEW_FLAG)" >&2
      echo "       Response: $PATCH_RESULT" >&2
      exit 3
    fi
    echo "  ✓ PATCH succeeded, is_template=true"
  fi
fi

# --- Post-condition verification ------------------------------------------

echo
echo "Post-condition verification:"
VERIFY=$(gh api "repos/${TEMPLATE_REPO}" --jq .is_template)
if [ "$VERIFY" = "true" ]; then
  echo "  ✅ is_template=true confirmed on ${TEMPLATE_REPO}"
  echo
  echo "Next steps:"
  echo "  - d073 regression guard should now PASS: bash scripts/tests/d073-template-flag.sh --self-test"
  echo "  - 'Use this template' button should appear on GH UI"
  echo "  - 'gh repo create <new> --template ${TEMPLATE_REPO}' should work end-to-end"
  exit 0
else
  echo "  ❌ is_template=$VERIFY (expected true)" >&2
  exit 3
fi