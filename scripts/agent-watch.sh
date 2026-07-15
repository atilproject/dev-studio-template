#!/usr/bin/env bash
# agent-watch.sh — GitHub-native autonomy: poll for new wake-up events for a role.
#
# Per ADR-0002 + ADR-0003 + ADR-0005 + ADR-0017 (Event Model v4): each agent's
# work queue lives on GitHub. This script queries the queue, diffs against
# the agent's state file, and emits new events as JSON.
#
# CRITICAL: every "$STATE_HELPER" set "$ROLE" <key> <value> call MUST wrap
# <value> in JSON quotes — i.e. \"$var\" not bare $var. Per ADR-0034 (cmd_set
# JSON contract), cmd_set validates input with `jq -e .` and exits 2 on plain
# strings. Hotfix Issue #267 (commit d0c999c) added the wrap to all 7 callers.
# Regression pin: scripts/tests/d030-cmd-set-quoting-guard.sh.
#
# Event Model v4 (ADR-0017) adds 2 event kinds to the v3 taxonomy:
#   `issue_comment_mention` — @<role> mentions in issue comments (was: PR-only)
#   `periodic_backlog_scan`  — 30-min synthetic wake when role has open queue
#
# Event Model v5 (Issue #44) adds 1 more:
#   `proactive_scan` — orchestrator-only board-anomaly sweep (D1 ready_unblocked,
#                      D2 orphan_backlog, D3 stalled, D4 wip_overflow). Fires
#                      every PROACTIVE_SWEEP_INTERVAL_SEC (default 300 = 5 min).
#                      Kill switch: PROACTIVE_SWEEP_ENABLED=false.
#
# Event Model v6 (ADR-0024) adds 2 more:
#   `stale_verdict`        — `cc:<role>` + `verdict-by:<ts>` where ts passed.
#                            Replaces `stale_cc` (label-presence) with deadline
#                            semantics. Back-compat shim 2026-06-19 → 2026-07-02.
#   `missing_expectation`  — `cc:<role>` WITHOUT `verdict-by:<ts>` (convention
#                            violation; ADR-0024 §Decision). One-shot per head_sha.
#
# Event Model v6.2 (Issue #113) adds 1 more:
#   `issue_assigned_any_status` — fires for every open issue with `agent:<role>`
#                      regardless of status label (backlog, ready, in-progress,
#                      blocked). Closes the silent-drop gap where agents with
#                      backlog-only work saw no wake events (2026-06-19 incident
#                      with #71/#72/#74). Throttled per (issue, role) at 5-min
#                      buckets; kill switch QUERY_ASSIGNED_ANY_STATUS_ENABLED=false.
#                      Context payload carries status + actionability hint.
#
# Event Model v7 (Issue #94) — Watcher self-cc skip rule:
#   For every PR with `agent:<role> == cc:<role>` (the author-self-cc pattern,
#   an intentional watchdog anchor per TD-001 Option A + ADR-0021 §peer cc on
#   own docs PR), the watcher was emitting the same set of `pr_review_requested`
#   / `pr_new_commit` / `stale_cc` events every poll cycle. The dedup chain in
#   `agent-state.sh` suppressed re-PROCESSING of the same event ID, but the
#   watcher continued to EMIT the same event IDs every cycle, so the autonomy
#   loop never idled. The fix adds an `is_author_self_cc_pr` filter at the top
#   of the `.[]` pipeline in `query_review_requests`, `query_new_commits_on_assigned_prs`,
#   and `query_stale_cc` — author-self-cc PRs are skipped BEFORE event construction.
#   `query_stale_verdict` and `query_missing_expectation` are NOT filtered
#   (ADR-0024 — deadline-based, not stall-based). Counter
#   `agent_watch_own_self_cc_filtered_total` tracks skipped PRs for observability.
#
# Event Model v8 (ADR-0041 / Issue #326 — `verdict_posted`):
#   PR-comment verdicts (🟢 APPROVED / 🟡 SUGGESTIONS / 🔴 CHANGES_REQUESTED)
#   that do NOT @-mention the role were silently missed by the v7 polling loop
#   (RCA: Issue #312, dev idled ~2h on PR #307). v8 adds `verdict_posted` as a
#   first-class event kind. The detector lives in `query_verdict_posted` (between
#   `query_pr_mentions` and `query_issue_mentions`) and fires when an in-scope
#   PR (cc:<role> OR agent:<role> OR verdict-by:<ts>) has a new comment whose
#   body matches the Issue #312 RCA Option A keyword table. Severity precedence:
#   `changes_requested > approved > suggestions`. The author-self-cc skip rule
#   (v7, Issue #94) applies — a role doesn't wake itself on its own PR's
#   incoming verdict. Event ID format: `verdict-posted-<pr>-<sha7>-b<bucket>`
#   (5-min dedup window, same as v6 stale_verdict). Deprecates the standalone
#   Phase 0 supplement `scripts/agent-watch-verdicts.sh` (kept for one sprint
#   as belt+suspenders per ADR-0041 §Deprecation timeline).
#
# Event Model v3 (ADR-0005) adds `pr_merged` to the v2 taxonomy:
#   When a PR is merged, the watcher fans out a `pr-merged-<n>-<sha7>` event to
#   orchestrator + product-manager + developer (the post-merge lifecycle MVP).
#   Architect/tester get label-conditional fanout in a later iteration.
#
# Event Model v2 (ADR-0003):
#   Event IDs include `headRefOid` (commit SHA) for PR events, so a new push
#   to a PR where cc:<role> is active = new event = re-wake (fixes the
#   "developer pushed fix but tester didn't re-verify" silent-failure class).
#
#   Stale-cc detector: if cc:<role> has been on a PR for > stale_threshold_sec
#   without any state change, emit a `stale_cc` event so deadlocks self-heal.
#
#   Heartbeat: after each poll the watcher bumps `last_heartbeat_utc`. A side
#   alarm (agent-doctor.sh / cron) raises a Telegram warn if a role's
#   heartbeat is stale, so silent watcher death is impossible to miss.
#
# Usage:
#   agent-watch.sh <role> [--once|--loop] [--repo owner/repo1,...] [--org <name>]
#
# Multi-repo polling (ADR-0047 Part 1, Issue #422 Sprint 11 P1):
#   --repo owner/repo1,owner/repo2   Comma-separated list; per-repo sub-query,
#                                    results merged into single event stream
#                                    and de-duped by id.
#   AGENT_WATCH_REPOS=owner/repo1,owner/repo2   Env-var equivalent (used when
#                                    --repo not passed).
#   Precedence: --repo flag > AGENT_WATCH_REPOS > GITHUB_REPO > auto-detect >
#               fallback ("atilproject/AtilCalculator").
#   Back-compat: no flag + no env = single-repo (current repo) only.
#
# Org-wide polling (RETRO-023 cross-repo sister-pattern discovery, Issue cycle ~#1825):
#   --org <name>              GitHub ORG name; fetch all non-archived repos from
#                             `gh api /orgs/<name>/repos` and APPEND them to
#                             REPOS[] (deduplicating against any explicit --repo
#                             entries). Makes org-wide workstream discovery
#                             feasible for cross-repo sister-pattern trackers.
#   AGENT_WATCH_ORG=<name>    Env-var equivalent (used when --org absent).
#                             Defaults to "atilproject" (per owner directive
#                             2026-07-15T06:42Z — sister-mirror of AtilCalculator
#                             d1041 in PR #1085). Set AGENT_WATCH_ORG="" to
#                             disable org-scan fallback (single-repo behavior).
#   Archived repos: SKIPPED by default. Set AGENT_WATCH_INCLUDE_ARCHIVED=1 to
#                  include (noise reduction; archived repos don't get fresh traffic).
#   Precedence: --org flag > AGENT_WATCH_ORG > (no org-scan)
#
# Env:
#   AGENT_WATCH_ORG=<name>    ORG name for cross-repo sister-pattern discovery.
#                             Default: "atilproject". Set to "" to disable.
#   AGENT_WATCH_INCLUDE_ARCHIVED=1  Include archived repos in org-scan (default 0).
#   WAKE_PANE=1   — when new_events > 0, send a wake-up prompt to the role's
#                   tmux pane via `tmux send-keys`. Auto-enabled in --loop mode.
#                   Override with WAKE_PANE=0 to disable.
#   TMUX_SESSION  — session name to address (default: dev-studio)
#   STALE_CC_SEC          — seconds before cc:<role> on an unchanged PR is "stale"
#                           (default: 900 = 15 min). DEPRECATED in shim window
#                           (ADR-0024); suppress by leaving VERDICT_SHIM_END
#                           in the past.
#   VERDICT_SHIM_END      — ISO timestamp; while now < this, `stale_cc` is still
#                           emitted alongside `stale_verdict` (default: 2026-07-02).
#   VERDICT_LEGACY_STALE_CC — set true to re-enable `stale_cc` after shim end
#                             (rollback / kill switch). Default: false.
#
# Output (JSON, to stdout):
#   {
#     "role": "<role>",
#     "polled_at_utc": "...",
#     "new_events": [
#       {
#         "id": "<unique event id>",
#         "kind": "issue_assigned|pr_review_requested|pr_new_commit|pr_comment_mention|verdict_posted|stale_cc|stale_verdict|missing_expectation|label_change|pr_merged|proactive_scan|issue_assigned_any_status",
#         "number": <int>,
#         "title": "<str>",
#         "url": "<str>",
#         "updated_at": "<utc>",
#         "context": { ...kind-specific... }
#       }
#     ],
#     "next_poll_sec": 60
#   }
#
# Exit codes:
#   0  — success (may have 0 new events)
#   2  — usage error
#   3  — gh CLI not authenticated
#   4  — repo not detected (not inside a git repo or no GITHUB_REPO env)
#   5  — state helper missing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_HELPER="$SCRIPT_DIR/agent-state.sh"
ROLE="${1:-}"
MODE="${2:---once}"
TMUX_SESSION="${TMUX_SESSION:-dev-studio}"
STALE_CC_SEC="${STALE_CC_SEC:-900}"
# v6 (ADR-0024 — stale-verdict watchdog schema): back-compat shim window.
# During the shim window (now < VERDICT_SHIM_END), poll_once emits BOTH the old
# `stale_cc` AND the new `stale_verdict` + `missing_expectation` event kinds so
# existing agents migrate gracefully. After VERDICT_SHIM_END, `query_stale_cc`
# is suppressed unless VERDICT_LEGACY_STALE_CC=true (kill switch / rollback).
# Default shim end: 2026-07-02T00:00:00Z (one sprint per ADR-0024 §Decision).
VERDICT_SHIM_END="${VERDICT_SHIM_END:-2026-07-02T00:00:00Z}"
VERDICT_LEGACY_STALE_CC="${VERDICT_LEGACY_STALE_CC:-false}"
# v7 (Issue #94 — Watcher self-cc skip rule): counter for observability.
# Incremented inside `is_author_self_cc_pr()` when a PR matches the
# author-self-cc pattern (BOTH `agent:<role>` AND `cc:<role>` present) and
# the filter skips the PR. Reset on watcher start; persists for the watcher's
# lifetime (one-shot poll = single counter per invocation).
AGENT_WATCH_OWN_SELF_CC_FILTERED_TOTAL="${AGENT_WATCH_OWN_SELF_CC_FILTERED_TOTAL:-0}"
# WAKE_PANE: 0/1. Auto-enabled in --loop mode unless explicitly set to 0.
WAKE_PANE_DEFAULT=0
[ "$MODE" = "--loop" ] && WAKE_PANE_DEFAULT=1
WAKE_PANE="${WAKE_PANE:-$WAKE_PANE_DEFAULT}"

# --- ORG-wide scan defaults (sister-mirror of AtilCalculator d1041) ---
# Owner directive 2026-07-15T06:42Z: org-scan default = atilproject so cross-repo
# sister-pattern discovery (RETRO-023 codifier) works without per-clone env setup.
# Disable by exporting AGENT_WATCH_ORG="" before invocation.
AGENT_WATCH_ORG="${AGENT_WATCH_ORG:-atilproject}"
ORG_FLAG=""

if [ -z "$ROLE" ] || [ "$ROLE" = "--help" ] || [ "$ROLE" = "-h" ]; then
  cat <<'USAGE' >&2
Usage: agent-watch.sh <role> [--once|--loop] [--repo owner/repo1,...] [--org <name>]

Arguments:
  <role>                    Role to poll for (developer, orchestrator, architect,
                            product-manager, tester, human)
  --once                    One-shot poll (default)
  --loop                    Poll forever (sleeps poll_interval between checks)
  --repo <list>             Comma-separated multi-REPO list (ADR-0047 Part 1).
                            Per-repo sub-query; results merged into single event
                            stream. Overrides AGENT_WATCH_REPOS env var.
                            Examples: --repo owner/repo1,owner/repo2
                                      --repo <owner>/<repo>
  --org <name>              GitHub ORG name; fetch all non-archived repos from
                            `gh api /orgs/<name>/repos` and merge into REPOS[].
                            Cross-repo sister-pattern discovery (RETRO-023).
                            Sister-mirror of AtilCalculator d1041 (PR #1085).

Environment:
  AGENT_WATCH_REPOS         Comma-separated REPO list (used when --repo absent)
  AGENT_WATCH_ORG=<name>    ORG name (used when --org absent). Default: atilproject.
                            Set to "" to disable org-scan (single-repo back-compat).
  AGENT_WATCH_INCLUDE_ARCHIVED=1  Include archived repos in org-scan (default 0).
  GITHUB_REPO               Single-repo fallback (legacy; --repo / AGENT_WATCH_REPOS
                            take precedence)
  WAKE_PANE=1               Send tmux wake-up prompt on new_events > 0
  STALE_CC_SEC=900          cc:<role> staleness threshold (DEPRECATED, ADR-0024)
  VERDICT_SHIM_END          ISO ts; while now < this, stale_cc is still emitted
                            alongside stale_verdict (default 2026-07-02)
  POLL_INTERVAL_SEC         Override state file's poll_interval_sec

Exit codes:
  0  success (may have 0 new events)
  2  usage error
  3  gh CLI not authenticated
  4  repo not detected
  5  state helper missing
  127  jq/gh missing

Examples:
  # Single-repo (back-compat default)
  agent-watch.sh developer

  # Multi-repo
  agent-watch.sh developer --repo <owner>/<repo>,<owner>/<repo>

  # Loop mode with tmux wake-up
  agent-watch.sh developer --loop
USAGE
  [ -z "$ROLE" ] && exit 2
  exit 0
fi

# --- argument parsing: --repo <list> (ADR-0047 Part 1) ---
# Walks args (skipping $ROLE at [1]) and extracts --repo <list> if present.
# All other args are forwarded semantics (--once/--loop detected via MODE above).
REPO_FLAG=""
ARG_IDX=2
while [ "$ARG_IDX" -le "$#" ]; do
  arg="${!ARG_IDX:-}"
  case "$arg" in
    --repo)
      next_idx=$((ARG_IDX + 1))
      REPO_FLAG="${!next_idx:-}"
      ARG_IDX=$((ARG_IDX + 2))
      ;;
    --repo=*)
      REPO_FLAG="${arg#--repo=}"
      ARG_IDX=$((ARG_IDX + 1))
      ;;
    --org)
      next_idx=$((ARG_IDX + 1))
      ORG_FLAG="${!next_idx:-}"
      ARG_IDX=$((ARG_IDX + 2))
      ;;
    --org=*)
      ORG_FLAG="${arg#--org=}"
      ARG_IDX=$((ARG_IDX + 1))
      ;;
    *)
      ARG_IDX=$((ARG_IDX + 1))
      ;;
  esac
done

if [ ! -x "$STATE_HELPER" ]; then
  echo "ERROR: agent-state.sh missing or not executable at $STATE_HELPER" >&2
  exit 5
fi

# --- multi-REPO resolution (ADR-0047 Part 1, Issue #422 Sprint 11 P1) ---
# Precedence: --repo flag > AGENT_WATCH_REPOS env > GITHUB_REPO > auto-detect > fallback.
# Each entry must match owner/name format; otherwise rejected with usage error.
REPOS_RAW=""
if [ -n "$REPO_FLAG" ]; then
  REPOS_RAW="$REPO_FLAG"
elif [ -n "${AGENT_WATCH_REPOS:-}" ]; then
  REPOS_RAW="$AGENT_WATCH_REPOS"
elif [ -n "${GITHUB_REPO:-}" ]; then
  REPOS_RAW="$GITHUB_REPO"
elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # REST API fallback (GraphQL rate-limit safe, 5/5 agents were failing)
  REPOS_RAW="$(gh api /repos/$(gh api user --jq .login 2>/dev/null)/$(basename "$(git rev-parse --show-toplevel 2>/dev/null)") --jq .full_name 2>/dev/null || true)"
fi
# Last-resort fallback (Issue #238 sub-task 2 emergency fix lineage): source
# ~/.dev-studio-env (AC3 contract from STORY-S21-010 / Issue #642) to pick up
# GITHUB_REPO, then fail loud if still unset. Skip when --org / AGENT_WATCH_ORG
# is set (org-scan populates REPOS[] downstream at the org-scan block).
if [ -z "$REPOS_RAW" ] && [ -z "$ORG_FLAG" ] && [ -z "${AGENT_WATCH_ORG:-}" ]; then
  [ -f "${HOME}/.dev-studio-env" ] && . "${HOME}/.dev-studio-env" 2>/dev/null || true
  REPOS_RAW="${GITHUB_REPO:-}"
fi
if [ -z "$REPOS_RAW" ] && [ -z "$ORG_FLAG" ] && [ -z "${AGENT_WATCH_ORG:-}" ]; then
  echo "ERROR: REPOS_RAW is empty; set --repo, --org, AGENT_WATCH_REPOS, AGENT_WATCH_ORG, GITHUB_REPO (~/.dev-studio-env), or run dev-studio-init.sh first" >&2
  exit 2
fi

# Split on comma, validate each owner/name, build REPOS[] array.
REPOS=()
REPO_INVALID=""
IFS=',' read -ra _repo_parts <<< "$REPOS_RAW"
for part in "${_repo_parts[@]}"; do
  trimmed="$(printf '%s' "$part" | tr -d '[:space:]')"
  [ -z "$trimmed" ] && continue
  if [[ ! "$trimmed" =~ ^[^/]+/[^/]+$ ]]; then
    REPO_INVALID="$trimmed"
    break
  fi
  REPOS+=("$trimmed")
done

if [ -n "$REPO_INVALID" ]; then
  echo "ERROR: invalid --repo format: '$REPO_INVALID' (expected owner/name)" >&2
  echo "Usage: $0 <role> [--once|--loop] [--repo owner/repo1,owner/repo2]" >&2
  exit 2
fi

if [ "${#REPOS[@]}" -eq 0 ] && [ -z "$ORG_FLAG" ] && [ -z "${AGENT_WATCH_ORG:-}" ]; then
  echo "ERROR: cannot determine repo. Set GITHUB_REPO=owner/name, AGENT_WATCH_REPOS, --org <name>, AGENT_WATCH_ORG, or run inside repo." >&2
  exit 4
fi

# --- ORG-wide scan (RETRO-023 cross-repo sister-pattern discovery) ---
# When --org or AGENT_WATCH_ORG is set, enumerate all non-archived repos in
# the org via `gh api /orgs/<org>/repos` and APPEND them to REPOS[] (dedup
# against any explicit --repo entries). Sister-mirror of AtilCalculator
# d1041 (PR #1085) + d1042 line-339 fix; same default = "atilproject" per
# owner directive 2026-07-15T06:42Z.
#
# Per-page: 100 (max). Pagination: for orgs with >100 non-archived repos we'd
# need to follow Link headers — defer to a future sprint if any active org
# crosses that threshold (atilproject currently has 5 non-archived repos).
if [ -n "$ORG_FLAG" ] || [ -n "${AGENT_WATCH_ORG:-}" ]; then
  ORG_RESOLVED="${ORG_FLAG:-${AGENT_WATCH_ORG}}"
  if [[ ! "$ORG_RESOLVED" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,38}[A-Za-z0-9])?$ ]]; then
    echo "ERROR: invalid --org format: '$ORG_RESOLVED' (expected GitHub org slug)" >&2
    exit 2
  fi
  ORG_REPOS_JSON="$(gh api "/orgs/${ORG_RESOLVED}/repos?per_page=100&type=all" 2>/dev/null || true)"
  if [ -z "$ORG_REPOS_JSON" ] || ! echo "$ORG_REPOS_JSON" | jq -e . >/dev/null 2>&1; then
    echo "ERROR: --org '$ORG_RESOLVED' fetch failed (gh api /orgs/.../repos)" >&2
    exit 2
  fi
  # Build set of existing REPOS[] for dedup; iterate org repos and append
  # non-archived entries not already in REPOS[].
  declare -A _seen_repos=()
  if [ "${#REPOS[@]}" -gt 0 ]; then
    for r in "${REPOS[@]}"; do _seen_repos["$r"]=1; done
  fi
  ORG_ADDED=0
  while IFS=$'\t' read -r full_name archived; do
    [ "$archived" = "true" ] && [ "${AGENT_WATCH_INCLUDE_ARCHIVED:-0}" != "1" ] && continue
    [ -n "${_seen_repos[$full_name]:-}" ] && continue
    REPOS+=("$full_name")
    _seen_repos["$full_name"]=1
    ORG_ADDED=$((ORG_ADDED + 1))
  done < <(echo "$ORG_REPOS_JSON" | jq -r '.[] | [.full_name, (.archived|tostring)] | @tsv')
  unset _seen_repos
  # Refresh REPO back-compat var in case REPOS[] was empty before org scan.
  if [ "${#REPOS[@]}" -gt 0 ]; then
    REPO="${REPOS[0]}"
  fi
  echo "[--org $ORG_RESOLVED] appended $ORG_ADDED non-archived repos; REPOS[] total = ${#REPOS[@]}" >&2
fi

# Back-compat: keep single REPO var for non-iterative call sites (e.g.
# query_proactive_sweep env export, gh pr view for individual PR lookups).
#
# Guarded with :- default expansion (sister to AtilCalculator d1042) so
# set -euo pipefail does not fire when REPOS[] is empty pre-org-scan. The
# org-scan block above populates REPOS[] and refreshes REPO from REPOS[0].
REPO="${REPOS[0]:-}"

# gh_all_repos <out_var> <gh_subcmd> [args...]
# Runs <gh_subcmd> [args...] --repo <each> for every repo in REPOS, merges
# JSON array outputs into <out_var>. Per-repo call fails soft (treated as '[]')
# so a transient gh error in one repo doesn't sink the whole query.
gh_all_repos() {
  local __outvar="$1"; shift
  local merged='[]'
  local piece
  local repo
  for repo in "${REPOS[@]}"; do
    piece="$("$@" --repo "$repo" 2>/dev/null || true)"
    if [ -z "$piece" ]; then
      piece='[]'
    elif ! echo "$piece" | jq -e . >/dev/null 2>&1; then
      piece='[]'
    fi
    merged="$(jq -c -n --argjson a "$merged" --argjson b "$piece" '$a + $b')"
  done
  printf -v "$__outvar" '%s' "$merged"
}

# --- preflight ---
require_jq() {
  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 127; }
}
require_gh() {
  command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI required" >&2; exit 127; }
}
require_jq
require_gh

# Ensure state file exists
"$STATE_HELPER" init "$ROLE" >/dev/null

POLL_INTERVAL="$("$STATE_HELPER" get "$ROLE" poll_interval_sec)"
POLL_INTERVAL="${POLL_INTERVAL:-180}"

# v3.4 (issue #61 fix): HWM refresh on every poll.
#
# Bug (issue #61): `LAST_SEEN` / `PR_MERGED_LAST_SEEN` / `PR_LABELED_LAST_SEEN`
# were previously read ONCE at script start (this file, pre-fix) and never
# refreshed inside `poll_once`. In a long-running --loop watcher, the local
# HWM vars drifted behind the state file's HWM (which advances on every
# poll's tail), so the gh query kept returning historical events with old
# `updatedAt`. Combined with the FIFO trim on `processed_event_ids`, the
# dedup chain failed and events re-emitted indefinitely (board-50/52
# phantoms in the orchestrator's INBOX — 17+/8+ re-emissions per session).
#
# Fix: read all 3 HWMs from state at the start of every poll_once call (see
# `poll_once` below). The backfill logic stays — it runs on first call
# (state empty) and is a no-op thereafter. The two `init_*_hwm` functions
# are called from poll_once, NOT script-top, so the local vars are always
# fresh relative to the state file.
#
# Backfill window defaults are unchanged from v3/v3.2:
#   PR_MERGED_BACKFILL = '1 hour ago'   — long enough to span a brief
#                                         watcher restart, short enough
#                                         to not replay multi-day history.
#   PR_LABELED_BACKFILL = '60 seconds ago' — D2.2 § 2.3 / § 6: matches
#                                            default poll interval so we
#                                            don't miss a wake during a
#                                            brief restart.
PR_MERGED_BACKFILL="${PR_MERGED_BACKFILL:-1 hour ago}"
PR_LABELED_BACKFILL="${PR_LABELED_BACKFILL:-60 seconds ago}"

# init_pr_merged_hwm — read PR_MERGED_LAST_SEEN with first-run backfill.
# Idempotent. Sets the global var; called from poll_once.
init_pr_merged_hwm() {
  PR_MERGED_LAST_SEEN="$("$STATE_HELPER" get "$ROLE" pr_merged_last_seen_utc)"
  if [ -z "$PR_MERGED_LAST_SEEN" ] || [ "$PR_MERGED_LAST_SEEN" = "null" ]; then
    # GNU date (Linux) understands "-d '1 hour ago'"; BSD date (macOS) needs -v.
    PR_MERGED_LAST_SEEN="$(date -u -d "$PR_MERGED_BACKFILL" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
    if [ -z "$PR_MERGED_LAST_SEEN" ]; then
      # BSD fallback: extract "<N> <unit>" → -v-<N><U>; default to -1H if unparsable.
      bsd_num="$(printf '%s' "$PR_MERGED_BACKFILL" | awk '{print $1}')"
      bsd_unit="$(printf '%s' "$PR_MERGED_BACKFILL" | awk '{print $2}' | cut -c1 | tr '[:lower:]' '[:upper:]')"
      case "$bsd_unit" in M|H|D|W) : ;; *) bsd_num=1; bsd_unit=H ;; esac
      PR_MERGED_LAST_SEEN="$(date -u -v-"${bsd_num}${bsd_unit}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
        || date -u '+%Y-%m-%dT%H:%M:%SZ')"
    fi
    "$STATE_HELPER" set "$ROLE" pr_merged_last_seen_utc "\"$PR_MERGED_LAST_SEEN\""
  fi
}

# init_pr_labeled_hwm — read PR_LABELED_LAST_SEEN with first-run backfill.
# Idempotent. Sets the global var; called from poll_once.
init_pr_labeled_hwm() {
  PR_LABELED_LAST_SEEN="$("$STATE_HELPER" get "$ROLE" pr_labeled_last_seen_utc)"
  if [ -z "$PR_LABELED_LAST_SEEN" ] || [ "$PR_LABELED_LAST_SEEN" = "null" ]; then
    PR_LABELED_LAST_SEEN="$(date -u -d "$PR_LABELED_BACKFILL" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
    if [ -z "$PR_LABELED_LAST_SEEN" ]; then
      PR_LABELED_LAST_SEEN="$(date -u -v-60S '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
        || date -u '+%Y-%m-%dT%H:%M:%SZ')"
    fi
    "$STATE_HELPER" set "$ROLE" pr_labeled_last_seen_utc "\"$PR_LABELED_LAST_SEEN\""
  fi
}

# v3.1 (ADR-0008): label-conditional pr_merged fanout.
#
# Two layers:
#   1. PR_MERGED_FANOUT_DEFAULT — roles always woken on every merge (lifecycle).
#      D2 MVP value: "orchestrator product-manager developer".
#      Empty string = no default fanout (kill switch / debugging).
#   2. PR_MERGED_FANOUT_RULES_ENABLED=true|false — when true (default), the
#      following label patterns add extra roles per-PR:
#        - needs-architect-review or agent:architect → +architect
#        - needs-tester-signoff   or agent:tester    → +tester
#      When false, only the default set is used (D2 behaviour, full rollback).
#
# Per-role gating (`role_receives_pr_merged`) decides at poll time whether THIS
# watcher should run the pr_merged query at all. Without labels available it
# returns true for any role in DEFAULT (so we run the query and pick up labels);
# for architect/tester it also returns true when rules are enabled so they at
# least query merged PRs and let the per-PR filter decide later.
# Issue #52 (BUG-1 sibling): empty string must disable the default fanout
# (kill switch per ADR-0008 § 6). Using `${VAR-default}` (not `${VAR:-default}`)
# so empty string is honored and only the unset case falls back to default.
# Same fix as BUG-1 for PR_LABELED_FANOUT in PR #49 (commit 6823193).
PR_MERGED_FANOUT_DEFAULT="${PR_MERGED_FANOUT_DEFAULT-orchestrator product-manager developer}"
PR_MERGED_FANOUT_RULES_ENABLED="${PR_MERGED_FANOUT_RULES_ENABLED:-true}"

# v3.2 (ADR-0009): pr_labeled fanout — PR-open architect/tester routing.
# Closes ADR-0008 § 8.2 loop: architect/tester wake on label-add at PR-open
# time, BEFORE label-cleanup.yml (ADR-0007) can strip the wake-trigger label.
#
# Roles in PR_LABELED_FANOUT wake when an OPEN PR carries any wake-trigger
# label for their role (see role_wakes_for_pr_labeled). Empty string disables
# the entire path — kill switch matches ADR-0009 § 6 Reversal.
# ADR-0009 § 6: empty string must disable the path (kill switch). Using
# `${VAR-default}` (not `${VAR:-default}`) so empty string is honored and
# only the unset case falls back to the default. Fixes BUG-1 (kill switch
# was silently re-defaulted by `:-` on empty).
PR_LABELED_FANOUT="${PR_LABELED_FANOUT-architect tester}"

# True if $role is in the always-woken default set.
role_in_default_fanout() {
  local r="$1"
  case " $PR_MERGED_FANOUT_DEFAULT " in
    *" $r "*) return 0 ;;
    *) return 1 ;;
  esac
}

# True if $role can ever be woken by label rules (i.e. architect / tester when
# rules are enabled). Used as a query-gate so architect/tester actually run the
# gh query and we get to look at the labels.
role_eligible_via_label_rules() {
  [ "$PR_MERGED_FANOUT_RULES_ENABLED" = "true" ] || return 1
  case "$1" in
    architect|tester) return 0 ;;
    *) return 1 ;;
  esac
}

# Query-level gate: should this watcher even run query_pr_merged?
# Yes if role is in default OR rules might wake it via labels.
role_receives_pr_merged() {
  local r="$1"
  role_in_default_fanout "$r" && return 0
  role_eligible_via_label_rules "$r" && return 0
  return 1
}

# v3.2 (ADR-0009): pr_labeled gating + matching.
#
# role_receives_pr_labeled — query-level gate: is this role enrolled in
# PR_LABELED_FANOUT? If not, skip the gh pr list call entirely.
role_receives_pr_labeled() {
  local r="$1"
  case " $PR_LABELED_FANOUT " in
    *" $r "*) return 0 ;;
    *) return 1 ;;
  esac
}

# role_wakes_for_pr_labeled — per-PR filter: does the OPEN PR carry any of
# this role's wake-trigger labels? Per ADR-0009 § 2.1:
#   architect: needs-architect-review, cc:architect, agent:architect
#   tester:    needs-tester-signoff,   cc:tester,    agent:tester
# Exact-name match (NOT regex) per ADR-0009 § 2.1 "Correction to issue #47 AC".
#   $1 = role
#   $2 = JSON array of label name strings (from PR's labels field)
# Returns 0 (wake) / 1 (skip).
role_wakes_for_pr_labeled() {
  local r="$1" labels_json="$2"
  case "$r" in
    architect)
      echo "$labels_json" | jq -e '
        any(.[]?; . == "needs-architect-review" or . == "cc:architect" or . == "agent:architect")
      ' >/dev/null 2>&1 && return 0
      ;;
    tester)
      echo "$labels_json" | jq -e '
        any(.[]?; . == "needs-tester-signoff" or . == "cc:tester" or . == "agent:tester")
      ' >/dev/null 2>&1 && return 0
      ;;
  esac
  return 1
}

# pr_labeled_wake_reason — returns the first matching wake-trigger label name,
# for event observability (context.wake_reason per ADR-0009 § 2.2 / § 4.3).
pr_labeled_wake_reason() {
  local r="$1" labels_json="$2"
  case "$r" in
    architect)
      echo "$labels_json" | jq -r '
        (map(select(. == "needs-architect-review" or . == "cc:architect" or . == "agent:architect")) | .[0]) // ""
      '
      ;;
    tester)
      echo "$labels_json" | jq -r '
        (map(select(. == "needs-tester-signoff" or . == "cc:tester" or . == "agent:tester")) | .[0]) // ""
      '
      ;;
    *) echo "" ;;
  esac
}

# Per-PR fanout decision: given a role and a JSON labels array, should this PR
# wake the role? Inputs:
#   $1 = role
#   $2 = JSON array of label name strings (from pr_merged event context.labels)
# Returns 0 (wake) / 1 (skip). Used to filter pr_merged events role-by-role.
role_wakes_for_pr() {
  local r="$1" labels_json="$2"

  # Default-fanout roles always wake on merge (D2 behaviour preserved).
  if role_in_default_fanout "$r"; then
    return 0
  fi

  # Rules disabled → no extra fanout, default-only.
  [ "$PR_MERGED_FANOUT_RULES_ENABLED" = "true" ] || return 1

  # architect: needs-architect-review or agent:architect.
  # tester:   needs-tester-signoff   or agent:tester.
  case "$r" in
    architect)
      echo "$labels_json" | jq -e '
        any(.[]?; . == "needs-architect-review" or . == "agent:architect")
      ' >/dev/null 2>&1 && return 0
      ;;
    tester)
      echo "$labels_json" | jq -e '
        any(.[]?; . == "needs-tester-signoff" or . == "agent:tester")
      ' >/dev/null 2>&1 && return 0
      ;;
  esac
  return 1
}

# v7 (Issue #94 — Watcher self-cc skip rule): per-PR author-self-cc detector.
#
# For PRs where `agent:<role> == cc:<role>` (the author-self-cc pattern,
# intentional watchdog anchor per TD-001 Option A + ADR-0021 §peer cc on own
# docs PR), the 3 PR queries below (`query_review_requests`,
# `query_new_commits_on_assigned_prs`, `query_stale_cc`) must NOT emit events.
# This bash helper takes a JSON array of label-name strings and returns 0
# (true = author-self-cc, SHOULD skip) when BOTH `agent:<role>` AND
# `cc:<role>` are present. Returns 1 (false = not author-self-cc, do NOT
# skip) otherwise.
#
# Side effect: increments the `AGENT_WATCH_OWN_SELF_CC_FILTERED_TOTAL` counter
# on every true return (Issue #94 design §Observability). The counter is
# observability-only — no functional effect.
#
# In the jq queries themselves, the same check is duplicated as a `def`
# block (one per query) because jq cannot call into bash. The bash function
# is kept for completeness and to centralize the counter increment logic
# — the jq defs and the bash function are kept in sync via tests/d094.
is_author_self_cc_pr() {
  local labels_json="$1"
  # Bash outer double-quote → bash interpolates ${ROLE} at runtime → jq sees
  # "agent:developer" (or whichever role). Source line keeps literal "${ROLE}"
  # so the d094 test grep matches (T2 looks for "agent:${ROLE}" / "cc:${ROLE}"
  # in the file). Inner \" escapes are passed to jq as literal " characters.
  if echo "$labels_json" | jq -e \
    "any(.[]?; . == \"agent:${ROLE}\") and any(.[]?; . == \"cc:${ROLE}\")" \
    >/dev/null 2>&1; then
    AGENT_WATCH_OWN_SELF_CC_FILTERED_TOTAL=$(( ${AGENT_WATCH_OWN_SELF_CC_FILTERED_TOTAL:-0} + 1 ))
    return 0
  fi
  return 1
}

# --- query builders (role-specific filters) ---
# Returns a JSON array of event objects (may be empty).
query_assigned_issues() {
  # Issues with label agent:<role> AND status:ready, updated after last_seen.
  # v3.5 (issue #6 fix): event ID is content-stable — derived from sorted label
  # set, NOT updatedAt. updatedAt bumps on every comment / label-edit / assign,
  # which used to produce fresh event IDs and wake the agent repeatedly for the
  # same underlying assignment. Sorted label set is stable across comment-only
  # bumps and changes only when the relevant label set actually changes.
  #
  # ADR-0047 Part 1 (Issue #422): gh_all_repos iterates REPOS[] and merges
  # per-repo JSON arrays into one event stream. Single-repo deployments see
  # identical behavior (REPOS has one element).
  # Issue #806: gh issue list --label filter silently drops matches for
  # certain roles (architect 100%, tester 60%, PM 75%, dev 25%). Use REST
  # gh api with labels=X query param instead. Sister-pattern: L1778
  # (Katman 1 queue count) — already correctly on REST path.
  gh_all_repos _q gh api \
    "repos/${REPO}/issues?labels=agent:${ROLE}&state=open&per_page=50" \
    --jq "[.[] | {number, title, url: .html_url, updatedAt: .updated_at, labels: [.labels[] | {name}]}]"
  echo "$_q" | jq "[ .[] | select(.updatedAt > \"$LAST_SEEN\") |
           {
             id: (\"issue-assigned-\" + (.number | tostring) + \"-\" + (.labels | map(.name) | sort | join(\"|\"))),
             kind: \"issue_assigned\",
             number: .number,
             title: .title,
             url: .url,
             updated_at: .updatedAt,
             context: { labels: [.labels[].name] }
           } ]"
}

# v6.1 (Issue #113): query_assigned_issues_any_status — wider lens than
# query_assigned_issues. The original filter `agent:<role> AND status:ready`
# excludes issues still in status:backlog or status:blocked, which means an
# agent whose queue has only backlog work gets a silent drop (the 2026-06-19
# incident with #71/#72/#74). This query returns ALL open issues with
# agent:<role> regardless of status, but throttles per (issue, role) bucket
# so it doesn't spam when an agent is actively working (issue already in
# its queue). The status:ready + status:in-progress subset is the
# actionable signal; status:backlog + status:blocked is informational.
#
# Throttle: 5-min bucket per issue per role (5 * 60 = 300s, matches the
# stale-verdict bucket cadence from PR #108 / ADR-0024).
#
# Kill switch: QUERY_ASSIGNED_ANY_STATUS_ENABLED=false bypasses.
query_assigned_issues_any_status() {
  if [ "${QUERY_ASSIGNED_ANY_STATUS_ENABLED:-true}" = "false" ]; then
    echo "[]"
    return 0
  fi

  local now_epoch bucket
  now_epoch="$(date -u +%s)"
  bucket=$(( now_epoch / 300 ))

  # Issue #806: REST gh api replaces gh issue list --label (silent-drop fix)
  gh_all_repos _q gh api \
    "repos/${REPO}/issues?labels=agent:${ROLE}&state=open&per_page=50" \
    --jq "[.[] | {number, title, url: .html_url, updatedAt: .updated_at, labels: [.labels[] | {name}]}]"
  echo "$_q" | jq --argjson now_epoch "$now_epoch" --arg bucket "$bucket" \
       "[ .[] |
         (.labels | map(.name)) as \$lbls |
         (\$lbls | map(select(startswith(\"status:\"))) | first // \"\") as \$status |
         {
           id: (\"issue-assigned-any-\" + (.number | tostring) + \"-b\" + \$bucket),
           kind: \"issue_assigned_any_status\",
           number: .number,
           title: .title,
           url: .url,
           updated_at: .updatedAt,
           context: {
             role: \"${ROLE}\",
             status: \$status,
             labels: \$lbls,
             bucket: \$bucket,
             note: (\"Issue is in ${ROLE}'s queue. Per Issue #113 soul doctrine: \" +
                    \"labels = ownership. Body text may be stale; work the spec, \" +
                    \"not the body. Actionability: \" +
                    (if \$status == \"status:ready\" or \$status == \"status:in-progress\" then \"ACTIONABLE\" else \"informational\" end))
           }
         } ]"
}

query_review_requests() {
  # PRs with label cc:<role>, open.
  # Event ID is derived from (pr_number, head_sha, sorted_labels). This is the
  # v3 content-stable fix for BUG #14 — a PR comment / CI re-run / label flip
  # that does not change the head SHA or the label set must produce the SAME
  # event ID, so the dedup chain suppresses it. A new push on the PR changes
  # head SHA → new ID → wake. A label flip (verdict, cc, status, etc.) changes
  # the sorted label set → new ID → wake. A comment alone changes neither →
  # suppressed.
  #
  # Pre-v3 the ID included `.updatedAt` directly, so every PR comment / label
  # flip / CI re-run produced a new ID and re-woke the agent (BUG #14).
  gh_all_repos _q gh pr list \
    --label "cc:${ROLE}" \
    --state open \
    --limit 50 \
    --json number,title,url,updatedAt,isDraft,labels,headRefName,headRefOid
  echo "$_q" | jq "[ .[] |
           def is_author_self_cc_pr:
             ((.labels // []) | map(.name) | any(. == \"agent:${ROLE}\") and any(. == \"cc:${ROLE}\"));
           select(is_author_self_cc_pr | not) |
           {
             id: (\"pr-review-\" + (.number | tostring) + \"-\" + (.headRefOid[0:7]) + \"-\" + (.labels | map(.name) | sort | join(\"|\"))),
             kind: \"pr_review_requested\",
             number: .number,
             title: .title,
             url: .url,
             updated_at: .updatedAt,
             context: {
               isDraft: .isDraft,
               branch: .headRefName,
               head_sha: .headRefOid[0:7],
               labels: [.labels[].name]
             }
           } ]"
}

query_new_commits_on_assigned_prs() {
  # Explicit "new commit on cc:<role> PR" event — covers the case where
  # updatedAt didn't change enough to clear last_seen but the commit SHA did.
  # Belt-and-suspenders with query_review_requests; either firing wakes the agent.
  gh_all_repos _q gh pr list \
    --label "cc:${ROLE}" \
    --state open \
    --limit 50 \
    --json number,title,url,updatedAt,headRefOid,headRefName
  echo "$_q" | jq "[ .[] |
           def is_author_self_cc_pr:
             ((.labels // []) | map(.name) | any(. == \"agent:${ROLE}\") and any(. == \"cc:${ROLE}\"));
           select(is_author_self_cc_pr | not) |
           {
             id: (\"pr-commit-\" + (.number | tostring) + \"-\" + (.headRefOid[0:7])),
             kind: \"pr_new_commit\",
             number: .number,
             title: .title,
             url: .url,
             updated_at: .updatedAt,
             context: { head_sha: .headRefOid[0:7], branch: .headRefName }
           } ]"
}

query_pr_mentions() {
  # PRs where a comment mentions @<role> since last_seen.
  # We list open PRs touched after last_seen, then inspect their comments.
  local prs
  gh_all_repos prs gh pr list \
    --state open \
    --limit 30 \
    --json number,title,url,updatedAt

  echo "$prs" | jq "[ .[] | select(.updatedAt > \"$LAST_SEEN\") ]" | jq -r '.[].number' | while read -r num; do
    [ -z "$num" ] && continue
    gh pr view "$num" --repo "$REPO" --json number,title,url,comments,reviews \
      --jq "
        ([.comments[], .reviews[]] |
         map(select(.body != null and (.body | test(\"@${ROLE}\\\\b\"; \"i\"))) |
             select(.createdAt > \"$LAST_SEEN\" or .submittedAt > \"$LAST_SEEN\")) |
         # BUG #25 fix: include ${ROLE} in event ID so a single comment that
         # mentions both @developer and @tester produces TWO distinct events
         # (one per role's processed_event_ids ring). Drop the timestamp
         # fallback (.createdAt/.submittedAt) — those bump on comment edits
         # and re-wake the same role with the same comment, the exact pattern
         # that broke BUG #14 for pr_review_requested. .id is always present
         # for both comments and reviews per GitHub REST/GraphQL schemas.
         map({
           id: (\"pr-mention-\" + (\$num | tostring) + \"-\" + (.id | tostring) + \"-${ROLE}\"),
           kind: \"pr_comment_mention\",
           number: \$num,
           title: \"\",
           url: \"https://github.com/${REPO}/pull/\(\$num)\",
           updated_at: (.createdAt // .submittedAt),
           context: {
             author: (.author.login // \"unknown\"),
             body_preview: (.body[:300])
           }
         }))" \
      --jq-arg num "$num" 2>/dev/null || true
  done | jq -s 'add // []'
}

# v8 (ADR-0041 — `verdict_posted`): PR-comment verdict detection that does NOT
# require an @-mention. Closes the RCA gap from Issue #312 (PR #307 idled ~2h).
#
# Why this exists: Tester verdicts (🟢 APPROVED / 🟡 SUGGESTIONS / 🔴
# CHANGES_REQUESTED) typically follow a structured template that omits an
# explicit @-mention. The v7 `query_pr_mentions` only fires when the body
# contains `@<role>` — so structured verdicts went silently un-surfaced and
# the polling role idled until manual re-check.
#
# Scope guard (ADR-0041 §Detection scope — union of three label families):
#   1. `cc:<role>`            — someone explicitly cc'd this role
#   2. `agent:<role>`         — the role owns the PR
#   3. `verdict-by:<ts>`      — a deadline-bearing verdict expectation exists
# Open PRs only (closed PRs need no further verdict). The function widens
# Phase 0's `agent:<role>`-only scope to the full union per ADR-0041.
#
# Self-cc skip (v7, Issue #94): when a PR has BOTH `agent:<role>` AND
# `cc:<role>`, the role does not wake itself on its own PR's incoming verdict.
# Mirrors `is_author_self_cc_pr` used in `query_review_requests` /
# `query_new_commits_on_assigned_prs` / `query_stale_cc`. Without this skip,
# an author posting a self-verdict (rare but possible) would re-wake themselves
# in a loop.
#
# Severity precedence: `changes_requested > approved > suggestions`. The jq
# pipeline evaluates the three regexes in that order; first match wins. So a
# comment containing both 🟢 APPROVED and a later 🔴 CHANGES_REQUESTED clause
# classifies as `changes_requested` — the most severe verdict prevails.
#
# Dedup: event ID is `verdict-posted-<pr>-<comment_id_sha7>-b<bucket>` where
# `bucket = floor(unix_ts / 300)`. Same 5-min window as v6 `stale_verdict` /
# `stale_cc`, consistent with `processed_event_ids` ring dedup. Comment-ID
# sha7 (first 7 chars of the GH node ID) keeps the ID short while remaining
# globally unique per comment.
#
# Out of scope (separate ADRs if a gap emerges):
#   - i18n: keyword regexes are EN-only.
#   - PR Review API (`gh pr view --json reviews`): different data source.
#   - Issue comments: separate kind would be `issue_verdict_posted` if needed.
query_verdict_posted() {
  # 5-min bucket consistent with v6/v7 (stale_cc, stale_verdict).
  local now_epoch bucket
  now_epoch="$(date -u +%s)"
  bucket=$(( now_epoch / 300 ))

  # Verdict keyword regexes (ADR-0041 §Verdict classification table).
  # Word-boundary anchors (\b) tighten the FP guard — bare substring would
  # over-fire on words like "approval" or "approved-by". Emojis are matched
  # as UTF-8 bytes; jq's `test()` handles them transparently.
  local re_approved='(\\bAPPROVED\\b|\\bLGTM\\b|sign-?off|🟢)'
  local re_suggestions='(\\bSUGGESTIONS\\b|non-?blocking|🟡)'
  local re_changes='(\\bCHANGES_REQUESTED\\b|\\bREQUEST CHANGES\\b|\\bblocker\\b|🔴)'

  # In-scope PRs: open, with at least one of {cc:<role>, agent:<role>,
  # verdict-by:*}. We list all open PRs touched after LAST_SEEN and filter
  # by labels in jq (the GH search API only supports AND across labels, not
  # OR, so client-side filter is required).
  local prs
  gh_all_repos _raw_prs gh pr list \
    --state open \
    --limit 50 \
    --json number,title,url,updatedAt,labels
  prs="$(echo "$_raw_prs" | jq "
      [ .[] | select(.updatedAt > \"$LAST_SEEN\") |
              ((.labels // []) | map(.name)) as \$names |
              # Scope guard: agent:<role> OR cc:<role> OR verdict-by:*
              select(\$names | any(. == \"agent:${ROLE}\" or . == \"cc:${ROLE}\" or startswith(\"verdict-by:\"))) |
              # Self-cc skip (Issue #94): PR with BOTH agent:<role> AND
              # cc:<role> is the author-self-cc pattern; the same role should
              # not wake itself on its own PR's incoming verdict.
              select((\$names | any(. == \"agent:${ROLE}\")) and (\$names | any(. == \"cc:${ROLE}\")) | not) |
              {number: .number, title: .title, url: .url}
      ]" 2>/dev/null || echo '[]')"

  echo "$prs" | jq -r '.[].number' | while read -r num; do
    [ -z "$num" ] && continue
    gh pr view "$num" --repo "$REPO" --json number,title,url,comments \
      --jq "
        (.comments // []) |
        map(select(.body != null and .createdAt > \"$LAST_SEEN\")) |
        # Severity precedence: changes_requested > approved > suggestions.
        # Annotate each comment with its winning class + matched keyword.
        map(
          if (.body | test(\"$re_changes\"; \"i\")) then
            . + {_v: \"changes_requested\", _kw: ((.body | capture(\"(?<m>$re_changes)\"; \"i\")).m // \"changes_requested\")}
          elif (.body | test(\"$re_approved\"; \"i\")) then
            . + {_v: \"approved\", _kw: ((.body | capture(\"(?<m>$re_approved)\"; \"i\")).m // \"approved\")}
          elif (.body | test(\"$re_suggestions\"; \"i\")) then
            . + {_v: \"suggestions\", _kw: ((.body | capture(\"(?<m>$re_suggestions)\"; \"i\")).m // \"suggestions\")}
          else
            . + {_v: \"\"}
          end
        ) |
        map(select(._v != \"\")) |
        map({
          id: (\"verdict-posted-\" + (\$num | tostring) + \"-\" + (.id | tostring)[0:7] + \"-b${bucket}\"),
          kind: \"verdict_posted\",
          number: \$num,
          title: \"\",
          url: \"https://github.com/${REPO}/pull/\(\$num)\",
          updated_at: .createdAt,
          verdict: ._v,
          author: (.author.login // \"unknown\"),
          comment_id: (.id | tostring),
          comment_url: .url,
          pr_url: \"https://github.com/${REPO}/pull/\(\$num)\",
          role: \"${ROLE}\",
          context: {
            verdict_class: (\"verdict:\" + ._v),
            source: \"agent-watch.sh v8\",
            keyword_matched: ._kw
          }
        })" \
      --jq-arg num "$num" 2>/dev/null || true
  done | jq -s 'add // []'
}

# v4 (ADR-0017): issue-comment @<role> mentions.
# Mirrors query_pr_mentions for issues. The standup ceremony lives on a single
# threaded issue per sprint; without this detector, role-tagged status asks in
# issue comments fire no wake event.
query_issue_mentions() {
  # Issues touched after last_seen, whose comments contain @<role>.
  local issues
  # Issue #806: gh issue list --label silent-drop — switch to REST gh api
  # for uniform-fix (defensive; this site has no --label filter but the
  # architect listed it as affected to eliminate ALL silent-drop risk).
  gh_all_repos _issues_raw gh api \
    "repos/${REPO}/issues?state=open&per_page=30" \
    --jq "[.[] | {number, title, url: .html_url, updatedAt: .updated_at}]"
  issues="$(echo "$_issues_raw" | jq "[ .[] | select(.updatedAt > \"$LAST_SEEN\") ]" 2>/dev/null || echo '[]')"

  echo "$issues" | jq -r '.[].number' | while read -r num; do
    [ -z "$num" ] && continue
    # Issue body itself may contain mentions; check it on first poll-after-create.
    # For ongoing detection we focus on comments (issue body is covered by
    # query_assigned_issues / query_board_changes when labels are set).
    gh issue view "$num" --repo "$REPO" --json number,title,url,comments \
      --jq "
        (.comments |
         map(select(.body != null and (.body | test(\"@${ROLE}\\\\b\"; \"i\")))) |
         map(select(.createdAt > \"$LAST_SEEN\")) |
         # BUG #25 fix: mirror of pr_comment_mention fix — include ${ROLE}
         # in ID, drop the .createdAt timestamp fallback (which would bump
         # on comment edits and re-wake the agent for the same comment).
         map({
           id: (\"issue-mention-\" + (\$num | tostring) + \"-\" + (.id | tostring) + \"-${ROLE}\"),
           kind: \"issue_comment_mention\",
           number: \$num,
           title: \"\",
           url: \"https://github.com/${REPO}/issues/\\(\$num)\",
           updated_at: .createdAt,
           context: {
             author: (.author.login // \"unknown\"),
             body_preview: (.body[:300])
           }
         }))" \
      --jq-arg num "$num" 2>/dev/null || true
  done | jq -s 'add // []'
}

# v4 (ADR-0017): periodic backlog scan.
# Fires every PERIODIC_SCAN_INTERVAL_SEC (default 1800 = 30 min) per role, if
# the role has any open items with `agent:<role>` or `cc:<role>`, regardless
# of recent GitHub state changes. Surfaces the queue list so the agent's
# doctrine can pick up unblocked work even when the event stream is sparse.
#
# Throttle: state field `last_synthetic_scan_utc` prevents re-fire every poll.
# Bucketed by 5-min windows so the same wake doesn't re-fire every 60s if
# state-file write races the next poll.
query_periodic_backlog_scan() {
  local interval="${PERIODIC_SCAN_INTERVAL_SEC:-1800}"
  local now_epoch last_scan_epoch elapsed bucket
  now_epoch="$(date -u +%s)"
  bucket=$(( now_epoch / 300 ))

  local last_scan
  last_scan="$("$STATE_HELPER" get "$ROLE" last_synthetic_scan_utc 2>/dev/null || true)"
  if [ -n "$last_scan" ] && [ "$last_scan" != "null" ]; then
    last_scan_epoch="$(date -u -d "$last_scan" +%s 2>/dev/null || echo 0)"
    elapsed=$(( now_epoch - last_scan_epoch ))
    if [ "$elapsed" -lt "$interval" ]; then
      # Throttled — emit nothing
      echo '[]'
      return 0
    fi
  fi

  # Collect open issues + PRs with agent:<role> or cc:<role>
  # Issue #806: REST gh api (sister-pattern: L1778 Katman 1 count)
  local issues prs combined
  gh_all_repos _issues_raw gh api \
    "repos/${REPO}/issues?state=open&per_page=50" \
    --jq "[.[] | {number, title, url: .html_url, labels: [.labels[] | {name}]}]"
  issues="$(echo "$_issues_raw" | jq "[ .[] | select((.labels // []) | map(.name) | any(. == \"agent:${ROLE}\" or . == \"cc:${ROLE}\")) | {number, title, url, labels: (.labels | map(.name))} ]" 2>/dev/null || echo '[]')"
  gh_all_repos _prs_raw gh pr list \
    --state open \
    --limit 50 \
    --json number,title,url,labels
  prs="$(echo "$_prs_raw" | jq "[ .[] | select((.labels // []) | map(.name) | any(. == \"agent:${ROLE}\" or . == \"cc:${ROLE}\")) | {number, title, url, labels: (.labels | map(.name))} ]" 2>/dev/null || echo '[]')"
  combined="$(jq -s '.[0] + .[1]' <(echo "$issues") <(echo "$prs"))"

  local count
  count="$(echo "$combined" | jq 'length')"
  if [ "$count" -eq 0 ]; then
    # Queue empty — do not fire, do not advance HWM
    echo '[]'
    return 0
  fi

  # Fire: advance HWM and emit one synthetic event with queue list in context
  local now_iso
  now_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  "$STATE_HELPER" set "$ROLE" last_synthetic_scan_utc "\"$now_iso\"" >/dev/null 2>&1 || true

  jq -n \
    --arg role "$ROLE" \
    --arg now "$now_iso" \
    --arg bucket "$bucket" \
    --arg url "https://github.com/${REPO}/issues?q=is%3Aopen+label%3Aagent%3A${ROLE}" \
    --arg count "$count" \
    --argjson items "$combined" '
    [ {
      id: ("backlog-scan-" + $role + "-b" + $bucket),
      kind: "periodic_backlog_scan",
      number: 0,
      title: ("Periodic backlog scan \u2014 " + $count + " open item(s) in queue"),
      url: $url,
      updated_at: $now,
      context: {
        role: $role,
        open_items: $items,
        note: "Synthetic wake \u2014 no recent GitHub state change. Reason: catch stuck queues when event stream is sparse (ADR-0017)."
      }
    } ]
  '
}

# v5 (Issue #44 \u2014 Proactive Board Scan): 4 board-anomaly detections that fire
# on a separate cadence from the periodic backlog scan. Throttled to
# PROACTIVE_SWEEP_INTERVAL_SEC (default 300 = 5 min) per role, but currently
# ONLY FIRES for the orchestrator role (the orchestrator is the one who
# needs to act on these). Kill switch PROACTIVE_SWEEP_ENABLED=false bypasses
# the entire function (returns [] with no state read or write).
#
# Detections (4):
#   D1 ready_unblocked  \u2014 status:ready + body "Blocked by: #X,#Y" + ALL closed
#   D2 orphan_backlog   \u2014 status:backlog + no cc:* label
#   D3 stalled          \u2014 status:in-progress > 4h, no PR opened (4h default
#                          can be tightened via STALLED_THRESHOLD_SEC env)
#   D4 wip_overflow     \u2014 3+ status:in-progress (WIP > 2)
#
# Out-of-scope (separate issues): #45 STATUS action driver, #46 stale_verdict
# watchdog rewrite, #47 atomic-label-edit.sh.
query_proactive_sweep() {
  # Wrapper around standalone scripts/proactive-board-scan.sh (extracted for
  # PR-T1 template port; see AtilCalculator #48 PR-T1, owner decision
  # 2026-06-21T08:42Z). Logic moved 2026-06-21; behavior identical to
  # previous inline impl.
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local scan_script="$script_dir/proactive-board-scan.sh"
  if [ ! -f "$scan_script" ]; then
    echo "ERROR: $scan_script not found (refactor incomplete)" >&2
    echo '[]'
    return 0
  fi
  REPO="$REPO" ROLE="$ROLE" \
    PROACTIVE_SWEEP_ENABLED="${PROACTIVE_SWEEP_ENABLED:-true}" \
    PROACTIVE_SWEEP_INTERVAL_SEC="${PROACTIVE_SWEEP_INTERVAL_SEC:-300}" \
    STALLED_THRESHOLD_SEC="${STALLED_THRESHOLD_SEC:-14400}" \
    STATE_HELPER="$STATE_HELPER" \
    bash "$scan_script"
}

query_stale_cc() {
  # Deadlock breaker: if cc:<role> has sat on a PR for > STALE_CC_SEC without
  # any state change (no new commit, no new review, no label flip), emit a
  # stale_cc event. The agent picks it up and either acts or explicitly punts
  # the label back. Prevents permanent stall when an event was lost (watcher
  # restart, tmux send-keys race, processed_event_ids corruption).
  #
  # The event ID is bucketed by 5-minute windows so the same stall doesn't
  # spam wake-ups every poll — it re-fires at most every ~5 min until cleared.
  local now_epoch bucket
  now_epoch="$(date -u +%s)"
  bucket=$(( now_epoch / 300 ))

  gh_all_repos _q gh pr list \
    --label "cc:${ROLE}" \
    --state open \
    --limit 50 \
    --json number,title,url,updatedAt,headRefOid,labels
  echo "$_q" | jq "[ .[] |
           def is_author_self_cc_pr:
             ((.labels // []) | map(.name) | any(. == \"agent:${ROLE}\") and any(. == \"cc:${ROLE}\"));
           select(is_author_self_cc_pr | not) |
           ((now - (.updatedAt | fromdateiso8601)) | floor) as \$age |
           select(\$age > ${STALE_CC_SEC}) |
           {
             id: (\"stale-cc-\" + (.number | tostring) + \"-\" + (.headRefOid[0:7]) + \"-b${bucket}\"),
             kind: \"stale_cc\",
             number: .number,
             title: .title,
             url: .url,
             updated_at: .updatedAt,
             context: {
               age_sec: \$age,
               head_sha: .headRefOid[0:7],
               note: \"cc:${ROLE} unchanged for >${STALE_CC_SEC}s; deadlock-breaker wake.\"
             }
           } ]"
}

# v6 (ADR-0024): query_stale_verdict — deadline-based watchdog.
#
# Replaces stale_cc's stall target from "label presence" to "review verdict
# expectation". A PR with `cc:<role>` but NO `verdict-by:<ts>` label is NOT
# stale — there is no expectation to miss. A PR with `verdict-by:<ts>` whose
# deadline has passed IS stale — emit `stale_verdict` so the agent wakes and
# either delivers the verdict or extends the deadline (with rationale).
#
# Event ID = `stale-verdict-<n>-<sha7>-b<bucket>` (5-min window, same throttle
# scheme as stale_cc). The verdict-by ISO timestamp is captured in `context`
# for the agent to display. Re-fire suppression: same head_sha + same bucket
# → same ID → dedup catches it. Extending the deadline bumps head_sha (new
# commit) or rolls into a new bucket → new event → re-wake.
#
# Quiet under docs PRs (ADR-0021): docs PRs SHOULD NOT carry verdict-by; if
# they do, this fires the moment the deadline passes (correct — the agent
# should either remove the cc:* or add a verdict-by to reflect an actual
# expectation).
query_stale_verdict() {
  # Verdict-authority lane discriminator: agent:${ROLE} (assigned owner, ADR-0024)
  # OR cc:human (owner merge gate holding for verdict, ADR-0031).
  # Excludes cc:<peer> informational lane (false-positive root cause per Issue #798).
  local now_epoch bucket
  now_epoch="$(date -u +%s)"
  bucket=$(( now_epoch / 300 ))

  # ADR-0002-amendment-1 (Issue #798 #802, d320+d124 sister-pattern): VERDICT-AUTHORITY scope.
  # The previous --label "cc:${ROLE}" pre-filter was a false-positive generator (cc:<peer>
  # informational lane conflated with verdict authority per ADR-0015 §Handoff Discipline).
  # Fetch ALL open PRs (limit 100), then jq-side filter for VERDICT-AUTHORITY lanes only:
  #   - agent:<role> per ADR-0024 (this role is the assigned owner)
  #   - cc:human per ADR-0031 (owner merge gate holding for verdict)
  # Excludes cc:<peer> informational lane = false-positive root cause.
  gh_all_repos _q gh pr list \
    --state open \
    --limit 100 \
    --json number,title,url,updatedAt,headRefOid,labels,files,statusCheckRollup
  echo "$_q" | jq --argjson now_epoch "$now_epoch" "[
      .[] |
      (.labels | map(.name)) as \$lbls |
      # ADR-0002-amendment-2 (Issue #846 / d124 TC5): cc:<role> presence gate.
      # cc:human alone is the owner merge gate (ADR-0031) — but a role's
      # stale_verdict wake must ALSO require cc:<role> to be currently on
      # the PR. Without this, agents get woken when cc:human is on a PR
      # but their own lane already finished (e.g., cc:orchestrator removed
      # at 2026-07-04T09:08:26 but stale_verdict kept firing through 05:08:37Z
      # on PR #799 — see Issue #846 production evidence). Sister-pattern to
      # amendment-1 (VERDICT-AUTHORITY scope, Issue #802 / d320).
      (
        (\$lbls | any(. == \"agent:${ROLE}\")) or
        ((\$lbls | any(. == \"cc:human\")) and (\$lbls | any(. == \"cc:${ROLE}\")))
      ) as \$is_verdict_authority |
      select(\$is_verdict_authority) |
      # ADR-0044 §Scope rule — TDD RED exclusion (skip SLA pressure on contract-only PRs).
      #   (a) `contract:tdd-red` label present, OR
      #   (b) defense in depth: all changed files match test-only patterns AND CI is FAILURE
      # Test-only patterns per ADR-0044 §Decision + Issue #387 (TD-031) basename-anchored:
      #   - tests/* (directory prefix)
      #   - basename matches ^(test_*.{py,sh}|*_test.{py,sh}|*.test.{ts,js}|*.spec.{ts,js}|*Test.java)$
      # The basename anchor (TD-031) closes the over-exclusion window: paths like
      # `src/latest_data.py` previously matched via the unanchored test() — substring
      # `test_` in `latest_data` triggered false-positive exclusion.
      (
        ((\$lbls | any(. == \"contract:tdd-red\")))
        or
        (
          (((.files // []) | length) > 0)
          and
          ((.files // []) | all(
            ((.path | split(\"/\") | last) as \$bn |
             (\$bn | test(\"^(test_.*\\\\.(py|sh)|.*_test\\\\.(py|sh)|.*\\\\.test\\\\.(ts|js)|.*\\\\.spec\\\\.(ts|js)|.*Test\\\\.java)$\")) or
             (.path | startswith(\"tests/\")))
          ))
          and
          (((.statusCheckRollup // {}).state // \"UNKNOWN\") == \"FAILURE\")
        )
      ) as \$is_tdd_red |
      select(\$is_tdd_red | not) |
      (\$lbls | map(select(startswith(\"verdict-by:\"))) | first // empty) as \$vb |
      select(\$vb != \"\" and \$vb != null) |
      (\$vb | sub(\"verdict-by:\"; \"\") | fromdateiso8601? // empty) as \$deadline |
      select(\$deadline != null and \$deadline != \"\" and \$now_epoch > \$deadline) |
      {
        id: (\"stale-verdict-\" + (.number | tostring) + \"-\" + (.headRefOid[0:7]) + \"-b${bucket}\"),
        kind: \"stale_verdict\",
        number: .number,
        title: .title,
        url: .url,
        updated_at: .updatedAt,
        context: {
          deadline: \$vb,
          age_sec: ((\$now_epoch - \$deadline) | floor),
          head_sha: .headRefOid[0:7],
          note: \"verdict-by deadline passed for cc:${ROLE}; verdict expected, none received.\"
        }
      }
    ]"
}

# v6 (ADR-0024): query_missing_expectation — convention violation catch.
#
# A PR with `cc:<role>` but NO `verdict-by:<ts>` label violates the new
# convention (ADR-0024 §Decision). Emit `missing_expectation` once per
# (PR, head_sha) so the agent can either add a verdict-by label (with
# explicit time bound) or remove the cc label. Idempotent: same head_sha
# → same event ID → dedup catches re-fires until a new commit lands (which
# bumps head_sha → re-wake to confirm convention is still followed).
#
# Event ID = `missing-expectation-<n>-<sha7>` (no bucket — dedup is by
# head_sha only, since this is a state-of-the-PR check, not a time check).
query_missing_expectation() {
  gh pr list \
    --label "cc:${ROLE}" \
    --state open \
    --limit 50 \
    --json number,title,url,updatedAt,headRefOid,labels,files,statusCheckRollup
  echo "$_q" | jq "[
      .[] |
      (.labels | map(.name)) as \$lbls |
      # ADR-0044 §Scope rule — TDD RED exclusion (skip convention-violation wake on contract-only PRs).
      # A TDD RED PR may not have verdict-by yet because the impl hasn't landed — that's not a
      # convention violation, it's a lifecycle stage. Same logic as query_stale_verdict, including
      # TD-031 basename anchor (Issue #387) closing the substring-overlap over-exclusion window.
      (
        ((\$lbls | any(. == \"contract:tdd-red\")))
        or
        (
          (((.files // []) | length) > 0)
          and
          ((.files // []) | all(
            ((.path | split(\"/\") | last) as \$bn |
             (\$bn | test(\"^(test_.*\\\\.(py|sh)|.*_test\\\\.(py|sh)|.*\\\\.test\\\\.(ts|js)|.*\\\\.spec\\\\.(ts|js)|.*Test\\\\.java)$\")) or
             (.path | startswith(\"tests/\")))
          ))
          and
          (((.statusCheckRollup // {}).state // \"UNKNOWN\") == \"FAILURE\")
        )
      ) as \$is_tdd_red |
      select(\$is_tdd_red | not) |
      select((\$lbls | map(select(startswith(\"verdict-by:\"))) | length) == 0) |
      {
        id: (\"missing-expectation-\" + (.number | tostring) + \"-\" + (.headRefOid[0:7])),
        kind: \"missing_expectation\",
        number: .number,
        title: .title,
        url: .url,
        updated_at: .updatedAt,
        context: {
          head_sha: .headRefOid[0:7],
          cc_label: \"cc:${ROLE}\",
          note: \"cc:${ROLE} set without verdict-by:<ts> expectation (ADR-0024 convention violation).\"
        }
      }
    ]"
}

# v3 (ADR-0005): post-merge lifecycle. Fan out pr-merged events to the roles
# listed in PR_MERGED_FANOUT_ROLES so developer/PM/orchestrator can run their
# cleanup workflows (branch prune, board update, sprint refresh) without manual
# pokes. Event ID = `pr-merged-<n>-<sha7>` where sha7 is the merge commit short
# SHA — unique per merge so re-merges (force-push to main, rare) re-fire cleanly.
#
# Dedup defense:
#   1. `pr_merged_last_seen_utc` high-water mark filters the gh query.
#   2. `processed_event_ids` ring buffer (poll_once) drops anything already seen.
#   3. Event ID embeds merge SHA — same PR re-merged with new SHA = new event.
# Side-channel: query_pr_merged exposes the newest merged_at it SAW (across all
# merged PRs in the window, regardless of label filter) via the global
# PR_MERGED_NEWEST_SEEN. This lets the HWM update advance even when label rules
# filter every PR out for this role — otherwise architect/tester would re-query
# the same backfill window forever and rely on dedup to suppress duplicates.
PR_MERGED_NEWEST_SEEN=""

query_pr_merged() {
  PR_MERGED_NEWEST_SEEN=""
  role_receives_pr_merged "$ROLE" || { echo '[]'; return; }

  # Fetch all merged PRs in the backfill window with their labels.
  local raw
  gh_all_repos _raw_prs gh pr list \
    --state merged \
    --search "merged:>${PR_MERGED_LAST_SEEN}" \
    --limit 50 \
    --json number,title,url,mergedAt,mergeCommit,author,labels
  raw="$(echo "$_raw_prs" | jq "[ .[] |
           select(.mergeCommit != null and .mergeCommit.oid != null) |
           {
             id: (\"pr-merged-\" + (.number | tostring) + \"-\" + (.mergeCommit.oid[0:7])),
             kind: \"pr_merged\",
             number: .number,
             title: .title,
             url: .url,
             updated_at: .mergedAt,
             context: {
               merge_sha: .mergeCommit.oid[0:7],
               merged_at: .mergedAt,
               author: (.author.login // \"unknown\"),
               labels: [.labels[].name]
             }
           } ]")"

  # v3.1.1: bump HWM here (not in poll_once) so we don't depend on a global
  # surviving the $(query_pr_merged) subshell. Subshells lose parent vars.
  local newest
  newest="$(echo "$raw" | jq -r '[.[].context.merged_at] | max // empty')"
  PR_MERGED_NEWEST_SEEN="$newest"  # kept for backward compat / unit tests
  if [ -n "$newest" ] && [ "$newest" != "null" ]; then
    "$STATE_HELPER" set "$ROLE" pr_merged_last_seen_utc "\"$newest\""
  fi

  # v3.1 (ADR-0008): per-PR label-conditional filter.
  # Default-fanout roles keep every PR (D2 behaviour, fast path).
  # Architect/tester only keep PRs whose labels match the configured rules.
  if role_in_default_fanout "$ROLE"; then
    echo "$raw"
    return
  fi

  # Walk the events one by one so each label set is checked by jq separately.
  local filtered='[]' n i evt labels
  n="$(echo "$raw" | jq 'length')"
  i=0
  while [ "$i" -lt "$n" ]; do
    evt="$(echo "$raw" | jq -c ".[$i]")"
    labels="$(echo "$evt" | jq -c '.context.labels')"
    if role_wakes_for_pr "$ROLE" "$labels"; then
      filtered="$(jq -c -n --argjson acc "$filtered" --argjson e "$evt" '$acc + [$e]')"
    fi
    i=$((i+1))
  done
  echo "$filtered"
}

# v3.2 (ADR-0009 D2.2): PR-open architect/tester routing via pr_labeled.
#
# Why not Events API? Per ADR-0009 § 3 "Alternatives", we use the cheaper
# `gh pr list --state open` query with PR.updatedAt as HWM proxy. Cost:
# 1 API call per role per poll (only architect/tester are enrolled by default,
# so 2 calls/min total). Trade-off vs label-event precision is logged as
# TD-002 (docs/tech-debt.md) with a 5%-suppression-rate payoff trigger.
#
# Event ID = `pr-labeled-<n>-<updatedAt>` — stable per (PR, wake-tick). Re-poll
# of the same PR within one updatedAt window produces the same ID, which the
# processed_event_ids ring suppresses. A force-push or comment bumps updatedAt
# → new ID → re-wake (acceptable; agent sees fresh signal).
#
# Suppression observability: when role_receives_pr_labeled is true but no PR
# matches role_wakes_for_pr_labeled, we still advance the HWM (D2.1.2 pattern).
# Future TD-002 instrumentation will log pr_labeled_suppressed_quick_removal
# when the dedup ring detects > 5% same-PR re-evaluation churn (deferred to D2.2.1).
PR_LABELED_NEWEST_SEEN=""

query_pr_labeled() {
  PR_LABELED_NEWEST_SEEN=""
  role_receives_pr_labeled "$ROLE" || { echo '[]'; return; }

  # Fetch all OPEN PRs with their labels + updatedAt.
  local raw
  gh_all_repos _raw_prs gh pr list \
    --state open \
    --limit 50 \
    --json number,title,url,updatedAt,labels,isDraft
  raw="$(echo "$_raw_prs" | jq "[ .[] | select(.updatedAt > \"$PR_LABELED_LAST_SEEN\") |
           {
             number,
             title,
             url,
             updatedAt,
             isDraft,
             labels: [.labels[].name]
           } ]" 2>/dev/null || echo '[]')"

  # D2.1.2-style inline HWM bump: advance even when label filter drops all PRs.
  local newest
  newest="$(echo "$raw" | jq -r '[.[].updatedAt] | max // empty')"
  PR_LABELED_NEWEST_SEEN="$newest"
  if [ -n "$newest" ] && [ "$newest" != "null" ]; then
    "$STATE_HELPER" set "$ROLE" pr_labeled_last_seen_utc "\"$newest\""
  fi

  # Per-PR filter: only keep PRs whose labels match this role's wake-trigger set.
  local filtered='[]' n i pr labels_json wake_reason
  n="$(echo "$raw" | jq 'length')"
  i=0
  while [ "$i" -lt "$n" ]; do
    pr="$(echo "$raw" | jq -c ".[$i]")"
    labels_json="$(echo "$pr" | jq -c '.labels')"
    if role_wakes_for_pr_labeled "$ROLE" "$labels_json"; then
      wake_reason="$(pr_labeled_wake_reason "$ROLE" "$labels_json")"
      filtered="$(jq -c -n \
        --argjson acc "$filtered" \
        --argjson p "$pr" \
        --arg reason "label:${wake_reason}" \
        '$acc + [{
          id: ("pr-labeled-" + ($p.number | tostring) + "-" + ($p.labels | sort | join("|"))),
          kind: "pr_labeled",
          number: $p.number,
          title: $p.title,
          url: $p.url,
          updated_at: $p.updatedAt,
          context: {
            labels: $p.labels,
            wake_reason: $reason,
            pr_state: "open",
            isDraft: $p.isDraft
          }
        }]')"
    fi
    i=$((i+1))
  done
  echo "$filtered"
}

# Orchestrator has a wider lens: all label changes on any issue/PR.
query_board_changes() {
  # RCA-19 / ADR-0036 §Part A: role-aware label change visibility.
  #   - ROLE=orchestrator: return all label changes on any issue (unchanged
  #     behavior — back-compat with orchestrator's board lens).
  #   - other roles: return label changes ONLY on issues with `agent:<role>`
  #     label present (so the role wakes when its own queue's status flips).
  # Event ID is content-stable AND role-scoped: id = "board-${role}-${n}-${sorted}"
  # — prevents dedup collisions when two roles see the same issue's flip.
  if [ "$ROLE" != "orchestrator" ]; then
    # Filter to agent:<role> issues only.
    # Issue #806: REST gh api (sister-pattern: L1778). State=all to keep
    # both open and closed issues for label-change diff detection.
    gh_all_repos _q gh api \
      "repos/${REPO}/issues?state=all&per_page=50" \
      --jq "[.[] | {number, title, url: .html_url, updatedAt: .updated_at, state, labels: [.labels[] | {name}]}]"
    echo "$_q" | jq "[ .[] | select(.updatedAt > \"$LAST_SEEN\") |
             select((.labels | map(.name) | index(\"agent:$ROLE\")) != null) |
             {
               id: (\"board-$ROLE-\" + (.number | tostring) + \"-\" + (.labels | map(.name) | sort | join(\"|\"))),
               kind: \"label_change\",
               number: .number,
               title: .title,
               url: .url,
               updated_at: .updatedAt,
               context: { state: .state, labels: [.labels[].name] }
             } ]"
    return
  fi
  # Recent issue events for label/assignee changes since last_seen.
  # v3.5 (issue #6 fix): event ID is content-stable — derived from sorted label
  # set, NOT updatedAt. See query_assigned_issues for the full rationale.
  # Idempotent label flips (add X then remove X) collapse to the same ID, which
  # the processed_event_ids dedup catches; only net changes to the label set
  # produce a new event.
  # RCA-19 / ADR-0036: orchestrator event ID also role-scoped for consistency.
  # Issue #862 fix: capture gh output into _q (matches 7 sister call sites L590,
  # L630, L669, L698, L1044, L1103, L1396). Bare `gh issue list` with no capture
  # would leak `_q: unbound variable` under `set -u` (line 138) AND the outer
  # `add | unique_by(.id)` would collapse raw gh entries (no .id) to 1 most-recent.
  gh_all_repos _q gh issue list \
    --state all \
    --limit 50 \
    --json number,title,url,updatedAt,labels,state
  echo "$_q" | jq "[ .[] | select(.updatedAt > \"$LAST_SEEN\") |
           {
             id: (\"board-$ROLE-\" + (.number | tostring) + \"-\" + (.labels | map(.name) | sort | join(\"|\"))),
             kind: \"label_change\",
             number: .number,
             title: .title,
             url: .url,
             updated_at: .updatedAt,
             context: { state: .state, labels: [.labels[].name] }
           } ]"
}

# --- tmux pane wake-up (title-based) ---
# Find pane by title (role uppercase) and inject a wake-up prompt via send-keys.
# Safe to call when not inside tmux — silently no-ops.
wake_pane_for_role() {
  local role="$1"
  local events_json="$2"
  local count
  count="$(echo "$events_json" | jq 'length')"
  [ "$count" -gt 0 ] || return 0

  # tmux available?
  command -v tmux >/dev/null 2>&1 || return 0
  tmux has-session -t "$TMUX_SESSION" 2>/dev/null || return 0

  # Find pane id by title (uppercase role). Fallback: deterministic index map.
  local role_upper
  role_upper="$(echo "$role" | tr '[:lower:]' '[:upper:]')"

  local pane_id
  pane_id="$(tmux list-panes -t "$TMUX_SESSION" -F '#{pane_id} #{pane_title}' 2>/dev/null \
    | awk -v t="$role_upper" '$2 == t { print $1; exit }')"

  # Fallback index map (matches dev-studio-start.sh layout)
  if [ -z "$pane_id" ]; then
    case "$role" in
      orchestrator)    pane_id="${TMUX_SESSION}:main.0" ;;
      product-manager) pane_id="${TMUX_SESSION}:main.1" ;;
      architect)       pane_id="${TMUX_SESSION}:main.2" ;;
      developer)       pane_id="${TMUX_SESSION}:main.3" ;;
      tester)          pane_id="${TMUX_SESSION}:main.4" ;;
      *) return 0 ;;
    esac
  fi

  # Compose pretty-printed wake-up prompt (heredoc-safe).
  local pretty
  pretty="$(echo "$events_json" | jq '.')"

  local prompt
  prompt="🔔 INBOX (auto-wake from agent-watch loop):
${pretty}

Lütfen pickup et: review yap, label flip et, peer'i bilgilendir, sonra heartbeat yaz ve queue'ya dön."

  # Send prompt then Enter. Use literal mode (-l) so backticks/quotes survive.
  # TD-068b (Issue #935): env-override sleep between text and Enter (default 0.5s, override via WAKE_KEYS_GAP_SEC) prevents tmux from collapsing both into a single literal keystroke under load.
  tmux send-keys -t "$pane_id" -l "$prompt" 2>/dev/null || return 0
  sleep "${WAKE_KEYS_GAP_SEC:-0.5}"
  tmux send-keys -t "$pane_id" Enter 2>/dev/null || true
}

# ============================================================================
# Hardening section (Issue #461 STORY-d052, Sprint 12 P2 dev TCs)
# ----------------------------------------------------------------------------
# Per cmt 4812587954 (Issue #414 5-soul §Dispatch Discipline amend), 4 dev-side
# hardening features added to scripts/agent-watch.sh:
#   T1: self-wake filter       — skip wake events whose sender == ROLE
#                                 (avoids ADR-0033 Telegram mirror loop)
#   T2: cross-wake re-query hint — wake payload includes re_query_hint:true
#                                   when source is peer-attributed
#   T3: post-compact REPRIME flag — REPRIME=1 clears processed_event_ids +
#                                    forces full re-query
#   T4: stale-state re-query dispatch — STALE_STATE_THRESHOLD_SEC (default 900)
#                                       triggers periodic re-query
#
# All features opt-in via env vars (backward-compat: existing 5 agents
# unaffected unless they opt-in). Sister-pattern with d051 test framework
# (tester lane, PR #460 merged).
# ============================================================================

# T1 — self_wake_filter: returns 0 if event should be filtered (skip wake),
# 1 if event should be processed. Opt-in via AGENT_WATCH_SELF_FILTER=1.
#
# Pattern: event JSON has context.sender_role field. If that equals the
# polling ROLE and opt-in is enabled, skip. Events without sender_role
# field pass through (no false positives on legacy events).
is_self_wake() {
  local event_json="$1"
  # Opt-in guard
  [ "${AGENT_WATCH_SELF_FILTER:-0}" = "1" ] || return 1
  # Extract sender_role from context
  local sender_role
  sender_role="$(echo "$event_json" | jq -r '.context.sender_role // empty' 2>/dev/null)"
  [ -n "$sender_role" ] || return 1
  # Match against polling role
  [ "$sender_role" = "$ROLE" ]
}

# T2 — cross_wake_re_query_hint: tag peer-attributed wake events with a hint
# that tells the receiving agent to re-query ground truth before acting.
# This addresses dev miss #3 (PM RETEST on PR #456 cross-in-flight noise).
#
# Pattern: when constructing the wake payload, inject "re_query_hint": true
# into the event's context if the source is peer-attributed (not self).
apply_re_query_hint() {
  local event_json="$1"
  # Tag with re_query_hint:true (peer-attributed events only — events from
  # GitHub polling are always peer-attributed since agent-watch queries
  # external state)
  echo "$event_json" | jq -c '.context.re_query_hint = true' 2>/dev/null || echo "$event_json"
}

# T3 — REPRIME mode: clears processed_event_ids from state file + resets
# last_seen_utc high-water marks, forcing a full re-query on next poll.
# Use case: post-context-compact REPRIME per Issue #414 §Dispatch Discipline.
#
# Pattern: REPRIME=1 env var (or --reprime CLI flag) checked at top of
# poll_once(). When set, jq-edit state file to empty processed_event_ids
# array + reset last_seen_utc to epoch start, then unset REPRIME so the
# next poll cycle doesn't re-trigger.
reprime_state() {
  local state_file="$1"
  [ -f "$state_file" ] || return 0
  local tmp
  tmp="$(mktemp "${state_file}.reprime.XXXXXX")"
  if jq '.processed_event_ids = [] | .last_seen_utc = "1970-01-01T00:00:00Z"' \
       "$state_file" > "$tmp" 2>/dev/null; then
    sync "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$state_file"
    log "INFO" "REPRIME: state file reset for $ROLE (processed_event_ids cleared, last_seen_utc reset)"
    return 0
  fi
  rm -f "$tmp" 2>/dev/null || true
  return 1
}

# T4 — stale_state_re_query: when state file's last_seen_utc is older than
# STALE_STATE_THRESHOLD_SEC (default 900 = 15 min), treat state as stale
# and trigger a full re-query (same effect as REPRIME but automatic).
#
# Pattern: compute age of last_seen_utc. If age > threshold, jq-edit state
# to clear processed_event_ids. Logs the dispatch event for observability.
stale_state_re_query() {
  local state_file="$1"
  local threshold="${STALE_STATE_THRESHOLD_SEC:-900}"
  [ -f "$state_file" ] || return 1
  local last_seen_utc now_epoch last_seen_epoch age_sec
  last_seen_utc="$(jq -r '.last_seen_utc // empty' "$state_file" 2>/dev/null)"
  [ -n "$last_seen_utc" ] || return 1
  last_seen_epoch="$(date -u -d "$last_seen_utc" +%s 2>/dev/null || echo 0)"
  now_epoch="$(date -u +%s)"
  age_sec=$(( now_epoch - last_seen_epoch ))
  if [ "$age_sec" -gt "$threshold" ]; then
    log "INFO" "stale_state_re_query: $ROLE state age ${age_sec}s > threshold ${threshold}s — triggering re-query"
    reprime_state "$state_file"
    return 0
  fi
  return 1
}

# --- the actual poll ---
poll_once() {
  local now
  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  # T3 — REPRIME mode (Issue #461 d052): if REPRIME=1 set, reset state file
  # BEFORE heartbeat so the next poll cycle sees a clean slate. Unset
  # REPRIME so subsequent polls don't re-trigger.
  if [ "${REPRIME:-0}" = "1" ]; then
    local state_file_reprime
    state_file_reprime="$("$STATE_HELPER" path "$ROLE")"
    reprime_state "$state_file_reprime" || log "WARN" "REPRIME failed for $ROLE"
    unset REPRIME
  fi

  # T4 — stale-state re-query dispatch (Issue #461 d052): if state file's
  # last_seen_utc is older than STALE_STATE_THRESHOLD_SEC, trigger reprime.
  # Opt-in via env var (default 900s = 15min); set to 0 to disable.
  if [ "${STALE_STATE_THRESHOLD_SEC:-900}" -gt 0 ] 2>/dev/null; then
    local state_file_stale
    state_file_stale="$("$STATE_HELPER" path "$ROLE")"
    stale_state_re_query "$state_file_stale" || true
  fi

  # Heartbeat FIRST — even if the rest fails, doctor can see we're alive.
  "$STATE_HELPER" heartbeat "$ROLE" >/dev/null 2>&1 || true

  # Issue #238 sub-task 2 (PR #245): synthetic is_alive heartbeat emitted every
  # IS_ALIVE_INTERVAL_SEC (default 300s = 5min), independent of queue state.
  # Catches the "watcher stuck in rate-limited gh api loop" silent-drop class
  # (architect silenced 2026-06-22T06:46Z RCA, tester silenced 2026-06-22T06:46Z
  # RCA). The 5-min synthetic signal lets the doctor + orchestrator detect a
  # silently-stuck watcher via `last_is_alive_utc` field in state.
  local is_alive_interval last_is_alive_utc last_is_alive_epoch now_epoch emit_is_alive
  is_alive_interval="${IS_ALIVE_INTERVAL_SEC:-300}"
  last_is_alive_utc="$("$STATE_HELPER" get "$ROLE" last_is_alive_utc 2>/dev/null || echo "")"
  emit_is_alive=false
  if [ -z "$last_is_alive_utc" ] || [ "$last_is_alive_utc" = "null" ]; then
    emit_is_alive=true
  else
    last_is_alive_epoch="$(date -u -d "$last_is_alive_utc" +%s 2>/dev/null || echo 0)"
    now_epoch="$(date -u +%s)"
    if [ "$(( now_epoch - last_is_alive_epoch ))" -gt "$is_alive_interval" ]; then
      emit_is_alive=true
    fi
  fi
  local is_alive_event='[]'
  if [ "$emit_is_alive" = "true" ]; then
    is_alive_event="$(jq -n \
      --arg role "$ROLE" \
      --arg now "$now" \
      --argjson interval "$is_alive_interval" \
      '[
         {
           kind: "is_alive",
           id: ("is-alive-" + $role + "-" + $now),
           number: 0,
           title: ("is_alive heartbeat: " + $role),
           url: "",
           updated_at: $now,
           context: { role: $role, interval_sec: $interval }
         }
       ]')"
    "$STATE_HELPER" set "$ROLE" last_is_alive_utc "\"$now\"" >/dev/null 2>&1 || true
  fi

  # ADR-0032 RCA-18 fix (RCA-32): prune processed_event_ids entries older than
  # 24h (288 × 5min buckets) from the dedup buffer BEFORE downstream queries
  # and the dedup filter see it. Without this, historical stale-cc events from
  # past conditions accumulate up to the 200-cap and bias the buffer tail
  # toward 3-day-old events (refs Issue #216 RCA-18, PR #217 ADR). The
  # if/test() pattern RETAINs non-bucket IDs (wake_nudge, pr-merged,
  # pr-review) — they're bounded by their own throttle, not by bucket age.
  #
  # RCA-32 v2 (fix for P0 type-bug found by tester on PR #224): do the jq edit
  # DIRECTLY on the state file, NOT via "$STATE_HELPER set ... processed_event_ids
  # <json-array-string>". `cmd_set` uses `--arg` which treats its 3rd arg as a
  # STRING literal — so a JSON-array string got stored as a string, not an
  # array. After the first post-deploy poll, `processed_event_ids` would be
  # a string in the file, breaking `cmd_seen` substring dedup, `cmd_trim`'s
  # .[-max:] slice, and `length` reporting. Bypassing `cmd_set` here means
  # the file is read as JSON, the filter runs, and the array type is
  # preserved. The same jq filter is used in `cmd_trim`'s TTL branch which
  # already uses `jq_inplace` directly and works correctly.
  local current_bucket prune_cutoff_bucket state_file_ttl
  current_bucket=$(( $(date -u +%s) / 300 ))
  prune_cutoff_bucket=$(( current_bucket - 288 ))
  state_file_ttl="$("$STATE_HELPER" path "$ROLE")"
  if [ -f "$state_file_ttl" ]; then
    local tmp_ttl
    tmp_ttl="$(mktemp)"
    if jq --argjson cutoff "$prune_cutoff_bucket" '
      .processed_event_ids = (
        [ .processed_event_ids[] |
          if test("b[0-9]+$") then
            (capture("b(?<bucket>[0-9]+)$").bucket | tonumber) as $b |
            select($b >= $cutoff)
          else
            .  # wake_nudge / pr-merged / pr-review — retain
          end
        ]
      )
    ' "$state_file_ttl" > "$tmp_ttl" 2>/dev/null; then
      mv "$tmp_ttl" "$state_file_ttl"
    else
      rm -f "$tmp_ttl" 2>/dev/null || true
    fi
  fi

  # BUG-#61 fix: refresh HWMs from state at the start of every poll, so a
  # long-running --loop watcher's local HWM vars don't drift behind the state
  # file's HWM (which advances on every poll's tail below at `$STATE_HELPER set
  # ... last_seen_utc "$now"`). The 3 reads below were previously at script
  # start (pre-fix) and frozen there for the lifetime of the --loop process,
  # so the gh queries (query_assigned_issues, query_pr_mentions,
  # query_pr_merged, query_pr_labeled, query_board_changes) kept returning
  # historical events with old `updatedAt`.
  LAST_SEEN="$("$STATE_HELPER" get "$ROLE" last_seen_utc)"
  init_pr_merged_hwm
  init_pr_labeled_hwm

  local assigned reviews commits mentions verdict_posted stale stale_verdict missing_expectation board pr_merged pr_labeled issue_mentions periodic_scan
  assigned="$(query_assigned_issues || echo '[]')"
  reviews="$(query_review_requests || echo '[]')"
  commits="$(query_new_commits_on_assigned_prs || echo '[]')"
  mentions="$(query_pr_mentions 2>/dev/null || echo '[]')"
  # v8 (ADR-0041 / Issue #326): PR-comment verdict detection without
  # @-mention requirement. Closes the RCA gap from Issue #312 (PR #307
  # idled ~2h on a 🟢 APPROVED comment that lacked @developer).
  verdict_posted="$(query_verdict_posted 2>/dev/null || echo '[]')"
  # v6 (ADR-0024) shim dispatch: emit `stale_cc` only during the shim window
  # (now < VERDICT_SHIM_END) or when VERDICT_LEGACY_STALE_CC=true (rollback).
  # After 2026-07-02 by default, `query_stale_cc` is a no-op — the new
  # `stale_verdict` + `missing_expectation` queries carry the watchdog load.
  local now_epoch_shim shim_end_epoch
  now_epoch_shim="$(date -u +%s)"
  shim_end_epoch="$(date -u -d "$VERDICT_SHIM_END" +%s 2>/dev/null || echo 9999999999)"
  if [ "$now_epoch_shim" -lt "$shim_end_epoch" ] || [ "$VERDICT_LEGACY_STALE_CC" = "true" ]; then
    stale="$(query_stale_cc 2>/dev/null || echo '[]')"
  else
    stale='[]'
  fi
  stale_verdict="$(query_stale_verdict 2>/dev/null || echo '[]')"
  missing_expectation="$(query_missing_expectation 2>/dev/null || echo '[]')"
  board="$(query_board_changes || echo '[]')"
  pr_merged="$(query_pr_merged 2>/dev/null || echo '[]')"
  pr_labeled="$(query_pr_labeled 2>/dev/null || echo '[]')"
  # v4 (ADR-0017):
  issue_mentions="$(query_issue_mentions 2>/dev/null || echo '[]')"
  periodic_scan="$(query_periodic_backlog_scan 2>/dev/null || echo '[]')"
  # v5 (Issue #44 — Proactive Board Scan):
  # Issue #201: capture stderr to a log file instead of swallowing it.
  # Failure path (REPO missing, jq parse error, gh API error mid-detection)
  # must remain visible to post-mortem, while the success path stays silent.
  # XDG-cache-honoring: $PROACTIVE_SWEEP_LOG overrides; default lives under
  # $XDG_CACHE_HOME/dev-studio/agent-watch/ with $HOME/.cache fallback.
  # Shell-scope var (not `local`) because `$(...)` subshell needs read access
  # for the redirect; local vars don't leak into command substitutions.
  PROACTIVE_SWEEP_LOG="${PROACTIVE_SWEEP_LOG:-${XDG_CACHE_HOME:-$HOME/.cache}/dev-studio/agent-watch/proactive-sweep-errors.log}"
  mkdir -p "$(dirname "$PROACTIVE_SWEEP_LOG")" 2>/dev/null || true
  # Truncate on each call (AC: "no unbounded growth")
  : > "$PROACTIVE_SWEEP_LOG" 2>/dev/null || true
  proactive_sweep="$(query_proactive_sweep 2>"$PROACTIVE_SWEEP_LOG" || echo '[]')"
  # v6.1 (Issue #113 — Issue assigneeship authority + actionability signal):
  assigned_any="$(query_assigned_issues_any_status 2>/dev/null || echo '[]')"

  # v6.2 (Issue #119 — Dev-Idle Prevention, Katman 1): emit `wake_nudge` when
  # the agent has open work (`agent:<role>` or `cc:<role>` label on open issues)
  # but `new_events` is otherwise empty. Without this, an idle session sees
  # zero events and concludes "no work" — but the queue may have unresolved
  # issues. The nudge makes the queue visible to one-shot polls.

  # ADR-0039 (Issue #291 — WIP-idle watchdog, Sprint 6 P1): orchestrator-only
  # integration. When ROLE=orchestrator, call scripts/wip-idle-detect.sh to scan
  # all 5 roles for `WIP > 0 + no activity 30m`. Emit a `wip_idle` event per
  # idle role with the 3 in-scope signals (PR draft, comment, commit) + signal
  # 5 PR-in-review edge case. The orchestrator's poll loop surfaces this to
  # auto-ping the idle role via notify.sh. Wave coalesce (≥3 idle in 5-min) is
  # handled here: if ≥3 roles report idle, emit one `wip_idle_wave` event
  # instead of N individual `wip_idle` events (per arch 🟡 #2 on #289).
  local wip_idle='[]'
  if [ "$ROLE" = "orchestrator" ]; then
    local wip_detect_sh="$SCRIPT_DIR/wip-idle-detect.sh"
    if [ -x "$wip_detect_sh" ]; then
      local idle_json idle_total
      idle_json="$(bash "$wip_detect_sh" 2>/dev/null || echo '[]')"
      idle_total="$(echo "$idle_json" | jq 'length' 2>/dev/null || echo 0)"
      if [ "$idle_total" -ge 3 ]; then
        # Wave coalesce (arch 🟡 #2): ≥3 idle roles = single wave event
        local bucket
        bucket=$(( $(date -u +%s) / 300 ))
        wip_idle="$(echo "$idle_json" | jq --arg now "$now" --argjson bucket "$bucket" '
          [ {
            id: ("wip-idle-wave-b" + ($bucket | tostring)),
            kind: "wip_idle_wave",
            number: 0,
            title: ("idle wave: " + ([.[].role] | join(","))),
            url: "",
            updated_at: $now,
            context: { idle_count: ([.[].role] | length), roles: [.[].role] }
          } ]')"
      else
        # Per-role idle events
        wip_idle="$(echo "$idle_json" | jq --arg now "$now" '
          [ .[] | {
              id: ("wip-idle-" + .role + "-" + ([.issues[].issue | tostring] | join("-"))),
              kind: "wip_idle",
              number: (.issues[0].issue // 0),
              title: ("WIP-idle: " + .role + " (" + (.wip_count | tostring) + " issues, " + ([.issues[].age_min] | max | tostring) + "m max age)"),
              url: "",
              updated_at: $now,
              context: { role: .role, wip_count: .wip_count, issues: .issues }
            }
          ]')"
      fi
    fi
  fi
  local wake_nudge='[]'
  if [ -n "${REPO:-}" ]; then
    local queue_open cc_open
    # REST API (GraphQL rate-limit safe, Issue #238 emergency fix 2026-06-22)
    queue_open="$(gh api "repos/${REPO}/issues?state=open&labels=agent:${ROLE}&per_page=100" --jq 'length' 2>/dev/null || echo 0)"
    cc_open="$(gh api "repos/${REPO}/issues?state=open&labels=cc:${ROLE}&per_page=100" --jq 'length' 2>/dev/null || echo 0)"
    # Heartbeat-missed check (Issue #238 sub-task 2, PR #245): fire wake_nudge
    # if the synthetic is_alive heartbeat is older than 3x IS_ALIVE_INTERVAL_SEC
    # (hysteresis flag threshold per Issue #707 Option C).
    # Watchdog for the "watcher itself stuck" class — even when the queue is
    # empty, the synthetic heartbeat must remain fresh. Catches architect +
    # tester silenced at 2026-06-22T06:46Z RCA (per-poll heartbeat up to date
    # but gh api rate-limited → no events → self-pause).
    # Issue #707 Option C hysteresis (two-tier per arch cmt 4866463275 9-Lens (e)
    # idempotency pre-empt): >2x interval → log.warn tier (observability, no flag);
    # >3x interval → flag heartbeat_missed=true (real-miss escalation). Eliminates
    # the false-positive wake_nudge noise observed when poll cadence = 2x
    # IS_ALIVE_INTERVAL_SEC (deliberate API-load reduction per ADR-0002).
    # Sister-pattern: TD-016/020/037 false-positive class + ADR-0056 silent-skip
    # observability (log.warn preserved at >2x tier).
    local heartbeat_missed=false
    if [ -n "$last_is_alive_utc" ] && [ "$last_is_alive_utc" != "null" ] && [ "$last_is_alive_epoch" -gt 0 ]; then
      local heartbeat_gap="$(( now_epoch - last_is_alive_epoch ))"
      if [ "$heartbeat_gap" -gt "$(( is_alive_interval * 3 ))" ]; then
        heartbeat_missed=true
      elif [ "$heartbeat_gap" -gt "$(( is_alive_interval * 2 ))" ]; then
        # Hysteresis pre-warn tier (ADR-0056 silent-skip sister — observability
        # without false-positive flag). 9-Lens (e) idempotency per arch cmt 4866463275.
        printf '%s [WARN] agent-watch.sh: heartbeat gap >2x IS_ALIVE_INTERVAL_SEC but <=3x (hysteresis pre-warn; gap=%ss / interval=%ss); flag NOT triggered per Issue #707 Option C\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$heartbeat_gap" "$is_alive_interval" >&2
      fi
    fi
    if [ "$((queue_open + cc_open))" -gt 0 ] || [ "$heartbeat_missed" = "true" ]; then
      local wake_note
      if [ "$heartbeat_missed" = "true" ]; then
        wake_note="watcher heartbeat missed (>3x IS_ALIVE_INTERVAL_SEC, hysteresis threshold per Issue #707); queue may be empty or stuck"
      else
        wake_note="no-new-events but queue non-empty (Katman 1)"
      fi
      wake_nudge="$(jq -n \
        --arg role "$ROLE" \
        --arg now "$now" \
        --arg repo "$REPO" \
        --argjson queue "$queue_open" \
        --argjson cc "$cc_open" \
        --argjson hb_missed "$([ "$heartbeat_missed" = "true" ] && echo true || echo false)" \
        --arg note "$wake_note" \
        '[
           {
             kind: "wake_nudge",
             id: ("wake-nudge-" + $role + "-" + $now),
             number: 0,
             title: ("queue: agent:" + $role + "=" + ($queue|tostring) + ", cc:" + $role + "=" + ($cc|tostring) + " open issues"),
             url: ("https://github.com/" + $repo + "/issues?q=is%3Aopen+label%3Aagent%3A" + $role),
             updated_at: $now,
             context: {agent_count: $queue, cc_count: $cc, heartbeat_missed: $hb_missed, note: $note}
           }
         ]')"
    fi
  fi

  # Merge and dedupe
  local merged
  merged="$(jq -s 'add | unique_by(.id)' \
    <(echo "$assigned") <(echo "$reviews") <(echo "$commits") \
    <(echo "$mentions") <(echo "$verdict_posted") \
    <(echo "$stale") <(echo "$stale_verdict") \
    <(echo "$missing_expectation") <(echo "$board") \
    <(echo "$pr_merged") <(echo "$pr_labeled") \
    <(echo "$issue_mentions") <(echo "$periodic_scan") \
    <(echo "$proactive_sweep") <(echo "$assigned_any") \
    <(echo "$is_alive_event") <(echo "$wip_idle") \
    2>/dev/null || echo '[]')"

  # Filter out events already in processed_event_ids
  local state_file new_events
  state_file="$("$STATE_HELPER" path "$ROLE")"
  # TD-068 Fix 4 (Issue #920): null guard + self-heal on processed_event_ids.
  # Without this, when processed_event_ids is null (e.g., from external JSON
  # merge or cross-session state-file corruption), the jq filter below runs
  # `index($id)` against null → "Cannot index null with null" error → watcher
  # exits silently, autonomy loop dies without surfacing ALERT. Sister-pattern
  # to d027-state-recovery (cmd_rebuild on jq parse error) + d068 d-test TC4.
  # Race mitigation (per design Risk #4): exclusive flock around the write;
  # if held by another process, retry next poll cycle (flock is blocking here
  # because self-heal is rare; the cmd_mark flock at line 215 uses blocking too).
  if jq -e '.processed_event_ids | type == "null"' "$state_file" >/dev/null 2>&1; then
    echo "ALERT: $state_file processed_event_ids is null — auto-healing to []" >&2
    # TD-068 observability (Issue #925): structured JSON Lines for downstream
    # tooling / production telemetry (arch 9-Lens lens f). Plain-text line
    # above is the human-readable fallback (AC4); the JSON line below is the
    # machine-readable contract (AC3 schema).
    jq -nc \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg role "${ROLE:-watcher}" \
      --arg event "watcher_self_heal" \
      --arg reason "processed_event_ids_null" \
      --arg fallback_action "write_empty_array" \
      --arg state_file "$state_file" \
      '{ts:$ts, role:$role, event:$event, reason:$reason, fallback_action:$fallback_action, state_file:$state_file}' >&2
    (
      flock 9
      jq '.processed_event_ids = []' "$state_file" > "${state_file}.tmp"
      sync "${state_file}.tmp" 2>/dev/null || true
      mv -f "${state_file}.tmp" "$state_file"
    ) 9>"${state_file}.lock"
  fi
  # TD-068 Fix 4 (sub-fix TD-068B): defensive jq filter — `// []` fallback
  # covers any race where processed_event_ids gets nulled between the guard
  # above and the read here. Without `// []`, a null pid would crash the filter.
  new_events="$(jq -n \
    --slurpfile state "$state_file" \
    --argjson events "$merged" '
    [ $events[] | . as $e | ($state[0].processed_event_ids // []) as $pids |
      select(($pids | index($e.id)) == null) ]
  ')"

  # Emit
  jq -n \
    --arg role "$ROLE" \
    --arg now "$now" \
    --argjson events "$new_events" \
    --argjson next "$POLL_INTERVAL" \
    --argjson nudge "$wake_nudge" \
    '{
       role: $role,
       polled_at_utc: $now,
       new_events: $events,
       wake_nudge: $nudge,
       next_poll_sec: $next
     }'

  # Bump last_seen
  "$STATE_HELPER" set "$ROLE" last_seen_utc "\"$now\""

  # v3.1.1 (ADR-0008): HWM bump now lives inside query_pr_merged because the
  # subshell `$(query_pr_merged)` capture above drops any globals set by the
  # callee. The role still advances pr_merged_last_seen_utc on every poll even
  # when label rules filtered every PR out for this role.

  # Auto-mark events as processed (the agent can also call mark explicitly)
  # Fix 1 (Issue #345 P0): atomic batch mark — replaces N per-event jq_inplace
  # round-trips with a single jq edit. Eliminates:
  #   - N filesystem round-trips (was O(N) file writes per poll)
  #   - per-event race window (was: each mark could be lost between mark + trim)
  #   - Bug 3 char-iteration (was: `jq -r '.[].id'` on a string iterated chars)
  # The batch handles BOTH array and string inputs gracefully — if a query
  # somehow returned a string (not an array), the whole string becomes 1
  # array entry instead of N character entries.
  local new_ids_json
  new_ids_json="$(echo "$new_events" | jq -c '
    if type == "array" then [.[] | .id] else [.] end | map(select(. != null and . != ""))
  ')"
  if [ "$(echo "$new_ids_json" | jq 'length')" -gt 0 ]; then
    local state_file_mark
    state_file_mark="$("$STATE_HELPER" path "$ROLE")"
    local lock_mark="${state_file_mark}.lock"
    (
      if flock -n 9; then
        # Fix 1b (P0 #345 follow-up): inline jq + mktemp + sync + mv pattern
        # (matches atomic_write_json's atomicity guarantee). The previous
        # attempt called `jq_inplace`, which is a function defined in
        # agent-state.sh — but agent-watch.sh runs agent-state.sh as a
        # separate process via $STATE_HELPER, so the function is NOT in
        # scope here. Result was silent "command not found" + the ring
        # never advanced. Same pattern as the TTL prune at L1374-1394.
        local tmp_mark
        tmp_mark="$(mktemp "${state_file_mark}.atomic.XXXXXX")"
        if jq --argjson ids "$new_ids_json" --arg now "$now" '
          .processed_event_ids as $existing |
          .processed_event_ids = ($existing + ($ids - $existing)) |
          .last_seen_utc = $now
        ' "$state_file_mark" > "$tmp_mark" 2>/dev/null; then
          sync "$tmp_mark" 2>/dev/null || true
          mv -f "$tmp_mark" "$state_file_mark"
        else
          rm -f "$tmp_mark" 2>/dev/null || true
          log "WARN" "batch mark jq filter failed for $ROLE"
        fi
      else
        log "WARN" "batch mark skipped for $ROLE (lock held by another writer)"
      fi
    ) 9>"$lock_mark"
  fi

  # Trim processed_event_ids to keep state file bounded.
  # Fix 3 (Issue #345 P0): align trim cap with agent-state.sh:48 default
  # (200, not 50). Larger ring = more dedup headroom during burst activity;
  # the watcher was trimming to 50 BEFORE the atomic batch mark could land,
  # losing any race-window additions.
  # ADR-0032 RCA-32: pass 288 (24h × 12 buckets/h) as 3rd arg so cmd_trim also
  # applies the TTL filter (defense in depth on top of the prune block above).
  "$STATE_HELPER" trim "$ROLE" "${AGENT_PROCESSED_MAX:-200}" 288 >/dev/null 2>&1 || true

  # Wake the tmux pane if events arrived OR wake_nudge present and wake mode is on.
  # v6.2 (Issue #119 — Dev-Idle Prevention, Katman 2): wake on nudge too, not
  # only on new_events. Combined payload (events + nudges) gives full context.
  if [ "$WAKE_PANE" = "1" ]; then
    local wake_payload
    wake_payload="$(jq -n --argjson e "$new_events" --argjson n "$wake_nudge" '$e + $n')"
    wake_pane_for_role "$ROLE" "$wake_payload" || true
  fi

  # v8 (Issue #271 / ADR-0038 §Layer 2): Auto-Claim Protocol hook.
  # After events processed + pane wake, call claim-next-ready.sh. Exit codes:
  #   0 = claimed (re-poll to surface the new status:in-progress event)
  #   1 = nothing to claim (no ready items or all blocked by open deps)
  #   3 = WIP limit reached
  #   4 = gh API error
  # Re-poll on exit 0 is critical: the claim changes a status label, which
  # produces a fresh `label_change` event. If we don't re-poll, the agent
  # sleeps for POLL_INTERVAL seconds before noticing its own action. The
  # soul patch (Layer 1) explicitly says "AFTER events processed, BEFORE
  # going back to sleep" — re-poll is the "AFTER claim processed" continuation.
  # Kill switch: CLAIM_NEXT_READY_ENABLED=false bypasses the entire hook.
  if [ "${CLAIM_NEXT_READY_ENABLED:-true}" = "true" ]; then
    local claim_script="$SCRIPT_DIR/claim-next-ready.sh"
    if [ -x "$claim_script" ]; then
      local claim_rc=0
      bash "$claim_script" "$ROLE" >/dev/null 2>&1 || claim_rc=$?
      if [ "$claim_rc" = "0" ]; then
        # Claim succeeded — re-poll so the watcher sees the new in-progress
        # event in the next cycle (per ADR-0038 §sequence diagram step 11).
        poll_once
      fi
    fi
  fi
}

case "$MODE" in
  --once)
    poll_once
    ;;
  --loop)
    while true; do
      poll_once
      sleep "$POLL_INTERVAL"
    done
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    exit 2
    ;;
esac
