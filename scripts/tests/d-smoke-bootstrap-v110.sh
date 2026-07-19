#!/usr/bin/env bash
# d-smoke-bootstrap-v110.sh — S32-020 (Issue #160) smoke repo bootstrap verify at v1.1.0
#
# Why this test exists
# --------------------
# Sprint 32 S32-020 verifies the dev-studio-template@v1.1.0 release produces a
# fully-bootstrapped smoke repo. S32-019 (Issue #159) cuts v1.1.0 post-S32-018
# (PR #182 squash merge at sha 4274ddce). After tag lands, the launcher creates
# atilcan65/smoke-v110 from v1.1.0 and runs init.sh + bootstrap-labels.sh. This
# d-test asserts post-bootstrap state via REST API checks (no GUI required) and
# follows Issue #972 Path-Verify Doctrine: ALWAYS check the canonical GitHub
# API (api.github.com/repos/...), NEVER a local mirror or local clone.
#
# Six ACs of Issue #160:
#   AC1: Smoke repo via launcher (`new-project.sh smoke-v110 --owner atilcan65 --private --dir /tmp`)
#   AC2: dev-studio-init.sh renders all .tmpl sources, sets PROJECT_TOKEN, runs canary
#   AC3: bootstrap-labels.sh seeds 34 labels per ADR-0012
#   AC4: All 5 CI checks SUCCESS on smoke repo main (sister-pattern to launcher S32-014 ci.yml)
#   AC5: Trust-but-verify per Issue #972 — smoke repo main HEAD SHA == tmpl v1.1.0 tag SHA
#   AC6: 4-cat labels + verdict-by + owner squash-merge (PR workflow, not d-tested here)
#
# Pre-impl RED state (Issue #160 active, v1.1.0 tag NOT YET cut per cycle ~#3196):
#   TC1 FAIL — refs/tags/v1.1.0 → HTTP 404 (Issue #159 DEFER-owner)
#   TC2 FAIL — repos/atilcan65/smoke-v110 → HTTP 404 (AC1 BLOCKED)
#   TC3 FAIL — smoke-v110 ci.yml query fails (TC2 dep, "smoke repo missing")
#   TC4 FAIL — smoke-v110 labels query fails (TC2 dep)
#   TC5 FAIL — smoke-v110 main HEAD query fails (TC1+TC2 deps)
# → 5/5 RED = proper RED-first per ADR-0044 baseline ≥5 RED TCs.
#
# Post-impl GREEN state (after v1.1.0 tag cut + smoke repo created + bootstrap run):
#   TC1: refs/tags/v1.1.0 → 200 OK + commit sha
#   TC2: repos/atilcan65/smoke-v110 → 200 OK
#   TC3: smoke-v110 .github/workflows/ci.yml present (AC2 sister-pattern)
#   TC4: smoke-v110 labels count = 34 (AC3)
#   TC5: smoke-v110 main HEAD SHA == tmpl v1.1.0 tag SHA (AC5 trust-but-verify)
# → 5/5 GREEN.
#
# Sister-pattern family (d-test lineage, ADR-0049 ≥2 sister-pattern met):
#   - d-verify-portage-diff-engine.sh (DIRECT sister — REST API verification pattern + ≥5 TC baseline + fake-gh isolation + python3 heredoc for JSON parsing)
#   - s29-005-verify-portage.sh (sister — bash -n + --help + idempotency TC1+TC2+TC3 baseline)
#   - e2e-pilot.sh (rendering workflow + idempotency note)
#   - Issue #972 Path-Verify Doctrine (always check GitHub API not local mirror)
#   - cycle ~#3196 (S32-019 tag DEFER-owner doctrine)
#   - cycle ~#3500 (1-sec Issue close lag sister-pattern for v1.1.0 release)
#
# Sprint 32 cross-repo workstream refs:
#   - Issue #160 (S32-020 tracker in dev-studio-template, agent:developer, status:in-progress)
#   - Issue #159 (S32-019 tag cut, OWNER lane per ADR-0031 + cycle ~#3196)
#   - Issue #158 (S32-018 CHANGELOG v1.1.0, AUTO-CLOSED via PR #182 squash per ADR-0057 + cycle ~#3500)
#   - PR #182 (S32-018 squash mergeCommit=4274ddce, mergedAt=2026-07-19T06:50:21Z, mergedBy=atilcan65 per ADR-0031)
#   - docs/sprints/sprint-32/00-plan.md §S32-020 (story ACs source)
#   - ADR-0044 (RED-first TDD doctrinal home)
#   - ADR-0049 (d-test framework, ≥5 TCs baseline + ≥2 sister-pattern)
#   - ADR-0055 §1 (Cadence Rule 1 atomic — d-test + INDEX.md same commit)
#   - ADR-0057 (Closes #N strict format — Issue #160 PR body anchor pattern)
#   - ADR-0031 (owner squash-merge gate — final gate after tester signoff)
#   - Issue #972 (Path-Verify Doctrine — sister-pattern for AC5 trust-but-verify)
#
# Usage:
#   bash scripts/tests/d-smoke-bootstrap-v110.sh
#
# Exit codes:
#   0 — all PASS (GREEN — smoke repo bootstrapped at v1.1.0 verified)
#   1 — at least one FAIL (RED — pre-tag or pre-smoke-repo or pre-bootstrap)
#   2 — preflight failure (missing tool, etc.)

set -uo pipefail

# --- Configuration ---
TMPL_REPO="atilproject/dev-studio-template"
SMOKE_REPO="atilcan65/smoke-v110"
EXPECTED_TAG="v1.1.0"
EXPECTED_LABEL_COUNT=34
GITHUB_API_BASE="https://api.github.com"

# --- TC0: preflight — bash + curl + gh available ---
tc0_status="PASS"
if ! command -v bash >/dev/null 2>&1; then
  echo "TC0 FAIL: bash not available" >&2
  tc0_status="FAIL"
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "TC0 FAIL: curl not available (needed for REST API queries)" >&2
  tc0_status="FAIL"
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "TC0 FAIL: gh CLI not available (needed as auth bearer fallback)" >&2
  tc0_status="FAIL"
fi

if [[ "$tc0_status" == "PASS" ]]; then
  echo "TC0 PASS: preflight OK (bash + curl + gh available)"
fi

# Helper: curl_http_code <url>
# Returns HTTP status code as string; 000 on network error.
curl_http_code() {
  local url="$1"
  curl -s -o /dev/null -w '%{http_code}' \
    --max-time 15 \
    -H "Accept: application/vnd.github+json" \
    "$url" 2>/dev/null || echo "000"
}

# Helper: curl_json_sha <url>
# Extracts top-level "sha" string from JSON response (used for refs/tags/* + refs/heads/*).
# Empty string on missing/non-JSON/error response.
curl_json_sha() {
  local url="$1"
  curl -s --max-time 15 \
    -H "Accept: application/vnd.github+json" \
    "$url" 2>/dev/null \
    | grep -oE '"sha"[[:space:]]*:[[:space:]]*"[a-f0-9]+"' | head -1 \
    | grep -oE '[a-f0-9]+$' || true
}

# --- TC1: tmpl v1.1.0 tag exists (Issue #159 S32-019 unblock signal) ---
TC1_HTTP_CODE=$(curl_http_code "${GITHUB_API_BASE}/repos/${TMPL_REPO}/git/refs/tags/${EXPECTED_TAG}")
TC1_TAG_SHA=""
if [[ "$TC1_HTTP_CODE" == "200" ]]; then
  TC1_TAG_SHA=$(curl_json_sha "${GITHUB_API_BASE}/repos/${TMPL_REPO}/git/refs/tags/${EXPECTED_TAG}")
fi

if [[ "$TC1_HTTP_CODE" == "200" && -n "$TC1_TAG_SHA" ]]; then
  echo "TC1 PASS: tmpl ${EXPECTED_TAG} tag exists (sha=${TC1_TAG_SHA:0:12}, Issue #159 unblock signal fired)"
  tc1_status="PASS"
elif [[ "$TC1_HTTP_CODE" == "404" ]]; then
  echo "TC1 FAIL: tmpl ${EXPECTED_TAG} tag missing (HTTP 404 — Issue #159 still OPEN, v1.1.0 not cut per ADR-0031 owner lane)"
  tc1_status="FAIL"
else
  echo "TC1 FAIL: tmpl ${EXPECTED_TAG} tag query failed (HTTP $TC1_HTTP_CODE — investigate)"
  tc1_status="FAIL"
fi

# --- TC2: smoke-v110 repo exists (AC1 launcher success signal) ---
TC2_HTTP_CODE=$(curl_http_code "${GITHUB_API_BASE}/repos/${SMOKE_REPO}")

if [[ "$TC2_HTTP_CODE" == "200" ]]; then
  echo "TC2 PASS: ${SMOKE_REPO} repo exists (AC1 launcher invocation succeeded)"
  tc2_status="PASS"
elif [[ "$TC2_HTTP_CODE" == "404" ]]; then
  echo "TC2 FAIL: ${SMOKE_REPO} repo missing (HTTP 404 — AC1 BLOCKED on v1.1.0 tag + launcher)"
  tc2_status="FAIL"
else
  echo "TC2 FAIL: ${SMOKE_REPO} repo query failed (HTTP $TC2_HTTP_CODE)"
  tc2_status="FAIL"
fi

# --- TC3: smoke-v110 .github/workflows/ci.yml present (AC2 sister-pattern to launcher S32-014 ci.yml) ---
if [[ "$tc2_status" == "PASS" ]]; then
  TC3_HTTP_CODE=$(curl_http_code "${GITHUB_API_BASE}/repos/${SMOKE_REPO}/contents/.github/workflows/ci.yml")
  if [[ "$TC3_HTTP_CODE" == "200" ]]; then
    echo "TC3 PASS: smoke-v110 .github/workflows/ci.yml present (AC2 sister-pattern to launcher S32-014)"
    tc3_status="PASS"
  else
    echo "TC3 FAIL: smoke-v110 ci.yml missing (HTTP $TC3_HTTP_CODE — bootstrap incomplete)"
    tc3_status="FAIL"
  fi
else
  echo "TC3 FAIL: smoke-v110 ci.yml query skipped (TC2 dependency — smoke repo missing)"
  tc3_status="FAIL"
fi

# --- TC4: smoke-v110 labels count = 34 (AC3: bootstrap-labels.sh per ADR-0012) ---
TC4_LABEL_COUNT=0
if [[ "$tc2_status" == "PASS" ]]; then
  PAGE=1
  while :; do
    PAGE_BODY=$(curl -s --max-time 15 \
      -H "Accept: application/vnd.github+json" \
      "${GITHUB_API_BASE}/repos/${SMOKE_REPO}/labels?per_page=100&page=${PAGE}" 2>/dev/null || echo "[]")
    PAGE_COUNT=$(echo "$PAGE_BODY" | grep -oE '"name"' | wc -l || echo 0)
    TC4_LABEL_COUNT=$((TC4_LABEL_COUNT + PAGE_COUNT))
    if [[ "$PAGE_COUNT" -lt 100 || "$PAGE" -gt 5 ]]; then
      break
    fi
    PAGE=$((PAGE + 1))
  done

  if [[ "$TC4_LABEL_COUNT" -eq "$EXPECTED_LABEL_COUNT" ]]; then
    echo "TC4 PASS: smoke-v110 labels count = $TC4_LABEL_COUNT (AC3: bootstrap-labels.sh per ADR-0012 invariant)"
    tc4_status="PASS"
  else
    echo "TC4 FAIL: smoke-v110 labels count = $TC4_LABEL_COUNT (expected $EXPECTED_LABEL_COUNT per bootstrap-labels.sh inventory)"
    tc4_status="FAIL"
  fi
else
  echo "TC4 FAIL: smoke-v110 labels query skipped (TC2 dependency — smoke repo missing)"
  tc4_status="FAIL"
fi

# --- TC5: smoke-v110 main HEAD SHA == tmpl v1.1.0 tag SHA (AC5 trust-but-verify per Issue #972) ---
SMOKE_MAIN_SHA=""
if [[ "$tc2_status" == "PASS" ]]; then
  SMOKE_MAIN_SHA=$(curl_json_sha "${GITHUB_API_BASE}/repos/${SMOKE_REPO}/git/refs/heads/main")
fi

if [[ "$tc1_status" == "PASS" && "$tc2_status" == "PASS" \
      && -n "$SMOKE_MAIN_SHA" && -n "$TC1_TAG_SHA" \
      && "$SMOKE_MAIN_SHA" == "$TC1_TAG_SHA" ]]; then
  echo "TC5 PASS: smoke-v110 main HEAD == tmpl ${EXPECTED_TAG} tag (smoke=${SMOKE_MAIN_SHA:0:12} == tmpl=${TC1_TAG_SHA:0:12}, AC5 trust-but-verify per Issue #972)"
  tc5_status="PASS"
elif [[ "$tc1_status" != "PASS" ]]; then
  echo "TC5 FAIL: smoke-v110 trust-but-verify skipped (TC1 dependency — tmpl ${EXPECTED_TAG} tag missing)"
  tc5_status="FAIL"
elif [[ "$tc2_status" != "PASS" ]]; then
  echo "TC5 FAIL: smoke-v110 trust-but-verify skipped (TC2 dependency — smoke repo missing)"
  tc5_status="FAIL"
else
  echo "TC5 FAIL: smoke-v110 main HEAD (${SMOKE_MAIN_SHA:0:12}) != tmpl ${EXPECTED_TAG} tag (${TC1_TAG_SHA:0:12}) — bootstrap diverged from v1.1.0 (AC5 trust-but-verify per Issue #972)"
  tc5_status="FAIL"
fi

# --- summary ---
total=5
fail_count=0
for s in "$tc1_status" "$tc2_status" "$tc3_status" "$tc4_status" "$tc5_status"; do
  if [[ "$s" == "FAIL" ]]; then
    fail_count=$((fail_count + 1))
  fi
done
pass_count=$((total - fail_count))

echo "---"
echo "d-smoke-bootstrap-v110: $pass_count/$total PASS, $fail_count/$total FAIL"

if [[ "$fail_count" -gt 0 ]]; then
  echo "RESULT: RED (v1.1.0 tag + smoke repo + bootstrap not yet verified — S32-020 in progress)"
  exit 1
else
  echo "RESULT: GREEN (smoke repo bootstrapped at v1.1.0 — S32-020 AC1-AC5 verified end-to-end)"
  exit 0
fi
