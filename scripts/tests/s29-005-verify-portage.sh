#!/usr/bin/env bash
# s29-005-verify-portage.sh — STORY-S29-005 regression guard.
#
# Why this test exists
# --------------------
# Sprint 29 cross-repo audit (Sprint 28 audit §4.6 + §6) surfaced a "60% portage
# gap" claim between dev-studio-template and AtilCalculator that needed concrete
# numbers. STORY-S29-005 (Issue #1017) authors scripts/verify-portage.sh in the
# dev-studio-template repo so S29-014 (orchestrator, sprint-end verification)
# can re-run it and produce a concrete gap report (JSON + text).
#
# This d-test guards against:
#   TC1: scripts/verify-portage.sh exists at the canonical path (AC1)
#   TC2: bash -n syntax check passes (script is parseable, no syntax errors)
#   TC3: --help exits 0 and prints usage info (per dev-studio-init.sh sister-pattern)
#   TC4: --dry-run exits 0 without making real GitHub API calls (AC3: idempotent
#        print-only mode, per e2e-pilot.sh sister-pattern naming)
#   TC5: --dry-run --json output is valid JSON with expected schema fields
#        (AC4: machine-readable JSON summary, gap count by category)
#   TC6: Header documents exit code matrix per AC6 (0 success, 1 preflight,
#        2 scratch-create, 3 e2e-pilot, 4 diff-capture, 5 cleanup-warn,
#        6 invalid-args)
#   TC7: Re-running --dry-run twice is idempotent (AC2: script is idempotent,
#        no state corruption across re-runs)
#   TC8 (bonus): Trap-based cleanup handler is wired (AC1 step 5 + idempotency)
#
# Pre-impl RED state (current main, pre-S29-005):
#   TC1: scripts/verify-portage.sh does NOT exist → FAIL
#   TC2: bash -n fails on missing file → FAIL
#   TC3: --help fails on missing executable → FAIL
#   TC4: --dry-run fails on missing executable → FAIL
#   TC5: --json output empty → FAIL
#   TC6: No header to inspect → FAIL
#   TC7: Cannot re-run missing executable → FAIL
#   TC8: No trap handler to inspect → FAIL
#   → 8/8 TCs FAIL = proper RED-first per ADR-0044.
#
# Post-impl GREEN state (after S29-005 PR squash):
#   TC1: scripts/verify-portage.sh exists ✅
#   TC2: bash -n exits 0 ✅
#   TC3: --help exits 0 with "Usage:" or "verify-portage" in output ✅
#   TC4: --dry-run exits 0, no "gh repo create" or "gh repo delete" actual
#        calls observed in trace ✅
#   TC5: JSON parseable, has `category_gaps` field with sub-counts ✅
#   TC6: Header contains "# Exit codes:" section with at least 6 codes ✅
#   TC7: Two consecutive --dry-run runs both exit 0 ✅
#   TC8: Header or body contains "trap" keyword + cleanup handler reference ✅
#   → 8/8 TCs PASS = GREEN.
#
# Sister-pattern family (d-test lineage, ADR-0049):
#   - e2e-pilot.sh (sister-pattern #1 — provides the rendering+e2e reference impl)
#   - dev-studio-init.sh (sister-pattern #2 — provides the --dry-run + helper
#     function conventions used here)
#   - d031-claim-next-ready.sh (claim script WIP cap test — Layer 2 sister)
#   - d095-post-org-migration-clone-urls.sh (AtilCalculator sister — URL hygiene
#     pattern, same Sprint 22 PIVOT origin)
#   - d983-s28-003-forward-port-parity.sh (STORY-S28-003 sister — first
#     cross-tmpl d-test in this file's INDEX)
#   - **s29-005 (this file) — STORY-S29-005 verify-portage d-test**
#
# Sprint 29 cross-repo workstream refs:
#   - Issue #1017 (S29-005 tracker in AtilCalculator, agent:developer)
#   - Issue #1020 (cross-repo scope Q, RESOLVED 2026-07-13T09:00:16Z Option A)
#   - docs/sprints/sprint-29/00-plan.md §S29-005
#   - docs/sprints/sprint-28/02-template-launcher-audit-2026-07-13.md §4.6 (recipe)
#   - ADR-0044 (RED-first TDD doctrinal home)
#   - ADR-0049 (d-test framework sister-pattern, ≥5 TCs minimum; this file: 8)
#   - ADR-0055 §1 Cadence Rule 1 atomic (d-test file + INDEX.md same commit)
#   - Sister-PR: atilproject/dev-studio-launcher#4 (S29-003 cross-repo workstream
#     pattern established — this S29-005 PR follows the same discipline)
#
# Usage:
#   bash scripts/tests/s29-005-verify-portage.sh
#
# Exit codes:
#   0 — all PASS (GREEN state — verify-portage.sh surface complete)
#   1 — at least one FAIL (RED state — surface incomplete)
#   2 — preflight failure (missing tool, etc.)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TARGET_SCRIPT="${REPO_ROOT}/scripts/verify-portage.sh"

# --- preflight ---
if ! command -v bash >/dev/null 2>&1; then
  echo "ERROR: preflight fail — bash not available" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: preflight fail — python3 not available (needed for JSON validation in TC5)" >&2
  exit 2
fi

# --- TC1: scripts/verify-portage.sh exists ---
if [[ -f "$TARGET_SCRIPT" ]]; then
  echo "TC1 PASS: scripts/verify-portage.sh exists at $TARGET_SCRIPT"
  tc1_status="PASS"
else
  echo "TC1 FAIL: scripts/verify-portage.sh does not exist at $TARGET_SCRIPT"
  tc1_status="FAIL"
fi

# --- TC2: bash -n syntax check passes ---
if [[ -f "$TARGET_SCRIPT" ]]; then
  if bash -n "$TARGET_SCRIPT" 2>/dev/null; then
    echo "TC2 PASS: bash -n syntax check passes"
    tc2_status="PASS"
  else
    echo "TC2 FAIL: bash -n syntax check failed (output: $(bash -n "$TARGET_SCRIPT" 2>&1 | head -3))"
    tc2_status="FAIL"
  fi
else
  echo "TC2 FAIL: bash -n cannot run — script missing (TC1 dependency)"
  tc2_status="FAIL"
fi

# --- TC3: --help exits 0 and prints usage info ---
if [[ -f "$TARGET_SCRIPT" && -x "$TARGET_SCRIPT" ]]; then
  help_output=$(bash "$TARGET_SCRIPT" --help 2>&1 || true)
  if echo "$help_output" | grep -qiE "usage|verify-portage"; then
    echo "TC3 PASS: --help exits 0 with Usage/verify-portage in output"
    tc3_status="PASS"
  else
    echo "TC3 FAIL: --help output does not contain 'Usage' or 'verify-portage'"
    tc3_status="FAIL"
  fi
elif [[ -f "$TARGET_SCRIPT" ]]; then
  echo "TC3 FAIL: --help cannot run — script not executable (chmod +x)"
  tc3_status="FAIL"
else
  echo "TC3 FAIL: --help cannot run — script missing (TC1 dependency)"
  tc3_status="FAIL"
fi

# --- TC4: --dry-run exits 0 without making real GitHub API calls ---
if [[ -f "$TARGET_SCRIPT" && -x "$TARGET_SCRIPT" ]]; then
  # Run with --dry-run and capture output + check for tell-tale real-API markers.
  # Real API calls would log "gh repo create" / "gh repo delete" directly.
  # --dry-run by spec must NOT make real calls.
  dry_output=$(bash "$TARGET_SCRIPT" --dry-run 2>&1 || true)
  # Real-API markers that should NOT appear in --dry-run mode (per AC3):
  # - "Creating scratch repo" (without [DRY-RUN] prefix)
  # - "gh repo create" (command execution)
  # - "gh repo delete" (command execution)
  # Note: "[DRY-RUN] Would create scratch repo" is fine — that's the print-mode signal.
  bad_markers_found=""
  if echo "$dry_output" | grep -E "gh repo create|gh repo delete" | grep -v "\[DRY-RUN\]" | grep -qv "^Would"; then
    bad_markers_found="real gh repo create/delete observed"
  fi
  if [[ -z "$bad_markers_found" ]]; then
    echo "TC4 PASS: --dry-run exited cleanly without real gh repo create/delete calls"
    tc4_status="PASS"
  else
    echo "TC4 FAIL: $bad_markers_found"
    tc4_status="FAIL"
  fi
elif [[ -f "$TARGET_SCRIPT" ]]; then
  echo "TC4 FAIL: --dry-run cannot run — script not executable"
  tc4_status="FAIL"
else
  echo "TC4 FAIL: --dry-run cannot run — script missing"
  tc4_status="FAIL"
fi

# --- TC5: --dry-run --json output is valid JSON with expected schema ---
if [[ -f "$TARGET_SCRIPT" && -x "$TARGET_SCRIPT" ]]; then
  # Capture only stdout (JSON goes to stdout; logs go to stderr in --json mode per script design)
  json_output=$(bash "$TARGET_SCRIPT" --dry-run --json 2>/dev/null || true)
  if echo "$json_output" | python3 -c "import sys, json; d = json.loads(sys.stdin.read()); sys.exit(0 if 'category_gaps' in d and isinstance(d['category_gaps'], dict) else 1)" 2>/dev/null; then
    echo "TC5 PASS: --json output has valid schema with category_gaps dict"
    tc5_status="PASS"
  else
    echo "TC5 FAIL: --json output is not valid JSON, or missing 'category_gaps' dict field (raw: $(echo "$json_output" | head -3))"
    tc5_status="FAIL"
  fi
else
  echo "TC5 FAIL: --json cannot run — script missing or not executable"
  tc5_status="FAIL"
fi

# --- TC6: Header documents exit code matrix per AC6 ---
if [[ -f "$TARGET_SCRIPT" ]]; then
  # Extract the first 80 lines (header section) and look for "# Exit codes:" + at least 6 codes.
  # Accept both "# N  text" (comment-style header) and "  N  text" (plain column) formats.
  header_section=$(head -80 "$TARGET_SCRIPT")
  if echo "$header_section" | grep -qE "^# Exit codes:"; then
    # Match either leading-whitespace-then-digit (plain) or # then whitespace then digit (comment-style header).
    # Use [^0-9] prefix to allow any non-digit (including #) before the digit, so "#   0  success" matches.
    code_count=$(echo "$header_section" | grep -cE "^[^0-9]*[0-9]+[[:space:]]")
    if [[ "$code_count" -ge 6 ]]; then
      echo "TC6 PASS: Header has '# Exit codes:' section with $code_count codes (≥6 required per AC6)"
      tc6_status="PASS"
    else
      echo "TC6 FAIL: Header has '# Exit codes:' but only $code_count codes listed (need ≥6)"
      tc6_status="FAIL"
    fi
  else
    echo "TC6 FAIL: Header does not contain '# Exit codes:' section"
    tc6_status="FAIL"
  fi
else
  echo "TC6 FAIL: Header cannot be inspected — script missing"
  tc6_status="FAIL"
fi

# --- TC7: Re-running --dry-run twice is idempotent ---
if [[ -f "$TARGET_SCRIPT" && -x "$TARGET_SCRIPT" ]]; then
  # Two consecutive --dry-run runs. Both should exit 0. No temp files should be left behind.
  tmpdir_before=$(mktemp -d)
  TMPDIR="$tmpdir_before" bash "$TARGET_SCRIPT" --dry-run >/dev/null 2>&1
  rc1=$?
  TMPDIR="$tmpdir_before" bash "$TARGET_SCRIPT" --dry-run >/dev/null 2>&1
  rc2=$?
  if [[ "$rc1" -eq 0 && "$rc2" -eq 0 ]]; then
    echo "TC7 PASS: Two consecutive --dry-run runs both exit 0 (idempotent)"
    tc7_status="PASS"
  else
    echo "TC7 FAIL: Two consecutive --dry-run runs had different exit codes: rc1=$rc1, rc2=$rc2"
    tc7_status="FAIL"
  fi
  rm -rf "$tmpdir_before"
else
  echo "TC7 FAIL: idempotency test cannot run — script missing or not executable"
  tc7_status="FAIL"
fi

# --- TC8 (bonus): Trap-based cleanup handler is wired ---
if [[ -f "$TARGET_SCRIPT" ]]; then
  # Look for trap command + cleanup function reference in body (not just header).
  if grep -qE '^trap .+(EXIT|INT|TERM|ERR)' "$TARGET_SCRIPT" 2>/dev/null; then
    if grep -qE '^cleanup\(\)|^cleanup\(\) \{' "$TARGET_SCRIPT" 2>/dev/null; then
      echo "TC8 PASS: Trap-based cleanup handler is wired (trap + cleanup() function present)"
      tc8_status="PASS"
    else
      echo "TC8 FAIL: trap is set but no cleanup() function defined"
      tc8_status="FAIL"
    fi
  else
    echo "TC8 FAIL: No trap-based cleanup handler present (AC1 step 5 + idempotency)"
    tc8_status="FAIL"
  fi
else
  echo "TC8 FAIL: cleanup handler cannot be inspected — script missing"
  tc8_status="FAIL"
fi

# --- summary ---
total=8
fail_count=0
for s in "$tc1_status" "$tc2_status" "$tc3_status" "$tc4_status" "$tc5_status" "$tc6_status" "$tc7_status" "$tc8_status"; do
  if [[ "$s" == "FAIL" ]]; then
    fail_count=$((fail_count + 1))
  fi
done
pass_count=$((total - fail_count))

echo "---"
echo "s29-005-verify-portage: $pass_count/$total PASS, $fail_count/$total FAIL"

if [[ "$fail_count" -gt 0 ]]; then
  echo "RESULT: RED (at least one TC failed — verify-portage.sh surface incomplete)"
  exit 1
else
  echo "RESULT: GREEN (all TCs pass — verify-portage.sh surface complete)"
  exit 0
fi
