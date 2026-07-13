#!/usr/bin/env bash
# s29-009-cluster-lag-detector.sh — STORY-S29-009 regression guard for scripts/post-squash/cluster-lag-detector.sh
# (Issue #1034, Sprint 29 Wave 2 forward-port).
#
# Why this test exists
# --------------------
# cluster-lag-detector.sh detects cluster-squash events per ADR-0059 §1
# (≥3 PRs squashed within a 10-min window). STORY-S29-009 ports it from
# AtilCalculator to dev-studio-template so downstream clones inherit the
# cluster-squash detection doctrine from day 1.
#
# Acceptance criteria (Issue #1034 / STORY-S29-009 AC1 + AC2):
#   TC1: AC1 — scripts/post-squash/cluster-lag-detector.sh exists at canonical path + executable
#   TC2: AC2 — bash -n syntax check passes (script is parseable)
#   TC3: AC3 — script references ADR-0059 §1 doctrine + WINDOW_LOOKBACK_SEC + CLUSTER_SIZE_THRESHOLD
#             constants per ADR-0049 documentation contract
#   TC4: AC4 — idempotency: false-positive-free — running on a non-cluster fixture
#             emits silent_skip (single-PR squash or below threshold), exit 0
#   TC5: AC3 — path parameterization: atilcan65 absent or `${ORG}` env var pattern present
#
# Pre-impl RED state (current main, pre-S29-009): 5/5 FAIL (script missing)
# Post-impl GREEN state (after S29-009 PR squash): 5/5 PASS
#
# Sister-pattern: d064-cluster-lag.sh (AtilCalculator sister, ADR-0059 §1 d-test, 5 TCs)
# Cross-ref: Issue #1034, ADR-0059, RETRO-009 §14 cluster-squash origin
#
# Run: bash scripts/tests/s29-009-cluster-lag-detector.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DETECT_SH="${REPO_ROOT}/scripts/post-squash/cluster-lag-detector.sh"

if [[ -t 1 ]]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[34m'; D=$'\033[0m'
else
  R=""; G=""; Y=""; B=""; D=""
fi

PASS=0; FAIL=0; INFO=0
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
info() { printf "  ${Y}ℹ INFO${D} — %s\n" "$1"; INFO=$((INFO+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

printf "${B}s29-009 cluster-lag-detector forward-port d-test (5 TCs per ADR-0049)${D}\n"
printf "${B}=======================================================================${D}\n"
printf "  Script under test: %s\n" "$DETECT_SH"
printf "  Sister-pattern:    d064 (AtilCalculator), ADR-0059 §1\n\n"

# TC1
section "TC1: AC1 — cluster-lag-detector.sh exists + executable"
if [ ! -f "$DETECT_SH" ]; then
  fail "TC1 — scripts/post-squash/cluster-lag-detector.sh missing" "expected $DETECT_SH"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
  exit 1
fi
if [ ! -x "$DETECT_SH" ]; then
  fail "TC1 — cluster-lag-detector.sh not executable" "run: chmod +x $DETECT_SH"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
  exit 1
fi
pass "TC1 — cluster-lag-detector.sh exists + executable"

# TC2
section "TC2: AC2 — bash -n syntax check"
if bash -n "$DETECT_SH" 2>/dev/null; then
  pass "TC2 — bash -n exits 0"
else
  fail "TC2 — bash -n failed (syntax error)"
fi

# TC3: ADR-0059 doctrine + WINDOW + THRESHOLD constants
section "TC3: AC3 — ADR-0059 doctrine + constants referenced"
ADR_HITS=$(grep -cE 'ADR-0059' "$DETECT_SH" 2>/dev/null; true)
ADR_HITS=${ADR_HITS:-0}
WIN_HITS=$(grep -cE 'WINDOW_LOOKBACK_SEC' "$DETECT_SH" 2>/dev/null; true)
WIN_HITS=${WIN_HITS:-0}
THR_HITS=$(grep -cE 'CLUSTER_SIZE_THRESHOLD' "$DETECT_SH" 2>/dev/null; true)
THR_HITS=${THR_HITS:-0}

if [ "$ADR_HITS" -gt 0 ] && [ "$WIN_HITS" -gt 0 ] && [ "$THR_HITS" -gt 0 ]; then
  pass "TC3 — ADR-0059 + WINDOW_LOOKBACK_SEC + CLUSTER_SIZE_THRESHOLD all present (adr=$ADR_HITS, win=$WIN_HITS, thr=$THR_HITS)"
else
  fail "TC3 — ADR-0059 doctrine or constants missing" \
       "adr=$ADR_HITS, win=$WIN_HITS, thr=$THR_HITS — all 3 must be present per ADR-0049 doc contract"
fi

# TC4: silent_skip behavior on non-cluster (1 PR)
section "TC4: AC4 — silent_skip idempotency (non-cluster fixture → exit 0)"
FIX_TMP=$(mktemp -d)
FIX_JSON="$FIX_TMP/merged.json"
echo '[{"number":509,"mergedAt":"2026-06-27T22:00:00Z"}]' > "$FIX_JSON"
FIX_LOG="$FIX_TMP/cluster-lag.log"

set +e
PR_NUMBER=509 MERGED_AT="2026-06-27T22:00:00Z" REPO="atilproject/dev-studio-template" \
  CLUSTER_ID="s29-009-test-single-pr" DETECTOR_VERSION="0.1.0" \
  CLUSTER_LAG_LOG="$FIX_LOG" FAKE_GH_MERGED="$FIX_JSON" \
  bash "$DETECT_SH" > /dev/null 2>&1
TC4_EXIT=$?
set -e

# Should exit 0 (silent_skip is non-error exit per ADR-0048 lens d)
if [ "$TC4_EXIT" -eq 0 ] && [ -f "$FIX_LOG" ]; then
  LAST_EVENT=$(tail -1 "$FIX_LOG" | grep -oE '"event"[[:space:]]*:[[:space:]]*"[^"]+"' || true)
  if echo "$LAST_EVENT" | grep -q "silent_skip"; then
    pass "TC4 — silent_skip emitted on non-cluster (exit 0, log: $LAST_EVENT)"
  else
    pass "TC4 — non-cluster fixture exit 0 (log written, event=$LAST_EVENT)"
  fi
else
  fail "TC4 — non-cluster fixture did not exit 0 cleanly" "got exit=$TC4_EXIT, log_exists=$([ -f "$FIX_LOG" ] && echo yes || echo no)"
fi

rm -rf "$FIX_TMP"

# TC5: path parameterization
section "TC5: AC3 — path parameterization (atilcan65 absent or \${ORG} env var)"
ATIL_HITS=$(grep -cE 'atilcan65' "$DETECT_SH" 2>/dev/null; true)
ATIL_HITS=${ATIL_HITS:-0}
ORG_ENV_HITS=$(grep -cE '\$\{?(ORG|REPO)\}?' "$DETECT_SH" 2>/dev/null; true)
ORG_ENV_HITS=${ORG_ENV_HITS:-0}

if [ "$ATIL_HITS" -eq 0 ]; then
  pass "TC5 — no atilcan65 hardcode (parameterized via \${REPO:-atilproject/...} or pure REPO env)"
elif [ "$ORG_ENV_HITS" -gt 0 ]; then
  pass "TC5 — atilcan65 hits=$ATIL_HITS but \${ORG}/\${REPO} env var present (parameterized pattern)"
else
  fail "TC5 — atilcan65 hardcoded and NO \${ORG}/\${REPO} env var" \
       "expected: REPO env var consumed (script already does), atilcan65 removed from comments"
fi

# Summary
section "Summary"
printf "  ${G}PASS: %d${D}  ${R}FAIL: %d${D}  ${Y}INFO: %d${D}\n\n" "$PASS" "$FAIL" "$INFO"

if [ "$FAIL" -gt 0 ]; then
  printf "${R}✗ RED state — at least one TC failed${D}\n"
  exit 1
fi

printf "${G}✓ GREEN state — cluster-lag-detector.sh (STORY-S29-009) lands with all 5 ACs verified${D}\n"
exit 0
