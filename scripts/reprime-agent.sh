#!/usr/bin/env bash
# reprime-agent.sh — Soft re-prime an agent: re-read CLAUDE.md + role doc.
#
# Purpose
# -------
# When doctrine on `main` changes (new ADR, role-doc patch, CLAUDE.md edit),
# the running agent's system prompt may be stale. This script sends the
# agent a single chat message instructing it to re-read its source-of-truth
# files and re-align. No restart required.
#
# Behavior
# --------
# Soft, enqueued: the message goes into the agent's chat input queue. The
# agent finishes its current turn (and any larger in-flight work unit)
# before processing the re-prime. See docs/CONTEXT-HYGIENE.md § 5.
#
# Targeting strategy
# ------------------
# We address panes by their **deterministic pane index** in the tmux
# session, as defined by scripts/dev-studio-start.sh:
#
#     pane 0 = orchestrator
#     pane 1 = product-manager
#     pane 2 = architect
#     pane 3 = developer
#     pane 4 = tester
#     pane 5 = human  (not a re-prime target)
#
# Why not pane_title?
#   - Tried it. Claude Code overlays activity indicators (e.g. "*developer",
#     "· orchestrator") on top of the title set by `tmux select-pane -T`,
#     making title-based matching unreliable in practice.
#   - The launcher creates panes in a fixed split order — index is
#     deterministic and survives layout changes (we never reorder).
#
# If the launcher's layout ever changes, update both this map AND
# scripts/dev-studio-start.sh together. Keep them in lockstep.
#
# Does NOT:
#   - Clear conversation history (use full restart in scripts/dev-studio-start.sh).
#   - Touch agent-state.sh JSON (that's the watcher's domain).
#   - Modify any GitHub state.
#
# Usage
# -----
#   bash scripts/reprime-agent.sh <role>
#
# Where <role> is one of: orchestrator, product-manager, architect,
# developer, tester.
#
# Env overrides
# -------------
#   TMUX_SESSION  (default: dev-studio)
#   TMUX_WINDOW   (default: main)
#
# Exit codes
# ----------
#   0 — message sent.
#   1 — bad role or usage error.
#   2 — tmux session/window/pane not found, or role doc not found.

set -euo pipefail

TMUX_SESSION="${TMUX_SESSION:-dev-studio}"
TMUX_WINDOW="${TMUX_WINDOW:-main}"

# Role → pane index map. MUST match scripts/dev-studio-start.sh layout.
declare -A ROLE_PANE=(
  [orchestrator]=0
  [product-manager]=1
  [architect]=2
  [developer]=3
  [tester]=4
)

VALID_ROLES=(orchestrator product-manager architect developer tester)

usage() {
  echo "Usage: $0 <role>"
  echo "  role: ${VALID_ROLES[*]}"
  echo ""
  echo "Env overrides:"
  echo "  TMUX_SESSION  (default: dev-studio)"
  echo "  TMUX_WINDOW   (default: main)"
  exit 1
}

[ $# -eq 1 ] || usage
ROLE="$1"

# Validate role.
if [ -z "${ROLE_PANE[$ROLE]+x}" ]; then
  echo "ERROR: invalid role '$ROLE'"
  usage
fi
PANE_IDX="${ROLE_PANE[$ROLE]}"
TARGET="${TMUX_SESSION}:${TMUX_WINDOW}.${PANE_IDX}"

# Resolve role-doc path (try common locations).
ROLE_DOC=""
for candidate in \
  ".claude/agents/${ROLE}.md" \
  "docs/roles/${ROLE}.md" \
  "docs/agents/${ROLE}.md"; do
  if [ -f "$candidate" ]; then
    ROLE_DOC="$candidate"
    break
  fi
done

if [ -z "$ROLE_DOC" ]; then
  echo "ERROR: role doc for '$ROLE' not found in known locations."
  echo "  Tried: .claude/agents/${ROLE}.md, docs/roles/${ROLE}.md, docs/agents/${ROLE}.md"
  echo "  Run from the repo root."
  exit 2
fi

# Validate tmux session exists.
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "ERROR: tmux session '$TMUX_SESSION' not found."
  echo "  Start it via: scripts/dev-studio-start.sh start"
  exit 2
fi

# Validate window exists.
if ! tmux list-windows -t "$TMUX_SESSION" -F '#W' | grep -qx "$TMUX_WINDOW"; then
  echo "ERROR: tmux window '$TMUX_WINDOW' not found in session '$TMUX_SESSION'."
  echo "  Available windows:"
  tmux list-windows -t "$TMUX_SESSION" -F '    #W'
  exit 2
fi

# Validate target pane exists at the expected index.
if ! tmux list-panes -t "${TMUX_SESSION}:${TMUX_WINDOW}" -F '#P' | grep -qx "$PANE_IDX"; then
  echo "ERROR: pane index ${PANE_IDX} (expected for role '${ROLE}') not found in ${TMUX_SESSION}:${TMUX_WINDOW}."
  echo "  Available panes (index : title) — for diagnostics only, not used for targeting:"
  tmux list-panes -t "${TMUX_SESSION}:${TMUX_WINDOW}" -F '    #{pane_index} : #{pane_title}'
  echo ""
  echo "  Tip: the launcher creates panes 0..5 in a fixed order. If pane"
  echo "       ${PANE_IDX} is missing, the launcher's layout has changed"
  echo "       or panes have been killed individually. Run a full restart:"
  echo "       scripts/dev-studio-start.sh stop && scripts/dev-studio-start.sh start"
  exit 2
fi

# Build the re-prime message. The [REPRIME] prefix is the trigger the
# role doc REPRIME Protocol section reacts to.
MESSAGE="[REPRIME] Doctrine may have changed on main. Before your next action:
1. Finish any in-flight work unit (do not abandon partial work).
2. Re-read .claude/CLAUDE.md (project root) and ${ROLE_DOC}.
3. Discard any cached assumptions from this conversation about labels,
   PR state, or issue status. Re-query GitHub for the current ground
   truth before acting.
4. Acknowledge with: [REPRIME ACK] ${ROLE}: <one-line summary of any
   doctrine change noticed, or 'no change'>.
5. Resume normal duties under the refreshed doctrine."

# Use load-buffer + paste-buffer for safe multi-line input.
# `send-keys` with a multi-line string can mis-interpret newlines on
# some tmux versions; load/paste-buffer is the canonical safe path.
TMP_BUF="$(mktemp)"
trap 'rm -f "$TMP_BUF"' EXIT
printf '%s\n' "$MESSAGE" > "$TMP_BUF"

BUFFER_NAME="reprime-${ROLE}-$$"
tmux load-buffer -b "$BUFFER_NAME" "$TMP_BUF"
tmux paste-buffer -b "$BUFFER_NAME" -t "$TARGET" -p
tmux delete-buffer -b "$BUFFER_NAME"

# Submit the message to the agent's chat input.
tmux send-keys -t "$TARGET" Enter

echo "✓ Sent re-prime to ${TARGET} (role: ${ROLE}, pane index: ${PANE_IDX})"
echo "  Role doc: ${ROLE_DOC}"
echo "  Watch the pane for: [REPRIME ACK] ${ROLE}: ..."
echo "  If no ack within one polling cycle, see docs/CONTEXT-HYGIENE.md § 4.2."
