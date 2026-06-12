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
# Panes are located by their `pane_title`, which each agent sets in its
# own bootstrap script via `tmux select-pane -T "<ROLE_UPPER>"`. Title
# survives pane-index reassignment caused by layout changes, kills, or
# splits — so this script is robust against the user rearranging panes.
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
valid=0
for r in "${VALID_ROLES[@]}"; do
  [ "$r" = "$ROLE" ] && valid=1 && break
done
if [ "$valid" = "0" ]; then
  echo "ERROR: invalid role '$ROLE'"
  usage
fi

ROLE_UPPER="$(echo "$ROLE" | tr '[:lower:]' '[:upper:]')"

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

# Find the pane whose pane_title equals ROLE_UPPER.
# Format: "<pane_index>:<pane_title>" per line.
PANE_LINE="$(
  tmux list-panes -t "${TMUX_SESSION}:${TMUX_WINDOW}" -F '#{pane_index}:#{pane_title}' \
    | grep -E ":${ROLE_UPPER}\$" || true
)"

if [ -z "$PANE_LINE" ]; then
  echo "ERROR: no pane with title '${ROLE_UPPER}' in ${TMUX_SESSION}:${TMUX_WINDOW}."
  echo "  Available panes (index:title):"
  tmux list-panes -t "${TMUX_SESSION}:${TMUX_WINDOW}" -F '    #{pane_index}:#{pane_title}'
  echo ""
  echo "  Tip: each agent bootstrap sets its own title with"
  echo "       'tmux select-pane -T <ROLE>'. If the title is missing,"
  echo "       the bootstrap may not have run — try full restart."
  exit 2
fi

PANE_IDX="${PANE_LINE%%:*}"
TARGET="${TMUX_SESSION}:${TMUX_WINDOW}.${PANE_IDX}"

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

echo "✓ Sent re-prime to ${TARGET} (role: ${ROLE}, title: ${ROLE_UPPER})"
echo "  Role doc: ${ROLE_DOC}"
echo "  Watch the pane for: [REPRIME ACK] ${ROLE}: ..."
echo "  If no ack within one polling cycle, see docs/CONTEXT-HYGIENE.md § 4.2."
