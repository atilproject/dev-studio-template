#!/usr/bin/env bash
# scripts/pre-push/branch-base-check.sh — RETRO-009 §1 pre-push chain dep pollution prevention hook.
#
# Sister-pattern to the existing direct-push-to-main prevention hook. Invoked by
# git before `git push`. Reads stdin per git pre-push contract:
#   <local_ref> <local_sha> <remote_ref> <remote_sha>
# (one line per ref being pushed)
#
# Detects chain dep pollution (RETRO-009 §1, PR #509 LIVE INSTANCE):
#   - Branch base stale (origin/main advanced past branch point) → chain dep
#   - Commit messages reference squash-merge / PR #N squash → chain dep
#
# Exit codes (per ADR-0044 RED-first contract):
#   0 — branch base is clean, safe to push
#   1 — chain dep pollution detected, push blocked (informative message)
#   2 — config error (non-git dir, no origin/main ref)
#
# Sister-pattern: d060-branch-base-check.sh (9 TCs regression test)
#
# Run standalone for testing: bash scripts/pre-push/branch-base-check.sh < /dev/null
# Real git invocation: git push (hook auto-fires)

set -uo pipefail

# --- preflight: must be in a git repo ---
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not in a git repository (branch-base-check requires git)" >&2
  exit 2
fi

# --- read stdin (git pre-push contract) ---
# Use a temp file to capture stdin, then iterate via `<<<` to avoid the
# classic `cat | while` subshell pitfall (subshell exits with side effects lost).
stdin_file="$(mktemp)"
trap 'rm -f "$stdin_file"' EXIT
cat > "$stdin_file"

# Empty stdin = nothing to check (e.g., --no-verify bypass or no refs)
if [ ! -s "$stdin_file" ]; then
  exit 0
fi

# --- preflight: origin/main must exist ---
if ! git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
  echo "ERROR: origin/main ref not found (run 'git fetch origin' first)" >&2
  exit 2
fi

# --- check each ref being pushed ---
while IFS=' ' read -r local_ref local_sha remote_ref remote_sha; do
  # Skip deletions (0000000000000000000000000000000000000000 sha)
  if [ "$local_sha" = "0000000000000000000000000000000000000000" ]; then
    continue
  fi

  # Skip non-branch refs (tags, notes, etc.)
  if [[ "$local_ref" != refs/heads/* ]]; then
    continue
  fi

  branch="${local_ref#refs/heads/}"

  # Resolve to full SHA
  head_sha="$(git rev-parse "$local_sha" 2>/dev/null)"
  if [ -z "$head_sha" ]; then
    continue
  fi

  # --- Check 1: origin/main must be an ancestor of HEAD ---
  # If origin/main is NOT an ancestor of HEAD, the branch is missing
  # squashed commits from main (chain dep pollution, RETRO-009 §1).
  if ! git merge-base --is-ancestor origin/main "$head_sha" 2>/dev/null; then
    echo "ERROR: branch '$branch' is missing squashed commits from origin/main" >&2
    echo "       chain dep pollution detected (RETRO-009 §1, PR #509 LIVE INSTANCE)" >&2
    echo "       fix: git fetch origin && git rebase origin/main" >&2
    exit 1
  fi

  # --- Check 2: scan commits unique to this branch for squash-merge references ---
  # Patterns detected (sister-pattern to chain dep pollution, PR #509 origin):
  #   - "Refs #N squash"
  #   - "PR #N squash"
  #   - "squash-merge"
  #   - "squashed"
  # Limit scan to commits not on origin/main (i.e., unique to this branch).
  chain_dep_commits="$(git log origin/main.."$head_sha" --format=%s 2>/dev/null | \
    grep -iE '(refs #[0-9]+.*squash|pr #[0-9]+.*squash|squash-merge|squashed)' || true)"
  if [ -n "$chain_dep_commits" ]; then
    echo "ERROR: branch '$branch' contains commits referencing squash-merge (chain dep)" >&2
    echo "       offending commits:" >&2
    echo "$chain_dep_commits" | sed 's/^/         /' >&2
    echo "       fix: git rebase origin/main to drop these commits" >&2
    exit 1
  fi
done < "$stdin_file"

exit 0