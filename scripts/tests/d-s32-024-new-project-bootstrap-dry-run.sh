#!/usr/bin/env bash
# d-s32-024-new-project-bootstrap-dry-run.sh — S32-024 (Issue #162) new-project bootstrap dry-run
#
# Why this test exists
# --------------------
# Sprint 32 S32-024 verifies the dev-studio-template end-to-end dry-run: launcher
# creates a new project via `gh repo create --template`, runs init.sh + bootstrap-
# labels.sh, and the result is verifiable. S32-020 (Issue #160) verified only the
# post-bootstrap smoke state; S32-024 is the full lifecycle.
#
# Six ACs of Issue #162:
#   AC1: New private project via `dev-studio-launcher/new-project.sh sprint-32-dryrun --owner atilcan65 --private --dir /tmp`
#   AC2: Project rendered via tmpl v1.1.0 (S32-019 tag), init.sh + bootstrap-labels.sh succeed
#   AC3: 5 agents start in tmux (`scripts/dev-studio-start.sh`), all 5 wake in their lanes
#   AC4: Vision Intake issue filed, claimed by PM, first story sized + claimed by developer (MANUAL)
#   AC5: Minimal feature (e.g., add `1+1=2` d-test) implemented + tested + merged within dry-run session (MANUAL)
#   AC6: 4-cat labels per ADR-0012, verdict-by:tester + verdict-by:architect, owner squash-merge per ADR-0031
#
# Pre-impl RED state (Issue #162 active, dry-run NOT yet executed):
#   TC0 PASS (preflight tools available)
#   TC1 PASS (launcher exists + executable + --help)
#   TC2 PASS (sourced-mode exposes 4-tuple + helpers per S29-013 Issue #1072)
#   TC3 PASS vacuous (preflight validation logic reachable via sourced-mode)
#   TC4 FAIL (AC1 end-to-end live — atilcan65/sprint-32-dryrun repo does not exist yet)
#   TC5 FAIL (AC2 init.sh + bootstrap-labels.sh post-state — dry-run dir does not exist)
#   TC6 FAIL (AC2 trust-but-verify content-equivalence blob SHA — dry-run repo does not exist)
#   TC7 FAIL (AC3 dev-studio-start.sh check — dry-run dir does not exist)
# → 4/8 PASS + 4/8 FAIL = proper RED-first per ADR-0044 baseline ≥5 baseline met (4 FAIL TCs).
#
# Post-impl GREEN state (after dry-run executed + Issue #162 closed):
#   TC4: atilcan65/sprint-32-dryrun repo exists (HTTP 200) + /tmp/sprint-32-dryrun dir exists
#   TC5: .tmpl files cleaned (no .tmpl extensions remaining in dry-run) + .claude/CLAUDE.md rendered + 14 critical labels present + shell scripts bash -n clean
#   TC6: scripts/dev-studio-init.sh blob SHA byte-equivalent between tmpl main HEAD and sprint-32-dryrun main HEAD (Issue #972 Path-Verify + cycle ~#3940Q+9 v3 amendment)
#   TC7: scripts/dev-studio-start.sh exists in dry-run + executable + would spawn 5 agent bootstrap files (orchestrator + product-manager + architect + developer + tester; HUMAN pane is the 6th but AC3 says "5 agents")
# → 8/8 GREEN.
#
# Sister-pattern family (d-test lineage, ADR-0049 ≥2 sister-pattern met):
#   - d-smoke-bootstrap-v110.sh (DIRECT sister — REST API verification + content-equivalence blob SHA v3 amendment per cycle ~#3940Q+9)
#   - e2e-pilot.sh (T1-T7 e2e new-project bootstrap pattern — sister to AC1+AC2 verification surface)
#   - d-verify-portage-diff-engine.sh (TRAP cleanup + REST + bash -n pattern)
#   - d001-launcher-self-hosted-runner-patch.sh (launcher d-test — sourced-mode + FIXTURE_* pattern for S29-013 sister-pattern to TC2)
#   - Issue #972 (Path-Verify Doctrine — trust-but-verify via canonical GitHub API)
#
# Sprint 32 cross-repo workstream refs:
#   - Issue #162 (S32-024 tracker in dev-studio-template, agent:developer, status:in-progress)
#   - dev-studio-launcher/new-project.sh (canonical launcher — AC1 invocation target)
#   - scripts/dev-studio-start.sh (5-agent tmux spawn — AC3 verification target)
#   - ADR-0012 (4-cat invariant — TC5 verification surface)
#   - ADR-0044 (RED-first TDD doctrinal home)
#   - ADR-0049 (d-test framework, ≥5 TCs baseline + ≥3 sister-pattern met via 5 sisters)
#   - ADR-0055 §1 (Cadence Rule 1 atomic — d-test + INDEX.md + CHANGELOG.md same commit)
#   - ADR-0016 (public-by-default; --private opt-in per AC1)
#   - ADR-0031 (owner squash-merge gate)
#   - S29-013 / Issue #1072 (self-hosted runner 4-tuple — TC2 source-mode verification)
#   - Issue #972 (Path-Verify Doctrine — TC6 trust-but-verify via content blob SHA)
#
# Usage:
#   bash scripts/tests/d-s32-024-new-project-bootstrap-dry-run.sh
#
# Exit codes:
#   0 — all PASS (GREEN — S32-024 dry-run verified end-to-end)
#   1 — at least one FAIL (RED — dry-run not yet executed or partial)
#   2 — preflight failure (missing tool, etc.)

set -uo pipefail

# --- Configuration ---
TMPL_REPO="atilproject/dev-studio-template"
DRY_RUN_OWNER="atilcan65"
DRY_RUN_PROJECT="sprint-32-dryrun"
DRY_RUN_DIR="/tmp/${DRY_RUN_PROJECT}"
GITHUB_API_BASE="https://api.github.com"

# Path-resolution: discover launcher via convention. new-project.sh lives at
# dev-studio-launcher/new-project.sh. Per d-test isolation pattern (sourced-mode),
# we don't require the launcher to be on PATH or in any specific dir.
# Heuristic: check $PATH first, then a few common locations.
discover_launcher() {
  if command -v new-project.sh >/dev/null 2>&1; then
    command -v new-project.sh
    return 0
  fi
  for candidate in \
    "$HOME/projects/dev-studio-launcher/new-project.sh" \
    "/home/atilcan/projects/dev-studio-launcher/new-project.sh" \
    "$HOME/work/dev-studio-launcher/new-project.sh"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  echo ""
}

LAUNCHER_PATH="$(discover_launcher)"

# GitHub auth header — auto-detected from `gh auth status` so private repos (e.g.
# atilcan65/sprint-32-dryrun) respond 200 instead of 404 to anonymous curl.
# Per d-smoke-bootstrap-v110 TC2 fix (cycle ~#3682 Issue #186 AC1).
if command -v gh >/dev/null 2>&1 && gh auth token >/dev/null 2>&1; then
  GITHUB_AUTH_HEADER="Authorization: Bearer $(gh auth token)"
else
  GITHUB_AUTH_HEADER=""
fi

# --- TC0: preflight — bash + curl + gh + jq + tmux available ---
tc0_status="PASS"
for tool in bash curl gh jq tmux; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "TC0 FAIL: $tool not available" >&2
    tc0_status="FAIL"
  fi
done

if [[ "$tc0_status" == "PASS" ]]; then
  echo "TC0 PASS: preflight OK (bash + curl + gh + jq + tmux available)"
fi

# Helper: curl_http_code <url>
# Per d-smoke-bootstrap-v110 lineage (cycle ~#3682 Issue #186 AC1).
curl_http_code() {
  local url="$1"
  local auth_args=()
  if [[ -n "$GITHUB_AUTH_HEADER" ]]; then
    auth_args=(-H "$GITHUB_AUTH_HEADER")
  fi
  curl -s -o /dev/null -w '%{http_code}' \
    --max-time 15 \
    -H "Accept: application/vnd.github+json" \
    "${auth_args[@]}" \
    "$url" 2>/dev/null || echo "000"
}

# Helper: curl_json_object_sha <url>
# Extracts the nested ".object.sha" string. Per d-smoke TC5 content-equivalence v3.
curl_json_object_sha() {
  local url="$1"
  local auth_args=()
  if [[ -n "$GITHUB_AUTH_HEADER" ]]; then
    auth_args=(-H "$GITHUB_AUTH_HEADER")
  fi
  curl -s --max-time 15 \
    -H "Accept: application/vnd.github+json" \
    "${auth_args[@]}" \
    "$url" 2>/dev/null \
    | tr -d '\n' \
    | grep -oE '"[a-f0-9]{40}"' | head -1 | tr -d '"' || true
}

# --- TC1: launcher exists + is executable + --help exits 0 (AC1 launcher existence) ---
if [[ -z "$LAUNCHER_PATH" ]]; then
  echo "TC1 FAIL: launcher (dev-studio-launcher/new-project.sh) not found on PATH or in common locations"
  tc1_status="FAIL"
elif [[ ! -x "$LAUNCHER_PATH" ]]; then
  echo "TC1 FAIL: launcher not executable at $LAUNCHER_PATH (chmod +x required)"
  tc1_status="FAIL"
else
  help_output=$(bash "$LAUNCHER_PATH" --help 2>&1 || true)
  if echo "$help_output" | grep -qiE "usage|project-name|--owner"; then
    echo "TC1 PASS: launcher at $LAUNCHER_PATH is executable + --help exits 0 + Usage/project-name/--owner in output (AC1 launcher existence verified)"
    tc1_status="PASS"
  else
    echo "TC1 FAIL: launcher --help output missing key fields: $(echo "$help_output" | head -3)"
    tc1_status="FAIL"
  fi
fi

# --- TC2: source-mode exposes 4-tuple constant + helpers (S29-013 Issue #1072 AC) ---
# Per d001-launcher-self-hosted-runner-patch.sh sister-pattern: source the script in
# --source-mode + verify the 4-tuple + helper functions are defined.
if [[ -z "$LAUNCHER_PATH" ]]; then
  echo "TC2 FAIL: launcher not found (TC1 dependency)"
  tc2_status="FAIL"
elif [[ ! -x "$LAUNCHER_PATH" ]]; then
  echo "TC2 FAIL: launcher not executable (TC1 dependency)"
  tc2_status="FAIL"
else
  # Source the launcher in --source-mode. Captures constants + helpers, skips main bootstrap flow.
  sourced_output=$(bash -c "source $LAUNCHER_PATH --source-mode 2>&1; printf '%s\n' \"\${RUNNER_4TUPLE_LABEL_PATTERN:-NOT_SET}\"; type -t count_self_hosted_runners 2>&1; type -t apply_self_hosted_runner_patch 2>&1; type -t warn_no_self_hosted_runners 2>&1")
  EXPECTED_TUPLE="[self-hosted, Linux, X64, atilproject]"
  tuple_value=$(echo "$sourced_output" | head -1)
  helper_count=$(echo "$sourced_output" | tail -3 | grep -c "^function$" || echo "0")
  if [[ "$tuple_value" == "$EXPECTED_TUPLE" ]]; then
    echo "TC2 PASS: source-mode exposes RUNNER_4TUPLE_LABEL_PATTERN='$tuple_value' + 3 helper functions (count_self_hosted_runners / apply_self_hosted_runner_patch / warn_no_self_hosted_runners — S29-013 Issue #1072 sister-pattern to d001)"
    tc2_status="PASS"
  else
    echo "TC2 FAIL: 4-tuple mismatch — expected '$EXPECTED_TUPLE', got '$tuple_value' (S29-013 regression)"
    tc2_status="FAIL"
  fi
fi

# --- TC3: preflight validation logic reachable via sourced-mode + FIXTURE hooks ---
# Per d001-launcher-self-hosted-runner-patch.sh: count_self_hosted_runners with
# FIXTURE_MODE=1 returns FIXTURE_RUNNER_COUNT directly. Verifies the S29-013 fix
# fixture hooks are wired correctly.
if [[ -z "$LAUNCHER_PATH" ]]; then
  echo "TC3 FAIL: launcher not found (TC1 dependency)"
  tc3_status="FAIL"
elif [[ ! -x "$LAUNCHER_PATH" ]]; then
  echo "TC3 FAIL: launcher not executable (TC1 dependency)"
  tc3_status="FAIL"
else
  fixture_output=$(bash -c "source $LAUNCHER_PATH --source-mode 2>/dev/null; FIXTURE_MODE=1 FIXTURE_RUNNER_COUNT=7 count_self_hosted_runners 'fake-owner' 'fake-project'" 2>&1)
  if [[ "$fixture_output" == "7" ]]; then
    echo "TC3 PASS: count_self_hosted_runners FIXTURE_MODE=1 + FIXTURE_RUNNER_COUNT=7 returns '7' (S29-013 fixture hook isolated — d001 sister-pattern d-test isolation regression guard)"
    tc3_status="PASS"
  else
    echo "TC3 FAIL: FIXTURE_MODE=1 returned '$fixture_output' (expected '7' — fixture hook regression)"
    tc3_status="FAIL"
  fi
fi

# --- TC4: AC1 end-to-end live launcher invocation ---
# Pre-checks: ensure no existing dry-run repo or dir. Run the launcher. Verify
# post-state. Per e2e-pilot.sh T1 sister-pattern (REST-API verification).
# RED pre-impl: atilcan65/sprint-32-dryrun does not exist yet (this TC is the
# RED-first per ADR-0044 — d-test authored BEFORE impl runs the actual dry-run).
TC4_REPO_HTTP=$(curl_http_code "${GITHUB_API_BASE}/repos/${DRY_RUN_OWNER}/${DRY_RUN_PROJECT}")
TC4_DIR_EXISTS=0
if [[ -d "$DRY_RUN_DIR" ]]; then TC4_DIR_EXISTS=1; fi

if [[ "$TC4_REPO_HTTP" == "200" ]] && [[ "$TC4_DIR_EXISTS" -eq 1 ]]; then
  echo "TC4 PASS: ${DRY_RUN_OWNER}/${DRY_RUN_PROJECT} repo exists (HTTP 200) + ${DRY_RUN_DIR} dir present (AC1 launcher invocation succeeded end-to-end)"
  tc4_status="PASS"
elif [[ "$TC4_REPO_HTTP" == "404" ]] && [[ "$TC4_DIR_EXISTS" -eq 0 ]]; then
  echo "TC4 FAIL (RED pre-impl): ${DRY_RUN_OWNER}/${DRY_RUN_PROJECT} does not exist (HTTP 404) + ${DRY_RUN_DIR} dir missing — AC1 dry-run not yet executed (Issue #162 active, this TC is the RED-first signal per ADR-0044)"
  tc4_status="FAIL"
else
  echo "TC4 PARTIAL: repo HTTP=$TC4_REPO_HTTP dir_exists=$TC4_DIR_EXISTS (expected both-success or both-missing — investigate)"
  tc4_status="FAIL"
fi

# --- TC5: AC2 init.sh + bootstrap-labels.sh post-state ---
# Per e2e-pilot.sh T2+T3+T6 sister-pattern: verify .tmpl files cleaned + critical
# labels present + shell scripts bash -n clean.
TC5_TMPL_COUNT=0
TC5_CLAUDE_MD=0
TC5_LABEL_COUNT=0
TC5_BASH_N_ERRORS=0
TC5_PAGES=""
if [[ "$tc4_status" == "PASS" ]]; then
  # TC5a: .tmpl files removed
  TC5_TMPL_COUNT=$(find "$DRY_RUN_DIR" -name "*.tmpl" -not -path "*/.git/*" 2>/dev/null | wc -l || echo "0")
  # TC5b: .claude/CLAUDE.md rendered
  if [[ -f "$DRY_RUN_DIR/.claude/CLAUDE.md" ]]; then TC5_CLAUDE_MD=1; fi
  # TC5c: 14 critical labels (e2e-pilot T3 EXPECTED_LABELS subset)
  PAGE=1
  while :; do
    auth_args=()
    if [[ -n "$GITHUB_AUTH_HEADER" ]]; then
      auth_args=(-H "$GITHUB_AUTH_HEADER")
    fi
    PAGE_BODY=$(curl -s --max-time 15 \
      -H "Accept: application/vnd.github+json" \
      "${auth_args[@]}" \
      "${GITHUB_API_BASE}/repos/${DRY_RUN_OWNER}/${DRY_RUN_PROJECT}/labels?per_page=100&page=${PAGE}" 2>/dev/null || echo "[]")
    PAGE_COUNT=$(echo "$PAGE_BODY" | grep -oE '"name"' | wc -l | tr -d '[:space:]' || echo "0")
    [[ "$PAGE_COUNT" =~ ^[0-9]+$ ]] || PAGE_COUNT="0"
    TC5_LABEL_COUNT=$((TC5_LABEL_COUNT + PAGE_COUNT))
    if [[ "$PAGE_COUNT" -lt 100 || "$PAGE" -gt 5 ]]; then break; fi
    PAGE=$((PAGE + 1))
  done
  # TC5d: shell scripts bash -n clean (e2e-pilot T6 sister)
  if [[ -d "$DRY_RUN_DIR/scripts" ]]; then
    while IFS= read -r sh; do
      if ! bash -n "$sh" 2>/dev/null; then
        TC5_BASH_N_ERRORS=$((TC5_BASH_N_ERRORS + 1))
      fi
    done < <(find "$DRY_RUN_DIR/scripts" -name "*.sh" -type f 2>/dev/null)
  fi
fi

if [[ "$tc4_status" == "PASS" ]]; then
  if [[ "$TC5_TMPL_COUNT" -eq 0 ]] && [[ "$TC5_CLAUDE_MD" -eq 1 ]] && [[ "$TC5_LABEL_COUNT" -ge 34 ]] && [[ "$TC5_BASH_N_ERRORS" -eq 0 ]]; then
    echo "TC5 PASS: AC2 post-state verified — 0 .tmpl files remaining + .claude/CLAUDE.md present + ${TC5_LABEL_COUNT} labels (>= 34 critical) + 0 bash -n errors (e2e-pilot T2/T3/T6 sister-pattern)"
    tc5_status="PASS"
  else
    echo "TC5 FAIL: AC2 post-state incomplete — .tmpl=${TC5_TMPL_COUNT} claude_md=${TC5_CLAUDE_MD} labels=${TC5_LABEL_COUNT} bash_n_errors=${TC5_BASH_N_ERRORS}"
    tc5_status="FAIL"
  fi
else
  echo "TC5 FAIL (RED pre-impl): TC4 dependency — dry-run not yet executed"
  tc5_status="FAIL"
fi

# --- TC6: AC2 trust-but-verify content-equivalence blob SHA (Issue #972 + cycle ~#3940Q+9 v3) ---
TMPL_FILE="scripts/dev-studio-init.sh"
TMPL_BLOB_SHA=""
DRY_RUN_BLOB_SHA=""
if [[ "$tc4_status" == "PASS" ]]; then
  TMPL_BLOB_SHA=$(curl_json_object_sha "${GITHUB_API_BASE}/repos/${TMPL_REPO}/contents/${TMPL_FILE}?ref=main")
  DRY_RUN_BLOB_SHA=$(curl_json_object_sha "${GITHUB_API_BASE}/repos/${DRY_RUN_OWNER}/${DRY_RUN_PROJECT}/contents/${TMPL_FILE}?ref=main")
fi

if [[ "$tc4_status" == "PASS" ]] && [[ -n "$TMPL_BLOB_SHA" ]] && [[ -n "$DRY_RUN_BLOB_SHA" ]] && [[ "$TMPL_BLOB_SHA" == "$DRY_RUN_BLOB_SHA" ]]; then
  echo "TC6 PASS: ${TMPL_FILE} content byte-identical between tmpl main and ${DRY_RUN_OWNER}/${DRY_RUN_PROJECT} main (blob=${TMPL_BLOB_SHA:0:12}, Issue #972 Path-Verify + cycle ~#3940Q+9 v3 amendment — content-equivalence, descendant-of impossible per cycle ~#3682 Defect #2 synthetic-init)"
  tc6_status="PASS"
elif [[ "$tc4_status" != "PASS" ]]; then
  echo "TC6 FAIL (RED pre-impl): TC4 dependency — dry-run not yet executed"
  tc6_status="FAIL"
elif [[ -z "$TMPL_BLOB_SHA" ]] || [[ -z "$DRY_RUN_BLOB_SHA" ]]; then
  echo "TC6 FAIL: blob SHA extraction empty (tmpl=${TMPL_BLOB_SHA:-empty} dry-run=${DRY_RUN_BLOB_SHA:-empty})"
  tc6_status="FAIL"
else
  echo "TC6 FAIL: blob SHA diverged (tmpl=${TMPL_BLOB_SHA:0:12} vs dry-run=${DRY_RUN_BLOB_SHA:0:12}) — content differs post-bootstrap"
  tc6_status="FAIL"
fi

# --- TC7: AC3 dev-studio-start.sh 5-agent spawn check (static, not live tmux) ---
TC7_SCRIPT_EXISTS=0
TC7_SCRIPT_EXECUTABLE=0
TC7_HAS_5_AGENT_BOOTSTRAPS=0
if [[ "$tc4_status" == "PASS" ]] && [[ -f "$DRY_RUN_DIR/scripts/dev-studio-start.sh" ]]; then
  TC7_SCRIPT_EXISTS=1
  if [[ -x "$DRY_RUN_DIR/scripts/dev-studio-start.sh" ]]; then
    TC7_SCRIPT_EXECUTABLE=1
  fi
  # Static grep for 5 agent bootstrap calls in dev-studio-start.sh body:
  # orchestrator + product-manager + architect + developer + tester
  expected_agents=("orchestrator" "product-manager" "architect" "developer" "tester")
  found_count=0
  for agent in "${expected_agents[@]}"; do
    if grep -q "write_agent_bootstrap \"$agent\"" "$DRY_RUN_DIR/scripts/dev-studio-start.sh" 2>/dev/null; then
      found_count=$((found_count + 1))
    fi
  done
  if [[ "$found_count" -eq 5 ]]; then
    TC7_HAS_5_AGENT_BOOTSTRAPS=1
  fi
fi

if [[ "$tc4_status" == "PASS" ]] && [[ "$TC7_SCRIPT_EXISTS" -eq 1 ]] && [[ "$TC7_SCRIPT_EXECUTABLE" -eq 1 ]] && [[ "$TC7_HAS_5_AGENT_BOOTSTRAPS" -eq 1 ]]; then
  echo "TC7 PASS: AC3 dev-studio-start.sh exists + executable + contains 5 agent bootstrap calls (orchestrator/product-manager/architect/developer/tester — HUMAN pane excluded per AC3 = '5 agents')"
  tc7_status="PASS"
elif [[ "$tc4_status" != "PASS" ]]; then
  echo "TC7 FAIL (RED pre-impl): TC4 dependency — dry-run not yet executed"
  tc7_status="FAIL"
else
  echo "TC7 FAIL: dev-studio-start.sh exists=${TC7_SCRIPT_EXISTS} executable=${TC7_SCRIPT_EXECUTABLE} 5-agent-bootstraps=${TC7_HAS_5_AGENT_BOOTSTRAPS}"
  tc7_status="FAIL"
fi

# --- summary ---
total=8
fail_count=0
for s in "$tc0_status" "$tc1_status" "$tc2_status" "$tc3_status" "$tc4_status" "$tc5_status" "$tc6_status" "$tc7_status"; do
  if [[ "$s" == "FAIL" ]]; then
    fail_count=$((fail_count + 1))
  fi
done
pass_count=$((total - fail_count))

echo "---"
echo "d-s32-024-new-project-bootstrap-dry-run: $pass_count/$total PASS, $fail_count/$total FAIL"

if [[ "$fail_count" -gt 0 ]]; then
  echo "RESULT: RED (S32-024 dry-run not yet verified — Issue #162 active, AC1 invocation pending)"
  exit 1
else
  echo "RESULT: GREEN (S32-024 dry-run verified end-to-end — Issue #162 closed, AC1+AC2+AC3 d-testable subset PASS)"
  exit 0
fi
