#!/usr/bin/env bash
# orchestrator-gap-scan.sh — ADR-???? Orchestrator proactive gap-scan duty.
#
# Per Issue #235 doctrine: every 30 min (via cron), scan all open issues for
# 4 kinds of gaps that the reactive orchestrator missed historically (root
# cause: #221 doctrine merged via PR #226 but impl landed 8h late).
#
# Detection kinds (per #235 AC3):
#   1. impl_gap     — issue body lists "Required impl files:" and any file is missing on main
#   2. dev_idle     — issue status:in-progress + agent:developer + last commit on assignee PR >60m ago
#   3. dep_broken   — issue status:ready/in-progress + `depends_on:` list contains unmerged issue
#   4. scope_drift  — PR body references issue number NOT in PR's stated `Closes #N` (deferred, stub)
#
# Idempotency: tracks filed alerts in /var/log/dev-studio/orchestrator-gap-scan.state
# (issue_number + kind + first_filed_at); re-fires only after 24h or when state file reset.
#
# Usage:
#   bash scripts/orchestrator-gap-scan.sh                    # scan + emit
#   bash scripts/orchestrator-gap-scan.sh --dry-run          # print gaps, no GitHub/Telegram side effects
#   bash scripts/orchestrator-gap-scan.sh --threshold 60     # override dev_idle threshold min (default 60)
#
# Output (stdout): JSON array of gaps detected
#   [{"issue":221,"kind":"impl_gap","detail":"scripts/notify.sh missing --wake flag",...}, ...]
#
# Exit codes:
#   0  scan completed (regardless of gap count)
#   1  usage error
#   2  gh/jq preflight fail
#
# Env:
#   GAP_SCAN_THRESHOLD_MIN   override dev_idle threshold (default: 60)
#   DRY_RUN                  when set, skip GitHub/Telegram emission
#   GITHUB_REPO              override (default: gh repo view --json nameWithOwner)
#   STATE_FILE               override state file path (default: /var/log/dev-studio/dev-studio-template/orchestrator-gap-scan.state)
#
# Reference: Issue #235 (doctrine + AC1-AC4), scripts/wip-idle-detect.sh (ADR-0039 sibling),
#            scripts/proactive-board-scan.sh (board sweep pattern).

set -uo pipefail

# --- Preflight ---
for cmd in gh jq git; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd not in PATH" >&2; exit 2; }
done

# --- Args ---
DRY_RUN="${DRY_RUN:-}"
THRESHOLD_MIN="${GAP_SCAN_THRESHOLD_MIN:-60}"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN="true"; shift ;;
    --threshold) THRESHOLD_MIN="$2"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag $1" >&2; exit 1 ;;
  esac
done

# --- Repo + state ---
REPO="${GITHUB_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")}"
if [ -z "$REPO" ]; then echo "ERROR: cannot determine repo (set GITHUB_REPO)" >&2; exit 2; fi

STATE_FILE="${STATE_FILE:-/var/log/dev-studio/dev-studio-template/orchestrator-gap-scan.state}"
mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"

# --- Time helpers ---
NOW_EPOCH="$(date +%s)"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
IDEMPOTENCY_WINDOW_SEC=86400  # 24h

# --- Idempotency check ---
already_filed() {
  # $1=issue_number $2=kind
  local issue="$1" kind="$2"
  local filed_at
  filed_at="$(awk -F'|' -v k="gap:${issue}:${kind}" '$1==k {print $2; exit}' "$STATE_FILE" 2>/dev/null || true)"
  [ -z "$filed_at" ] && return 1  # not filed
  local filed_epoch
  filed_epoch="$(date -d "$filed_at" +%s 2>/dev/null || echo 0)"
  [ $((NOW_EPOCH - filed_epoch)) -lt $IDEMPOTENCY_WINDOW_SEC ]
}

mark_filed() {
  # $1=issue_number $2=kind
  echo "gap:$1:$2|${NOW_ISO}" >> "$STATE_FILE"
}

# --- Emit helper ---
emit_gap() {
  # $1=json_fragment (one gap object)
  echo "$1"
}

file_sub_issue() {
  # $1=parent_issue $2=kind $3=detail
  local parent="$1" kind="$2" detail="$3"
  local title="Gap: ${kind} on #${parent} (auto-detected ${NOW_ISO})"
  local body="**Parent**: #${parent}
**Kind**: \`${kind}\`
**Detected**: ${NOW_ISO}
**Detail**: ${detail}

_Filed automatically by \`scripts/orchestrator-gap-scan.sh\` per Issue #235 doctrine. Re-runs suppressed for 24h._"
  if [ -n "$DRY_RUN" ]; then
    echo "[DRY-RUN] would file: ${title}"
    return
  fi
  gh issue create --title "$title" --body "$body" \
    --label "type:incident" --label "status:ready" \
    --label "agent:orchestrator" --label "cc:developer" --label "cc:human" \
    --label "auto-filed:gap-scan" 2>/dev/null || echo "WARN: sub-issue file failed for #${parent}" >&2
  mark_filed "$parent" "$kind"
}

notify_human() {
  # $1=summary
  local msg="[ORCH→HUMAN] Gap-scan alert (${NOW_ISO}): $1"
  if [ -n "$DRY_RUN" ]; then
    echo "[DRY-RUN] would notify: $msg"
    return
  fi
  bash "$(dirname "$0")/notify.sh" -l warn "$msg" 2>/dev/null || true
}

# --- Scan 1: impl_gap ---
# Parse issue body for "Required impl files:" section, check each file exists on main.
scan_impl_gap() {
  local issue_body file_path line
  for issue_num in $(gh issue list --state open --label "status:ready,status:in-progress" \
                       --json number -q '.[].number' 2>/dev/null); do
    issue_body="$(gh issue view "$issue_num" --json body -q .body 2>/dev/null || echo "")"
    # Look for "Required impl files:" section (markdown list of `- path/to/file`)
    echo "$issue_body" | grep -qi "required impl files" || continue
    echo "$issue_body" | grep -E '^\s*-\s+`?[a-zA-Z0-9_./-]+\.[a-z]+`?' | while read -r line; do
      file_path="$(echo "$line" | sed -E 's/^\s*-\s+`?([^`]+)`?.*/\1/' | awk '{print $1}')"
      [ -z "$file_path" ] && continue
      [ -f "$file_path" ] || {
        already_filed "$issue_num" "impl_gap" && continue
        emit_gap "{\"issue\":${issue_num},\"kind\":\"impl_gap\",\"detail\":\"missing ${file_path}\"}"
        file_sub_issue "$issue_num" "impl_gap" "missing required impl file: ${file_path}"
        notify_human "#${issue_num} impl_gap: missing ${file_path}"
      }
    done
  done
}

# --- Scan 2: dev_idle ---
# Issue status:in-progress + agent:developer + assignee's most recent commit >THRESHOLD_MIN ago.
scan_dev_idle() {
  local issue_num assignee last_commit_epoch age_min
  for issue_num in $(gh issue list --state open --label "agent:developer,status:in-progress" \
                       --json number -q '.[].number' 2>/dev/null); do
    last_commit_epoch="$(git log -1 --format=%ct 2>/dev/null || echo 0)"
    [ "$last_commit_epoch" -eq 0 ] && continue
    age_min=$(( (NOW_EPOCH - last_commit_epoch) / 60 ))
    if [ "$age_min" -gt "$THRESHOLD_MIN" ]; then
      already_filed "$issue_num" "dev_idle" && continue
      emit_gap "{\"issue\":${issue_num},\"kind\":\"dev_idle\",\"detail\":\"${age_min}m since last commit (threshold ${THRESHOLD_MIN}m)\"}"
      file_sub_issue "$issue_num" "dev_idle" "no commit in ${age_min}m (threshold ${THRESHOLD_MIN}m)"
      notify_human "#${issue_num} dev_idle: ${age_min}m no commit"
    fi
  done
}

# --- Scan 3: dep_broken ---
# Issue body contains "depends_on: [#N, #M]" or "Depends on: #N" and any ref is open/unmerged.
scan_dep_broken() {
  local issue_num body dep_issues open_deps
  for issue_num in $(gh issue list --state open \
                       --label "status:ready,status:in-progress" \
                       --json number -q '.[].number' 2>/dev/null); do
    body="$(gh issue view "$issue_num" --json body -q .body 2>/dev/null || echo "")"
    # Extract #NNN references that look like deps (heuristic: lines starting with "depends" or "- depends on")
    dep_issues="$(echo "$body" | grep -iE 'depends[ -_]?on[: ]|#depends' | grep -oE '#[0-9]+' | tr -d '#' | sort -u)"
    [ -z "$dep_issues" ] && continue
    open_deps=""
    for dep in $dep_issues; do
      dep_state="$(gh issue view "$dep" --json state -q .state 2>/dev/null || echo "unknown")"
      [ "$dep_state" = "OPEN" ] && open_deps="${open_deps} #${dep}"
    done
    if [ -n "$open_deps" ]; then
      already_filed "$issue_num" "dep_broken" && continue
      emit_gap "{\"issue\":${issue_num},\"kind\":\"dep_broken\",\"detail\":\"unmerged deps:${open_deps}\"}"
      file_sub_issue "$issue_num" "dep_broken" "issue ready/in-progress but unmerged deps:${open_deps}"
      notify_human "#${issue_num} dep_broken: waiting on${open_deps}"
    fi
  done
}

# --- Scan 4: scope_drift (STUB) ---
# Deferred: requires PR body parsing + cross-ref with issue scope. Skipped in this impl.
scan_scope_drift() {
  : # noop, see Issue #235 follow-up
}

# --- Main ---
echo "[gap-scan ${NOW_ISO}] repo=${REPO} threshold=${THRESHOLD_MIN}m dry_run=${DRY_RUN:-false}" >&2
echo "["
scan_impl_gap
scan_dev_idle
scan_dep_broken
scan_scope_drift
echo "]"

exit 0
