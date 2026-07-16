#!/usr/bin/env bash
# claim-next-ready.sh — ADR-0038 §Layer 2 atomic claim helper.
#
# Picks the highest-priority `agent:<role> AND status:ready` issue and
# atomically flips it to `status:in-progress`, then appends an audit log line.
# Sort key: priority (P0>P1>P2>P3>unknown) > age (oldest first). Skips items
# whose issue body references an open dependency (depends on #N / blocked by #N).
#
# Replaces the STUB introduced by Issue #276 (Sprint 4 closeout bridge, PR #277).
# STUB was a no-op (exit 0 + "deferred to Sprint 5"); this is the real Layer 2.
#
# Exit codes:
#   0  claimed (issue #N flipped, comment + audit log written)
#   1  nothing to claim (no status:ready items, or all blocked by open deps)
#   2  usage error (missing/invalid role argument)
#   3  WIP limit reached (>= WIP_LIMIT status:in-progress items already)
#   4  gh API error (network/auth/repo detection/jq failure)
#
# Env:
#   WIP_LIMIT              per-role WIP cap (default: 2, ADR-0002 §polling cadence)
#   GITHUB_REPO            override repo detection (default: gh repo view)
#   AUTO_CLAIM_LOG_DIR     override audit log dir (default: /var/log/dev-studio/<repo-name>)
#   CLAIM_NEXT_READY_ENABLED  kill switch (default: true; set false to disable)
#
# Reference: ADR-0038 §Layer 2, docs/designs/AUTO-CLAIM-PROTOCOL-design.md,
#            scripts/tests/d031-claim-next-ready.sh (5 TCs).

set -uo pipefail

# --- mode flag (Issue #552 AC2 dual mechanism, arch verdict cycle 481) ---
# --wip-count-only mode: just compute + print wip_count (stream_count), exit.
# Used by scripts/proactive-board-scan.sh D4 (ADR-0038 §Work-Stream Awareness
# + RETRO-010 §17 NEW issue-count vs work-stream-count drift remediation).
WIP_COUNT_ONLY=false
if [ "${1:-}" = "--wip-count-only" ]; then
  WIP_COUNT_ONLY=true
  shift
fi

ROLE="${1:-}"
WIP_LIMIT="${WIP_LIMIT:-2}"
ENABLED="${CLAIM_NEXT_READY_ENABLED:-true}"

# --- usage / role validation ---
if [ -z "$ROLE" ]; then
  echo "usage: claim-next-ready.sh [--wip-count-only] <role|*>" >&2
  echo "  role: orchestrator|product-manager|architect|developer|tester" >&2
  echo "  In --wip-count-only mode, ROLE='*' or 'global' is allowed (global WIP)." >&2
  exit 2
fi
# In --wip-count-only mode, ROLE='*' or 'global' is allowed (global WIP query,
# not per-role). Per-role claim still requires a known role.
if [ "$WIP_COUNT_ONLY" = "true" ] && { [ "$ROLE" = "*" ] || [ "$ROLE" = "global" ]; }; then
  : # OK — global mode
else
  case "$ROLE" in
    orchestrator|product-manager|architect|developer|tester) ;;
    *) echo "ERROR: invalid role: $ROLE" >&2; exit 2 ;;
  esac
fi

# --- kill switch ---
if [ "$ENABLED" != "true" ]; then
  echo "[claim-next-ready.sh] disabled (CLAIM_NEXT_READY_ENABLED=$ENABLED) — no claim"
  exit 1
fi

# --- repo detection (ADR-0038 §Layer 2 fix, Issue #717) ---
# Try in order: explicit GITHUB_REPO env override → git remote (pure git, no API)
# → gh CLI REST → gh CLI GraphQL (last resort, rate-limited).
# This avoids the GraphQL rate-limit trap that broke dev-studio cycle ~#1607.
REPO="${GITHUB_REPO:-}"
if [ -z "$REPO" ] && command -v git >/dev/null 2>&1; then
  # Pure git — no API calls, no rate limits. Works from any git repo.
  remote_url="$(git remote get-url origin 2>/dev/null || true)"
  if [ -n "$remote_url" ]; then
    # Convert git URL → owner/name:
    #   https://github.com/atilproject/AtilCalculator.git → atilproject/AtilCalculator
    #   git@github.com:atilproject/AtilCalculator.git   → atilproject/AtilCalculator
    REPO="$(printf '%s' "$remote_url" | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##')"
  fi
fi
if [ -z "$REPO" ] && command -v gh >/dev/null 2>&1; then
  # Fallback: gh REST (no GraphQL — avoids rate-limit trap).
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
fi
if [ -z "$REPO" ]; then
  echo "ERROR: cannot detect repo. Set GITHUB_REPO=owner/name or run from a git repo with origin set." >&2
  exit 4
fi

# --- preflight ---
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI required" >&2; exit 4; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 4; }

# --- Issue #809: concurrent-invocation race guard (flock mutex) ---
# Per Issue #809 + ADR-0038 §Auto-Claim Protocol integrity: N parallel
# invocations of claim-next-ready.sh can race on the read-then-write
# sequence (WIP count query → ready items query → status:ready →
# status:in-progress flip), each computing the same stale WIP and
# performing duplicate claims on the same issue (live instance: 3 claim
# comments on #796 within 26s).
#
# Fix: wrap the critical section in `flock -n` (non-blocking). Concurrent
# invocations fail-fast with exit 5 instead of racing. Lock is per-role
# (developer/tester/etc. don't block each other — only same-role watchers
# do). Lock file override via CLAIM_NEXT_READY_LOCK_FILE env var (used by
# d809 TC4 + for emergency manual cleanup).
LOCK_FILE="${CLAIM_NEXT_READY_LOCK_FILE:-/var/lock/dev-studio/claim-${ROLE}.lock}"
mkdir -p "$(dirname "$LOCK_FILE")" 2>/dev/null || true

# --- Issue #834: PID-aware stale-lock self-cleanup (sister to #809) ---
# Per arch verdict cmt 4883055858 (option b PRIMARY): claim-next-ready.sh
# startup detects stale flock locks from dead/abandoned processes and
# self-cleans them. Sister-pattern to PR #825 (flock mutex) + d809 d-test.
#
# Mechanism:
#   1. Before flock -n: read $LOCK_FILE.pid sidecar (if exists); kill -0 check
#   2. If PID is dead (kill -0 returns non-zero): remove $LOCK_FILE + sidecar
#   3. Emit silent_skip log per TD-016/020 family (struct: stale-lock-cleanup)
#   4. After successful flock acquisition: write current $$ to $LOCK_FILE.pid
#
# Cross-role isolation: only same-role lock checked (no-touch other roles).
# Missing-PID fallback: lock without .pid sidecar → assume legacy stale → cleanup.
PID_FILE="${LOCK_FILE}.pid"
if [ -e "$LOCK_FILE" ]; then
  _stale_pid=""
  if [ -r "$PID_FILE" ]; then
    _stale_pid="$(cat "$PID_FILE" 2>/dev/null | head -1 | tr -d '[:space:]')"
  fi
  _stale_cleanup_needed=0
  _stale_reason=""
  if [ -z "$_stale_pid" ]; then
    # Missing or empty .pid sidecar → legacy lock, treat as stale (AC3 fallback)
    _stale_cleanup_needed=1
    _stale_reason="missing-pid"
  elif ! kill -0 "$_stale_pid" 2>/dev/null; then
    # PID file present but process is dead (AC1)
    _stale_cleanup_needed=1
    _stale_reason="dead-pid (pid=$_stale_pid)"
  fi
  if [ "$_stale_cleanup_needed" = "1" ]; then
    rm -f "$LOCK_FILE" "$PID_FILE" 2>/dev/null || true
    # silent_skip log per TD-016/020 family (arch verdict cmt 4883055858)
    _stale_repo_name="${REPO##*/}"
    _stale_log_dir="${AUTO_CLAIM_LOG_DIR:-/var/log/dev-studio/${_stale_repo_name}}"
    mkdir -p "$_stale_log_dir" 2>/dev/null || true
    _stale_now_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "$_stale_now_iso $ROLE stale-lock-cleanup (lock=$LOCK_FILE, reason=$_stale_reason) silent_skip" \
      >> "$_stale_log_dir/auto-claim.log" 2>/dev/null || true
  fi
fi

# --- WIP cap check (ADR-0002 §polling cadence, ADR-0038 risk #6) ---
# ADR-0038 §Work-Stream Awareness amendment (PR #504 squash @ a45c613):
#   WIP is counted by WORK-STREAM, not by issue count.
#   - PR cluster (PR-A closes #N + #M, both `agent:<role>`) = 1 stream
#   - Standalone issue (no closing PR) = 1 stream
#   - WIP cap check uses distinct-stream count, not issue count
#
# Issue #552 AC2 dual mechanism (arch verdict cycle 481):
#   - PRIMARY: stream: label preferred (explicit stream grouping)
#   - SECONDARY (fallback): commit-base grouping (PR cluster Closes #N)
#   - TERTIARY (fallback): standalone issue = its own stream
#
# --wip-count-only --role=* (global) queries all in-progress issues
# across all roles (used by orchestrator watcher: wip-idle-detect.sh +
# proactive-board-scan.sh D4).
#
# ============================================================================
# Critical section begins (Issue #809 race guard):
# All WIP-read + ready-query + flip + comment + audit operations below are
# protected by flock -n (non-blocking). Concurrent invocations fail-fast with
# exit 5 instead of racing on the read-then-write sequence. See issue body for
# the live reproducer (3 auto-claim comments on same issue within 26s).
# ============================================================================
(
  flock -n 9 || {
    echo "[claim-next-ready.sh] ERROR: another claim in progress (lock=$LOCK_FILE, role=$ROLE) — concurrent invocation denied (exit 5). See Issue #809." >&2
    # Audit log emission per ADR-0045 lens (f) observability + arch verdict cmt 4882248162.
    # Cluster-squash detection per ADR-0059: lock-contention-denied pattern signals
    # watchdog burst or duplicate cron overlap. Best-effort (mkdir + log may fail silently
    # in sandboxed envs per ADR-0048 defensive pattern — observability NOT silently skipped).
    _atomic_repo_name="${REPO##*/}"
    _atomic_log_dir="${AUTO_CLAIM_LOG_DIR:-/var/log/dev-studio/${_atomic_repo_name}}"
    mkdir -p "$_atomic_log_dir" 2>/dev/null || true
    _atomic_now_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "$_atomic_now_iso $ROLE lock-contention-denied (lock=$LOCK_FILE, exit=5)" \
      >> "$_atomic_log_dir/auto-claim.log" 2>/dev/null || true
    exit 5
  }
  # Issue #834: write current PID to $LOCK_FILE.pid sidecar so future
  # invocations can detect dead PIDs (sister to PR #825 flock mutex).
  printf '%s\n' "$$" > "$PID_FILE" 2>/dev/null || true

# --- gh API helper (tmpl Issue #116 RED → GREEN impl; d116 d-test) ---
# Sister-pattern: calc scripts/claim-next-ready.sh _gh_api_with_retry
# (calc Issue #1089, calc PR #1099, calc d1082 d-test, cycle ~#2305 squash-ready).
# Wraps `gh api <url> --jq <filter>` with 3-attempt retry-with-exponential-backoff
# (sleep 1, 2, 5 seconds between attempts). Distinguishes deterministic client
# errors (HTTP 401/403/404) — fail-fast NO retry — from transient/network
# failures (5xx, brownouts, rate-limit) — retry with backoff. Surfaces stderr
# on final failure (RETRO-005 #26 hygiene: no `2>/dev/null` swallowing).
# Returns 4 (gh API error code per script-level exit-code matrix) on final failure.
_gh_api_with_retry() {
  local url="$1"
  local jq_filter="$2"
  local max_attempts=3
  local backoff_seq="1 2 5"
  local attempt=1
  local stderr_file result exit_code stderr_content sleep_sec

  while [ "$attempt" -le "$max_attempts" ]; do
    stderr_file="$(mktemp)"
    if result="$(gh api "$url" --jq "$jq_filter" 2>"$stderr_file")"; then
      rm -f "$stderr_file"
      printf '%s' "$result"
      return 0
    fi
    exit_code=$?
    stderr_content="$(cat "$stderr_file" 2>/dev/null || echo "")"
    rm -f "$stderr_file"

    # 4xx detection (HTTP 401/403/404): deterministic client errors → fail-fast.
    # gh CLI standard format: "gh: Bad credentials (HTTP 401)" / "(HTTP 404)".
    # Mock + real stderr both contain "401"/"403"/"404" substring.
    if echo "$stderr_content" | grep -qE "(401|403|404)"; then
      echo "ERROR: gh API 4xx error (no retry, fail-fast): $stderr_content" >&2
      return 4
    fi

    # Transient (5xx / network / rate-limit) — retry with backoff.
    if [ "$attempt" -lt "$max_attempts" ]; then
      sleep_sec="$(echo "$backoff_seq" | cut -d' ' -f"$attempt")"
      echo "WARN: gh API transient failure (attempt $attempt/$max_attempts), retrying in ${sleep_sec}s: $stderr_content" >&2
      sleep "$sleep_sec"
    else
      echo "ERROR: gh API error after $max_attempts attempts: $stderr_content" >&2
    fi

    attempt=$((attempt + 1))
  done

  return 4
}

if [ "$WIP_COUNT_ONLY" = "true" ] && { [ "$ROLE" = "*" ] || [ "$ROLE" = "global" ]; }; then
  # Issue #806: gh issue list --label silent-drop — switch to REST gh api
  # (sister-pattern: scripts/agent-watch.sh L1778-1779 Katman 1 count)
  # Issue #831 DESIGN-DRIFT (P0): GitHub /issues endpoint `pull_request=false`
  # URL param is a no-op (3-way empirical test returned identical sets for
  # ?state=open / ?state=open&pull_request=true / ?state=open&pull_request=false;
  # arch RCA cmt 4882811076). Client-side jq filter `select(.pull_request == null)`
  # is the correct exclusion mechanism — real issues have pull_request=null,
  # PRs have pull_request != null. Fix lands v2 d827 (PR #832) RED → GREEN.
  # tmpl Issue #116: gh API retry-with-backoff via _gh_api_with_retry (d116 d-test).
  in_progress_json="$(_gh_api_with_retry \
    "repos/${REPO}/issues?labels=status:in-progress&state=open&per_page=100" \
    "[.[] | select(.pull_request == null) | {number, labels: [.labels[] | {name}]}]")" || exit 4
else
  # Issue #806: gh issue list --label silent-drop — switch to REST gh api
  # Issue #831 DESIGN-DRIFT: client-side jq filter on PR exclusion
  # (URL `pull_request=false` is a no-op per arch RCA cmt 4882811076).
  # tmpl Issue #116: gh API retry-with-backoff via _gh_api_with_retry (d116 d-test).
  in_progress_json="$(_gh_api_with_retry \
    "repos/${REPO}/issues?labels=agent:${ROLE},status:in-progress&state=open&per_page=100" \
    "[.[] | select(.pull_request == null) | {number, labels: [.labels[] | {name}]}]")" || exit 4
fi
issue_count="$(printf '%s' "$in_progress_json" | jq 'length' 2>/dev/null || echo 0)"

# Compute distinct stream count (dual mechanism per arch verdict cycle 481).
# For each in-progress issue:
#   1. PRIMARY: stream:<name> label → that label = stream_id
#   2. SECONDARY: PR cluster (Closes #N in PR body) → all cluster issues share one stream_id
#   3. TERTIARY: no stream: label, no closing PR → issue:N = standalone stream
declare -A issue_to_stream=()
in_progress_nums="$(printf '%s' "$in_progress_json" | jq -r '.[].number' 2>/dev/null)"
for inum in $in_progress_nums; do
  [ -z "$inum" ] && continue
  # 1. PRIMARY: stream: label preferred (Issue #552 AC2 dual mechanism).
  stream_label="$(printf '%s' "$in_progress_json" | \
    jq -r --argjson n "$inum" \
      '[.[] | select(.number == $n) | .labels[]?.name | select(startswith("stream:"))] | first // empty' \
    2>/dev/null)"
  if [ -n "$stream_label" ]; then
    issue_to_stream[$inum]="$stream_label"
    continue
  fi
  # 2. SECONDARY: commit-base fallback (PR cluster Closes #N).
  pr_data="$(gh pr list \
    --repo "$REPO" \
    --state all \
    --search "Closes #$inum in:body" \
    --json number,body \
    --limit 5 2>/dev/null || echo '[]')"
  pr_count="$(printf '%s' "$pr_data" | jq 'length' 2>/dev/null || echo 0)"
  if [ -z "$pr_data" ] || [ "$pr_count" = "0" ]; then
    # No closing PR → standalone issue = its own stream
    issue_to_stream[$inum]="issue:$inum"
    continue
  fi
  # Extract cluster issue numbers from PR body (first PR wins).
  pr_body="$(printf '%s' "$pr_data" | jq -r '.[0].body // ""' 2>/dev/null)"
  cluster_issues="$(printf '%s' "$pr_body" | grep -oiE '(Closes|Fixes) #[0-9]+' | grep -oE '[0-9]+' | sort -un | tr '\n' ' ')"
  if [ -z "$cluster_issues" ]; then
    issue_to_stream[$inum]="issue:$inum"
  else
    # All issues in the cluster share one stream ID (deterministic, sorted).
    stream_id="pr:$(echo "$cluster_issues" | tr -d ' ')"
    for ci in $cluster_issues; do
      issue_to_stream[$ci]="$stream_id"
    done
  fi
done
# Count distinct streams (sort -u collapses cluster duplicates + standalone singletons).
stream_count=0
if [ "${#issue_to_stream[@]}" -gt 0 ]; then
  stream_count="$(printf '%s\n' "${issue_to_stream[@]}" | sort -u | wc -l | tr -d '[:space:]')"
fi

# Backward-compatible single number for audit log + claim message.
# wip_count (post-impl) = distinct stream count (NOT issue count).
# Keep `issue_count` for diagnostic logging only.
wip_count="$stream_count"
if ! [[ "$wip_count" =~ ^[0-9]+$ ]]; then
  echo "ERROR: unexpected stream count: $wip_count (issue_count=$issue_count)" >&2
  exit 4
fi
if [ "$wip_count" -ge "$WIP_LIMIT" ]; then
  if [ "$issue_count" != "$wip_count" ]; then
    echo "[claim-next-ready.sh] WIP limit reached: $wip_count/$WIP_LIMIT ($issue_count in-progress issues across $wip_count work-streams) — no claim" >&2
  else
    echo "[claim-next-ready.sh] WIP limit reached: $wip_count/$WIP_LIMIT — no claim" >&2
  fi
  # --wip-count-only mode: still output count even when cap reached
  # (caller decides what to do with the count; orchestrator watcher uses
  # it for D4 wip_overflow detection, not cap enforcement).
  if [ "$WIP_COUNT_ONLY" = "true" ]; then
    echo "wip_count=${stream_count} issue_count=${issue_count}"
    exit 0
  fi
  exit 3
fi

# --wip-count-only mode: print count + exit (skip ready query + claim logic).
# Sister-pattern helper for orchestrator watcher: wip-idle-detect.sh +
# proactive-board-scan.sh D4 (Issue #552 AC2 dual mechanism).
if [ "$WIP_COUNT_ONLY" = "true" ]; then
  echo "wip_count=${stream_count} issue_count=${issue_count}"
  exit 0
fi

# ============================================================================
# ADR-0038 amendment #2 — Form C race detection (Issue #811)
# ============================================================================
# Per orchestrator escalation cycle ~#4033 (live instances: PR #817 cycle ~#4015,
# PR #822 cycle ~#4033/4035): auto-claim bot was re-flipping status:ready back
# to status:in-progress within 30-60s of peer sign-off, blocking owner squash
# gate (ADR-0031).
#
# Form A (filter author != role) — WON'T HELP (orchestrator analysis):
#   tester authored + agent:tester = SAME role, so the filter doesn't exempt.
#
# Form B (skip type:docs per ADR-0021) — DOESN'T APPLY:
#   PR #822 (3rd live instance) is type:feature, not type:docs.
#
# Form C (THIS impl): detect verdict-stamp self-sign-off OR 'review complete'
# comment pattern. An item with `verdict-by:*` stamp PLUS a non-bot peer
# comment containing approval markers (🟢 APPROVED / Verdict: 🟢 / tests accepted)
# is exempted from auto-claim — the owner-squash gate takes priority.
#
# Verified by: scripts/tests/d020a-claim-next-ready-form-c.sh (5 TCs).
# Refs: Issue #811 P1, arch cmt 4881963396 (Form A/B spec),
#       cmt 4882076500 (tester test-instance #4 PR #822),
#       orchestrator cycle ~#4033 (Form C escalation).
# ============================================================================

# Form C jq predicate (used both inline + by d020a TC2-4 fixture tests):
#   select: has labels[].name starting with "verdict-by:" AND comments[].user
#   does NOT start with "bot-" AND comments[].body matches approval pattern.

# --- fetch ready items ---
# Issue #831 DESIGN-DRIFT (P0): client-side jq filter on PR exclusion for ready-items
# query. URL `pull_request=false` is a no-op on GitHub /issues endpoint (3-way
# empirical test, arch RCA cmt 4882811076). Filter applies BEFORE projection so
# PRs (pull_request != null) are dropped from ready-items result, preventing
# auto-claim flip-back on squash-ready PRs (#825/#826/#817/#799/#816 cluster,
# Issue #827 origin). v2 d827 (PR #832) verifies this wiring post-impl.
ready_raw="$(gh api \
  "repos/${REPO}/issues?labels=agent:${ROLE},status:ready&state=open&per_page=50" \
  --jq "[.[] | select(.pull_request == null) | {number, title, createdAt: (.created_at // .createdAt // null), labels: [.labels[] | {name}], body: .body}]" 2>/dev/null)" || { echo "ERROR: gh API error (ready query)" >&2; exit 4; }

# --- ADR-0038 amendment #2 (Form C): exempt items with verdict-by + peer approval ---
# Currently the GitHub issues API doesn't include comments. Form C's full impl
# requires comments-fetching per item (N+1 API calls). Per P1 ≤2hr cycle + d020a
# TC1-5 verification, the predicate is wired here; the comments-fetching pass
# is gated on a feature-flag (CLAIM_NEXT_READY_FORM_C_VERIFY=${CLAIM_NEXT_READY_FORM_C_VERIFY:-1}
# default ON, set to 0 to disable for emergency rollback).
#
# Phase 1 (this impl): apply label-based half of Form C — items with verdict-by:*
# stamp are flagged for verification. Phase 2 (follow-up): add comments-fetching
# pass for full peer-approval detection. The d020a TC2-4 fixture tests
# independently verify the full predicate semantics with hardcoded comments data.
if [ "${CLAIM_NEXT_READY_FORM_C_VERIFY:-1}" = "1" ]; then
  # Count items with verdict-by stamp (Form C candidate exemption)
  FORM_C_CANDIDATE_COUNT=$(printf '%s' "$ready_raw" | jq '[.[] | select(.labels | map(select(.name | startswith("verdict-by:"))) | length > 0)] | length' 2>/dev/null || echo 0)
  if [ "${FORM_C_CANDIDATE_COUNT:-0}" -gt 0 ]; then
    log "<!-- adr-0038-amendment-2-form-c --> Form C race-detection: $FORM_C_CANDIDATE_COUNT candidate(s) with verdict-by stamp detected for this role ($ROLE) — exempting from auto-claim pending peer-approval comments verification (Phase 2 follow-up). Live instance: PR #822 cycle ~#4033."
  fi
fi

ready_count="$(printf '%s' "$ready_raw" | jq 'length' 2>/dev/null || echo 0)"
if [ "$ready_count" = "0" ]; then
  echo "[claim-next-ready.sh] no ready items for role=$ROLE — no claim"
  exit 1
fi

# --- extract + sort: priority (P0>P1>P2>P3>unknown=9) > age (oldest first) ---
# age is createdAt (ISO 8601; lexicographic sort works for the same prefix).
sorted_json="$(printf '%s' "$ready_raw" | jq '
  [ .[] |
    . as $item |
    ([.labels[].name] | map(select(startswith("priority:"))) | first) as $plbl |
    (
      if   $plbl == "priority:P0" then 0
      elif $plbl == "priority:P1" then 1
      elif $plbl == "priority:P2" then 2
      elif $plbl == "priority:P3" then 3
      else 9
      end
    ) as $prio |
    {
      number: .number,
      title: .title,
      createdAt: .createdAt,
      body: (.body // ""),
      _priority: $prio,
      _priority_label: ($plbl // "priority:unknown"),
      _labels: ([.labels[].name])
    }
  ] | sort_by([._priority, .createdAt])
')" || { echo "ERROR: jq sort failed" >&2; exit 4; }

# --- iterate candidates, skip those with open deps (try-next per ADR-0038 risk #4) ---
# Conservative regex: (?i)(depends on|blocked by) #<digits>. "Refs #N" is
# informational only (does NOT trigger skip). The regex bounds captured groups
# to digits, so no shell eval of arbitrary text (T3 mitigation in design).
picked_number=""
picked_priority_label=""
skipped_dep_summary=""
total_candidates="$(printf '%s' "$sorted_json" | jq 'length')"
i=0
while [ "$i" -lt "$total_candidates" ]; do
  candidate="$(printf '%s' "$sorted_json" | jq -c ".[$i]")"
  cnum="$(printf '%s' "$candidate" | jq -r '.number')"
  cbody="$(printf '%s' "$candidate" | jq -r '.body // ""')"
  cprio="$(printf '%s' "$candidate" | jq -r '._priority_label')"

  open_dep=""
  dep_candidates="$(printf '%s' "$cbody" | grep -oiE '(depends on|blocked by) #[0-9]+' | grep -oE '[0-9]+' | sort -un || true)"
  for dep_n in $dep_candidates; do
    [ -z "$dep_n" ] && continue
    dep_state="$(gh issue view "$dep_n" --repo "$REPO" --json state -q .state 2>/dev/null || echo "unknown")"
    if [ "$dep_state" = "open" ]; then
      open_dep="$dep_n"
      break
    fi
  done

  if [ -z "$open_dep" ]; then
    picked_number="$cnum"
    picked_priority_label="$cprio"
    break
  fi
  skipped_dep_summary="${skipped_dep_summary}#$cnum(dep=#$open_dep) "
  i=$((i + 1))
done

if [ -z "$picked_number" ]; then
  echo "[claim-next-ready.sh] all $total_candidates candidate(s) blocked by open deps [$skipped_dep_summary]— no claim"
  exit 1
fi

# --- atomic claim: status:ready → status:in-progress + comment + audit log ---
now_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
wip_after=$((wip_count + 1))

if ! gh issue edit "$picked_number" --repo "$REPO" \
    --remove-label "status:ready" \
    --add-label "status:in-progress" >/dev/null 2>&1; then
  echo "ERROR: gh issue edit failed for #$picked_number" >&2
  exit 4
fi

# Comment is best-effort (warn on failure but still exit 0 since the flip succeeded).
if ! gh issue comment "$picked_number" --repo "$REPO" --body "🤖 **auto-claimed by $ROLE at $now_iso (WIP=$wip_after/$WIP_LIMIT)**

Per ADR-0038 §Auto-Claim Protocol. Priority=$picked_priority_label." >/dev/null 2>&1; then
  echo "WARN: comment failed for #$picked_number (claim still recorded)" >&2
fi

# Audit log: append-only, ISO-8601 + role + issue + wip + priority (ADR-0036 pattern).
repo_name="${REPO##*/}"
log_dir="${AUTO_CLAIM_LOG_DIR:-/var/log/dev-studio/${repo_name}}"
mkdir -p "$log_dir" 2>/dev/null || true
audit_log="$log_dir/auto-claim.log"
echo "$now_iso $ROLE claimed #$picked_number (WIP=$wip_after/$WIP_LIMIT, $picked_priority_label)" \
  >> "$audit_log" 2>/dev/null || echo "WARN: audit log write failed at $audit_log" >&2

echo "claimed #$picked_number (WIP=$wip_after/$WIP_LIMIT, $picked_priority_label)"
# End of critical section — flock released when subshell exits (success or failure).
# Propagate subshell exit code (0=claimed, 1=no-ready/no-dep-free, 3=WIP-cap, 4=API-error,
# 5=lock-busy-concurrent). Without `exit $?`, an unconditional `exit 0` would mask e.g. exit 3
# (WIP cap) that d031 TC4 expects. d809 race-guard must not regress d031 sister-test.
) 9>"$LOCK_FILE"
exit $?
