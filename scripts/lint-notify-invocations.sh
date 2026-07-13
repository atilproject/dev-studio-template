#!/usr/bin/env bash
# lint-notify-invocations.sh — detect broken notify.sh -l <role> syntax in PR diffs.
#
# Why this exists
# ----------------
# Issue #320 RCA found broken `notify.sh -l <role>` syntax in 22 places
# across 6 files (CLAUDE.md + 5 soul files). The doctrine was either never
# validated against the script, or the script changed and the doctrine
# wasn't updated. Sprint 3+ peer-pings have been silently broken for months.
#
# This script greps a PR diff for the broken pattern and emits a structured
# report. Owners can wire it into CI to block merges that re-introduce the
# broken syntax. With `--post-comment`, it posts a GH PR comment listing the
# violations.
#
# Usage:
#   scripts/lint-notify-invocations.sh <pr-number> [--post-comment]
#
# Exit codes:
#   0 — clean (no broken syntax)
#   1 — broken syntax found
#   2 — usage error (no PR number)
#
# Reference: Issue #320 RCA, ADR-0033 (dual-channel), CLAUDE.md §Auto-Ping.

set -uo pipefail

PR_NUMBER="${1:-}"
POST_COMMENT=0
[ "${2:-}" = "--post-comment" ] && POST_COMMENT=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -z "$PR_NUMBER" ]; then
  echo "usage: $0 <pr-number> [--post-comment]" >&2
  echo "  example: $0 322" >&2
  exit 2
fi

command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI required" >&2; exit 1; }

# Fetch PR diff (markdown-body form for human-readable comments; raw diff for matching).
DIFF="$(gh pr diff "$PR_NUMBER" 2>/dev/null || true)"
if [ -z "$DIFF" ]; then
  echo "ERROR: could not fetch diff for PR #$PR_NUMBER" >&2
  exit 1
fi

# Broken pattern: `notify.sh` followed (anywhere on the line) by `-l <role>`
# where <role> is one of the agent role names. We exclude info|warn|error|ok
# by anchoring on word-boundary role names.
# PCRE: -l <role> followed by non-lowercase (so 'developerx' won't match).
BROKEN_PATTERN='notify\.sh.*-l[[:space:]]+(orchestrator|product-manager|architect|developer|tester|human)([^a-z_-]|$)'

# Scan only added lines (lines starting with +, not +++) to avoid matching
# context lines. Use grep -nE for line numbers.
VIOLATIONS="$(printf '%s' "$DIFF" | grep -nE '^\+[^+]' | grep -E "$BROKEN_PATTERN" || true)"

if [ -n "$VIOLATIONS" ]; then
  echo "BROKEN: notify.sh -l <role> syntax found in PR #$PR_NUMBER (Issue #320):"
  echo "$VIOLATIONS" | while IFS= read -r line; do
    echo "  $line"
  done
  echo ""
  echo "Fix: use 'scripts/ping.sh <role> <message>' (canonical wrapper) or"
  echo "     'scripts/notify.sh -l info -w -r <role> <message>' (manual correct form)."

  if [ "$POST_COMMENT" -eq 1 ]; then
    COMMENT_BODY="## 🔔 lint-notify-invocations.sh — broken syntax detected (Issue #320)

PR diff contains \`notify.sh -l <role>\` invocations. The \`-l\` flag is a LOG LEVEL (info|warn|error|ok), not a role. This pattern silently falls through to Telegram-only delivery and the target agent's tmux pane never wakes.

### Violations

\`\`\`
$(printf '%s' "$VIOLATIONS" | head -10)
\`\`\`

### Fix

- **Canonical**: \`scripts/ping.sh <role> <message>\` (cannot be misused)
- **Manual**: \`scripts/notify.sh -l info -w -r <role> <message>\` (ADR-0033 dual-channel)

Refs: Issue #320, ADR-0033, CLAUDE.md §Auto-Ping Hard-Rule.

— auto-posted by scripts/lint-notify-invocations.sh"
    gh pr comment "$PR_NUMBER" --body "$COMMENT_BODY" >/dev/null 2>&1 || true
    echo "Posted PR comment."
  fi
  exit 1
fi

echo "OK: no broken notify.sh -l <role> syntax in PR #$PR_NUMBER"
exit 0
