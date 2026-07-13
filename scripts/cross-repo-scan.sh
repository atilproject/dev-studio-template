#!/usr/bin/env bash
# cross-repo-scan.sh — Orchestrator cross-repo fleet scan (ADR-0047 Part 2)
#
# Why this script exists
# ----------------------
# ADR-0047 §Decision Part 2: orchestrator owns fleet-wide cross-repo visibility.
# This script complements the per-agent `scripts/agent-watch.sh --repo` polling
# (ADR-0047 Part 1) by providing a centralized scan that catches PRs in repos
# NOT covered by any agent's `AGENT_WATCH_REPOS` config (config drift recovery).
#
# Sister to scripts/agent-watch.sh (Part 1): same multi-REPO pattern, but:
#   - queries PRs only (issues stay per-agent polling)
#   - dispatches via peer-poke.sh (not into the agent's own queue)
#   - emits `cross_repo_dispatch` audit log event
#   - lower frequency (5 min default vs 60s agent-watch)
#
# Operational contract (ADR-0042 §Orchestrator role):
#   - Run by orchestrator's autonomy loop (cron or systemd timer)
#   - Cadence: CROSS_REPO_SCAN_INTERVAL_SEC (default 300s = 5 min)
#   - Defense in depth with Part 1: even if all agents miss a cross-repo PR,
#     orchestrator scan catches it within 5 min.
#
# Usage:
#   scripts/cross-repo-scan.sh               # one-shot scan (default repos)
#   scripts/cross-repo-scan.sh --loop        # loop forever (sleeps CROSS_REPO_SCAN_INTERVAL_SEC)
#
# Env:
#   AGENT_CROSS_REPOS=owner/repo1,owner/repo2  Comma-separated REPO list
#                                               (default = atilproject/AtilCalculator,atilproject/dev-studio-template)
#   CROSS_REPO_SCAN_INTERVAL_SEC=300            Loop sleep interval (default 5 min)
#   CROSS_REPO_SCAN_LOG                         Audit log path override
#                                               (default: $XDG_CACHE_HOME/dev-studio/cross-repo-scan.log
#                                                or $HOME/.cache/dev-studio/cross-repo-scan.log)
#
# Output (audit log, JSONL):
#   {"ts":"2026-06-26T...","event":"cross_repo_dispatch","repo":"...","pr":N,
#    "role":"developer","labels":[...],"url":"...","peer_poke_rc":N}
#   {"ts":"...","event":"cross_repo_scan_complete","repos_scanned":N,"prs_total":N,
#    "dispatches":N,"duration_sec":N}
#
# Exit codes:
#   0  success (may have 0 dispatches — no PRs to dispatch)
#   2  usage error
#   4  no repos configured
#   5  peer-poke.sh missing

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PEER_POKE_SH="$SCRIPT_DIR/peer-poke.sh"

# --- defaults ---
# Sister-pattern to scripts/agent-watch.sh (e48dd96) and init-template-repo.sh
# (99bb1c5): no hardcoded repo default. Source ~/.dev-studio-env first (AC3
# contract from STORY-S21-010 / c638208), then derive from AGENT_CROSS_REPOS
# or GITHUB_REPO env var.
[ -f "${HOME}/.dev-studio-env" ] && . "${HOME}/.dev-studio-env" 2>/dev/null || true
# silent-skip guard per ADR-0045 lens (d) and Issue #642 §Out of scope: emit
# structured event when neither AGENT_CROSS_REPOS nor GITHUB_REPO is set, so
# the soft-fall-through is observable rather than silent. Arch 9-Lens (d)
# follow-up on PR #873.
if [ -z "${AGENT_CROSS_REPOS:-}" ] && [ -z "${GITHUB_REPO:-}" ]; then
  echo "silent_skip event=cross-repo-repos-empty layer=2 reason=no-env-or-env-file message=\"REPOS_RAW will be empty; scan no-ops until AGENT_CROSS_REPOS or GITHUB_REPO is set\"" >&2
fi
DEFAULT_REPOS=""
KNOWN_ROLES="orchestrator product-manager architect developer tester human"

# --- env / config ---
MODE="${1:---once}"
: "${AGENT_CROSS_REPOS:=${GITHUB_REPO:-}}"
REPOS_RAW="${AGENT_CROSS_REPOS:-$DEFAULT_REPOS}"
INTERVAL="${CROSS_REPO_SCAN_INTERVAL_SEC:-300}"

# --- audit log path (XDG-cache-honoring, $HOME/.cache fallback) ---
AUDIT_LOG="${CROSS_REPO_SCAN_LOG:-${XDG_CACHE_HOME:-$HOME/.cache}/dev-studio/cross-repo-scan.log}"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true

# --- usage ---
if [ "$MODE" = "--help" ] || [ "$MODE" = "-h" ]; then
  cat <<USAGE >&2
Usage: cross-repo-scan.sh [--once|--loop]

Orchestrator cross-repo fleet scan (ADR-0047 Part 2, Issue #422 Sprint 11 P1).

Modes:
  --once    One-shot scan (default)
  --loop    Loop forever, sleeping CROSS_REPO_SCAN_INTERVAL_SEC between scans

Env:
  AGENT_CROSS_REPOS=owner/repo1,owner/repo2  REPO list (default: $DEFAULT_REPOS)
  CROSS_REPO_SCAN_INTERVAL_SEC=300            Loop sleep interval (default 5 min)
  CROSS_REPO_SCAN_LOG                         Audit log path override

Audit log: \$CROSS_REPO_SCAN_LOG or \$XDG_CACHE_HOME/dev-studio/cross-repo-scan.log

Exit codes:
  0  success
  2  usage error
  4  no repos configured
  5  peer-poke.sh missing
USAGE
  exit 0
fi

# --- preflight ---
if [ ! -x "$PEER_POKE_SH" ]; then
  echo "ERROR: peer-poke.sh missing or not executable at $PEER_POKE_SH" >&2
  exit 5
fi

# --- repo resolution (ADR-0047 §Decision Part 2) ---
REPOS=()
IFS=',' read -ra _repo_parts <<< "$REPOS_RAW"
for part in "${_repo_parts[@]}"; do
  trimmed="$(printf '%s' "$part" | tr -d '[:space:]')"
  [ -z "$trimmed" ] && continue
  [[ "$trimmed" =~ ^[^/]+/[^/]+$ ]] || continue
  REPOS+=("$trimmed")
done

if [ "${#REPOS[@]}" -eq 0 ]; then
  echo "ERROR: no repos configured (AGENT_CROSS_REPOS empty or invalid)" >&2
  exit 4
fi

# --- audit log helper ---
# Writes a JSONL line to $AUDIT_LOG. Uses printf to avoid jq dependency on the
# hot path; structured fields are escaped via jq -nc for safety.
log_event() {
  local event="$1"
  shift
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # Build JSON via jq for safe escaping
  local line
  line="$(jq -nc \
    --arg ts "$ts" \
    --arg event "$event" \
    --argjson rest "$*" \
    '{ts: $ts, event: $event} + $rest')"
  printf '%s\n' "$line" >> "$AUDIT_LOG" 2>/dev/null || true
}

# --- core scan (one iteration) ---
scan_once() {
  local repos_total="${#REPOS[@]}"
  local prs_total=0
  local dispatches=0
  local started_at
  started_at="$(date -u +%s)"

  for repo in "${REPOS[@]}"; do
    # Per-repo gh pr list (ADR-0047 §Decision Part 2: only PRs, not issues)
    local prs
    prs="$(gh pr list \
      --repo "$repo" \
      --state open \
      --limit 50 \
      --json number,title,url,labels \
      2>/dev/null || echo '[]')"

    # Validate JSON; soft-fail on parse error
    if ! echo "$prs" | jq -e . >/dev/null 2>&1; then
      log_event cross_repo_scan_repo_error "$(jq -nc \
        --arg repo "$repo" \
        '{repo: $repo, error: "gh pr list returned invalid JSON"}')"
      continue
    fi

    local count
    count="$(echo "$prs" | jq 'length' 2>/dev/null || echo 0)"
    prs_total=$((prs_total + count))

    # Iterate PRs, check labels for agent:* / cc:* matching KNOWN_ROLES
    local i=0
    while [ "$i" -lt "$count" ]; do
      local pr
      pr="$(echo "$prs" | jq -c ".[$i]")"
      local pr_number pr_url pr_title pr_labels
      pr_number="$(echo "$pr" | jq -r '.number')"
      pr_url="$(echo "$pr" | jq -r '.url')"
      pr_title="$(echo "$pr" | jq -r '.title')"
      pr_labels="$(echo "$pr" | jq -r '[.labels[].name] | join(",")')"

      # Find first matching role from labels (priority: agent:* > cc:* per ADR-0012)
      local matched_role=""
      IFS=',' read -ra _lbls <<< "$pr_labels"
      for lbl in "${_lbls[@]}"; do
        case "$lbl" in
          agent:*)
            local candidate="${lbl#agent:}"
            case " $KNOWN_ROLES " in *" $candidate "*) matched_role="$candidate"; break ;; esac
            ;;
        esac
      done
      # Fallback to cc:* if no agent:* matched
      if [ -z "$matched_role" ]; then
        for lbl in "${_lbls[@]}"; do
          case "$lbl" in
            cc:*)
              local candidate="${lbl#cc:}"
              case " $KNOWN_ROLES " in *" $candidate "*) matched_role="$candidate"; break ;; esac
              ;;
          esac
        done
      fi

      # T4: no-dispatch on no-match (skip guard)
      if [ -z "$matched_role" ]; then
        i=$((i+1))
        continue
      fi

      # Dispatch via peer-poke.sh (ADR-0033 dual-channel)
      local msg="[ORCH→${matched_role^^}] Cross-repo PR #${pr_number} in ${repo} matches agent/cc:${matched_role}
${pr_url}
${pr_title}"
      local rc=0
      bash "$PEER_POKE_SH" "$matched_role" "$msg" >/dev/null 2>&1 || rc=$?
      dispatches=$((dispatches + 1))

      # T5: audit log event
      log_event cross_repo_dispatch "$(jq -nc \
        --arg repo "$repo" \
        --argjson pr "$pr_number" \
        --arg role "$matched_role" \
        --arg url "$pr_url" \
        --argjson rc "$rc" \
        --argjson labels "$(echo "$pr_labels" | jq -R 'split(",")')" \
        '{repo: $repo, pr: $pr, role: $role, url: $url, peer_poke_rc: $rc, labels: $labels}')"

      i=$((i+1))
    done
  done

  local duration=$(( $(date -u +%s) - started_at ))
  log_event cross_repo_scan_complete "$(jq -nc \
    --argjson repos_scanned "$repos_total" \
    --argjson prs_total "$prs_total" \
    --argjson dispatches "$dispatches" \
    --argjson duration_sec "$duration" \
    '{repos_scanned: $repos_scanned, prs_total: $prs_total, dispatches: $dispatches, duration_sec: $duration_sec}')"
}

# --- main ---
if [ "$MODE" = "--loop" ]; then
  while true; do
    scan_once
    sleep "$INTERVAL"
  done
else
  scan_once
fi