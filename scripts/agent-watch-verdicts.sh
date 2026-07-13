#!/usr/bin/env bash
# agent-watch-verdicts.sh — Standalone supplement for PR comment verdict detection.
#
# ⚠️  DEPRECATED (Issue #326 / ADR-0041 Phase 2, 2026-06-24)
# ----------------------------------------------------------
# This standalone supplement is SUPERSEDED by the native `verdict_posted`
# event kind in `scripts/agent-watch.sh` v8 (ADR-0041). Operators should
# stop running this script in new sessions; the main `agent-watch.sh`
# polling loop now emits `verdict_posted` events natively with the full
# ADR-0041 scope (agent:<role> OR cc:<role> OR verdict-by:<ts>, severity
# precedence, self-cc skip, 5-min bucket dedup).
#
# Sunset timeline (ADR-0041 §Deprecation):
#   Phase 0 (Issue #312 fix, 2026-06-23)  — this script shipped as Option B
#                                           fast-path (commit 52974ab,
#                                           later merged via PR #322)
#   Phase 1 (ADR-0041, 2026-06-24, PR #323) — long-term Option A documented
#   Phase 2 (THIS — Issue #326, 2026-06-24) — v8 native ships; this script
#                                             marked DEPRECATED, kept for
#                                             one sprint as belt+suspenders
#   Phase 3 (one sprint after v8 lands)   — retire entirely; d036 (PR #313,
#                                           MERGED) remains as sole
#                                           regression coverage
#
# If you are running this script today: prefer
# `bash scripts/agent-watch.sh <role> --once` (or --loop) instead. The
# native v8 path covers a strict superset of this script's behavior.
#
# Why this exists (original rationale)
# -------------------------------------
# scripts/agent-watch.sh v7 event taxonomy did NOT include a verdict_posted
# kind. Tester's comment-based verdicts (🟢 APPROVED / 🟡 SUGGESTIONS / 🔴
# CHANGES_REQUESTED) do not @-mention the role, so the pr_comment_mention
# event never fires. Result: developer idle for ~2h waiting on a verdict
# that was already delivered — RCA in Issue #312 (P0), incident case PR #307.
#
# Per Issue #312 Option B (defensive fix): standalone script + opt-in.
# agent-watch.sh v8 (Option A) is the long-term taxonomy change (separate
# ADR); this script is the fast-path fix that ships NOW. d036 (merged in
# PR #313) covers both paths via OR-check; this script satisfies Option B.
#
# Verdict classification (Issue #312 RCA Option A keyword table):
#   APPROVED          — 🟢 / APPROVED / LGTM / sign-off / sign off
#   SUGGESTIONS       — 🟡 / SUGGESTIONS / non-blocking
#   CHANGES_REQUESTED — 🔴 / CHANGES_REQUESTED / REQUEST CHANGES / blocker
#   (no verdict)      — anything else → NOT emitted (FP guard T6)
#
# Output: NDJSON, one event per line, schema:
#   {"kind":"verdict_posted","number":N,"verdict":"approved|suggestions|
#    changes_requested","author":"...","comment_id":...,"comment_url":"...",
#    "pr_url":"...","role":"developer|...","context":{"verdict_class":"..."}}
#
# verdict_class values (NDJSON convention): verdict:approved |
#   verdict:suggestions | verdict:changes_requested
#
# Usage:
#   bash scripts/agent-watch-verdicts.sh <role> [--poll-once]
#   bash scripts/agent-watch-verdicts.sh developer            # 60s loop
#   bash scripts/agent-watch-verdicts.sh developer --poll-once  # one-shot
#
# Exit: 0 on success (event emission is best-effort; missing gh auth → empty).
# Exit: 2 on usage error (no role / invalid role).
#
# Reference: Issue #312 RCA, PR #313 (regression test), ADR-0002 (autonomy
# loop), ADR-0017 (event taxonomy).

set -uo pipefail

ROLE="${1:-}"
POLL_ONCE=0
[ "${2:-}" = "--poll-once" ] && POLL_ONCE=1

# --- role validation ---
case "$ROLE" in
  orchestrator|product-manager|architect|developer|tester) ;;
  *)
    echo "usage: $0 <role> [--poll-once]" >&2
    echo "  role: orchestrator|product-manager|architect|developer|tester" >&2
    exit 2
    ;;
esac

command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

# --- verdict keyword regexes (Issue #312 RCA classification table) ---
# Word-boundary (\b) regex tightens the false-positive guard (T6) — bare
# substring match would over-fire on words like "approval" or "approved-by".
# Emojis are matched byte-literal (grep/[[ =~ ]] handle UTF-8 bytes fine).
VERDICT_APPROVED_REGEX='(\bAPPROVED\b|\bLGTM\b|sign-?off|🟢)'
VERDICT_SUGGESTIONS_REGEX='(\bSUGGESTIONS\b|non-?blocking|🟡)'
VERDICT_CHANGES_REGEX='(\bCHANGES_REQUESTED\b|\bREQUEST CHANGES\b|\bblocker\b|🔴)'

# classify_verdict <comment-body> -> "approved" | "suggestions" |
#   "changes_requested" | "" (no verdict)
# Order: changes_requested first (most severe wins if comment mentions both).
classify_verdict() {
  local body="$1"
  if [[ "$body" =~ $VERDICT_CHANGES_REGEX ]]; then
    printf '%s' "changes_requested"
  elif [[ "$body" =~ $VERDICT_APPROVED_REGEX ]]; then
    printf '%s' "approved"
  elif [[ "$body" =~ $VERDICT_SUGGESTIONS_REGEX ]]; then
    printf '%s' "suggestions"
  else
    printf '%s' ""
  fi
}

# fetch_relevant_prs — scope guard T7: only PRs where agent:<role> OR
# cc:<role> matches the polling role. Prevents verdict spam on unrelated PRs.
fetch_relevant_prs() {
  gh pr list --state all --limit 50 \
    --label "agent:${ROLE}" --json number,title,url,comments 2>/dev/null \
    || true
}

# emit_verdict_event — structured NDJSON event for the autonomy loop.
# comment_id is passed as --arg (string) because GH node IDs are strings like
# "IC_kwDOS9WE8s8AAAABHQ_EvQ"; --argjson would require a JSON number.
# Template is single-line so jq emits single-line NDJSON (multi-line templates
# preserve whitespace, which would break NDJSON consumers).
emit_verdict_event() {
  local pr_number="$1" verdict="$2" author="$3" \
        comment_id="$4" comment_url="$5" pr_url="$6"
  jq -nc \
    --arg kind "verdict_posted" \
    --argjson number "$pr_number" \
    --arg verdict "$verdict" \
    --arg author "$author" \
    --arg comment_id "$comment_id" \
    --arg comment_url "$comment_url" \
    --arg pr_url "$pr_url" \
    --arg role "$ROLE" \
    '{kind: $kind, number: $number, verdict: $verdict, author: $author, comment_id: $comment_id, comment_url: $comment_url, pr_url: $pr_url, role: $role, context: {verdict_class: ("verdict:" + $verdict), source: "agent-watch-verdicts.sh"}}'
}

# main poll loop — query PRs in scope, scan comments, classify, emit.
while true; do
  prs="$(fetch_relevant_prs)"
  if [ -n "$prs" ] && [ "$prs" != "null" ] && [ "$prs" != "[]" ]; then
    pr_count="$(printf '%s' "$prs" | jq 'length' 2>/dev/null || echo 0)"
    for i in $(seq 0 $((pr_count - 1))); do
      pr_json="$(printf '%s' "$prs" | jq -c ".[$i]")"
      pr_number="$(printf '%s' "$pr_json" | jq -r '.number // 0')"
      pr_url="$(printf '%s' "$pr_json" | jq -r '.url // ""')"
      comments="$(printf '%s' "$pr_json" | jq -c '.comments // []')"
      comment_count="$(printf '%s' "$comments" | jq 'length' 2>/dev/null || echo 0)"
      for j in $(seq 0 $((comment_count - 1))); do
        comment="$(printf '%s' "$comments" | jq -c ".[$j]")"
        body="$(printf '%s' "$comment" | jq -r '.body // ""')"
        verdict="$(classify_verdict "$body")"
        if [ -n "$verdict" ]; then
          author="$(printf '%s' "$comment" | jq -r '.author.login // "unknown"')"
          comment_id="$(printf '%s' "$comment" | jq -r '.id // ""')"
          comment_url="$(printf '%s' "$comment" | jq -r '.url // ""')"
          emit_verdict_event "$pr_number" "$verdict" "$author" \
            "$comment_id" "$comment_url" "$pr_url"
        fi
      done
    done
  fi

  [ "$POLL_ONCE" -eq 1 ] && break
  sleep 60
done

exit 0
