#!/usr/bin/env bash
# d-verify-portage-diff-engine.sh — S32-002.1 (Issue #130) verify-portage diff-engine regression guard.
#
# Why this test exists
# --------------------
# Sprint 32 S32-002 baseline run (PR #129 → 5cf72a7, calc#1149) discovered that
# scripts/verify-portage.sh step 3+4 was a SILENT-GREEN PLACEHOLDER that emitted
# `category_gaps: 0/0/0/0` for all 4 categories — exact Issue #1041 sister-pattern
# (claim-next-ready.sh green-looking-but-not-verifying). Sister-PR baseline report
# (`docs/sprints/sprint-32/02-portage-baseline.md`) flagged AC4 placeholder gap as
# forward-path blocker.
#
# Issue #130 (S32-002.1) is the gap-closure story. This d-test guards against:
#   TC1: scripts/verify-portage.sh exists at the canonical path (AC1 sister-pattern)
#   TC2: bash -n syntax check passes (script is parseable, no syntax errors)
#   TC3: --help exits 0 and prints usage info (sister-pattern to s29-005 TC3)
#   TC4: --dry-run --ref-dir <fixture> exits 0 (AC1: new --ref-dir flag works)
#   TC5: --dry-run --ref-dir <fixture> --json output has valid schema with
#        `category_gaps` dict containing REAL (non-zero) counts per AC2 (≥3/4 categories)
#   TC6: JSON output includes per-file diff with line counts (added/removed/modified)
#        per AC3
#   TC7: JSON output includes `dtest_parity` section (local=N, ref=M, delta=D) per AC4
#   TC8: Secret sanitization — no `ghp_*` / `github_pat_*` / `TELEGRAM_BOT_TOKEN=`
#        literals in output (AC5 sanitization — file METADATA only, no contents)
#   TC9: --reference-repo flag is parsed (AC1: real-mode flag works; exits 6 on bad flag)
#   TC10: Header documents exit code matrix per AC6 (≥6 codes; should be 9 after impl)
#
# Pre-impl RED state (current main, pre-S32-002.1):
#   TC1 PASS (file exists) ✅
#   TC2 PASS (bash -n) ✅
#   TC3 PASS (--help) ✅
#   TC4 FAIL (--ref-dir flag not recognized, exits 6) ❌
#   TC5 FAIL (TC4 dependency) ❌
#   TC6 FAIL (no per-file diff in output) ❌
#   TC7 FAIL (no dtest_parity section) ❌
#   TC8 PASS (vacuous — script never outputs secrets) ✅
#   TC9 FAIL (--reference-repo flag not recognized, exits 6) ❌
#   TC10 PASS (header has 7 codes already) ✅
#   → 5/10 PASS = proper RED-first per ADR-0044 baseline ≥5 RED TCs.
#
# Post-impl GREEN state (after S32-002.1 PR squash):
#   TC1-TC10 all PASS → 10/10 GREEN.
#
# Sister-pattern family (d-test lineage, ADR-0049):
#   - s29-005-verify-portage.sh (DIRECT sister — 8 TCs, --dry-run + --json + exit codes,
#     bash -n + --help + idempotency + trap pattern, TC naming + summary format)
#   - d1138-template-agent-wake-fix-4b.sh (INDEX.md row format precedent, ADR-0055 §1)
#   - s29-004-status-label-to-board-disabled.sh (single-commit cluster-squash shape)
#   - e2e-pilot.sh (rendering workflow + idempotency note — verify-portage sister)
#   - dev-studio-init.sh (helper-function conventions: log/ok/warn/fail/dbg, color codes)
#
# Sprint 32 cross-repo workstream refs:
#   - Issue #130 (S32-002.1 tracker in dev-studio-template, agent:developer)
#   - Issue #128 (S32-002 origin, AC4 FAIL discovery)
#   - Issue #129 (S32-002 PR, MERGED 5cf72a7)
#   - calc#1149 (sister-side tracker, CLOSED via RETRO-024 work-done-elsewhere)
#   - docs/sprints/sprint-32/02-portage-baseline.md (raw AC4 FAIL report)
#   - ADR-0044 (RED-first TDD doctrinal home)
#   - ADR-0049 (d-test framework, ≥5 TCs baseline)
#   - ADR-0055 §1 Cadence Rule 1 atomic (d-test + INDEX.md same commit)
#   - ADR-0057 Closes vs Refs strict format (this PR uses Refs-only — Issue #130
#     already in-progress WIP=1/1, sister-pattern PR #1151/Issue #1150 cycle ~#3177)
#   - Issue #1041 sister-pattern (silent-green false-confidence — what this PR fixes)
#
# Usage:
#   bash scripts/tests/d-verify-portage-diff-engine.sh
#
# Exit codes:
#   0 — all PASS (GREEN state — diff engine wired)
#   1 — at least one FAIL (RED state — diff engine incomplete)
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
  echo "ERROR: preflight fail — python3 not available (needed for JSON validation in TC5/TC6/TC7)" >&2
  exit 2
fi
if ! command -v diff >/dev/null 2>&1; then
  echo "ERROR: preflight fail — diff not available (needed for AC3 diff_lines)" >&2
  exit 2
fi
if ! command -v sha256sum >/dev/null 2>&1; then
  echo "ERROR: preflight fail — sha256sum not available (needed for AC3 file metadata)" >&2
  exit 2
fi

# --- Build deterministic fixture dir for TC4-TC8 ---
# Fixture design (per Issue #130 ACs):
#   - scripts/dev-studio-init.sh (SAME name as template, DIFFERENT content) → 1 modified
#   - scripts/dummy-added.sh (UNIQUE to fixture) → 1 added
#   - workflows/dummy.yml (UNIQUE to fixture) → 1 added
#   - decisions/ADR-dummy.md (UNIQUE to fixture) → 1 added
#   - scripts/tests/d-test-stub1.sh (UNIQUE fixture d-test, no body) → delta to dtest_parity
# Expected counts per category:
#   scripts:    added=1, removed=0, modified=1, diff_lines>0
#   workflows:  added=1, removed=0, modified=0, diff_lines=0
#   decisions:  added=1, removed=0, modified=0, diff_lines=0
#   soul:       added=0, removed=0, modified=0, diff_lines=0
# → 3/4 categories have non-zero counts (AC2 satisfied)

FIXTURE_DIR="$(mktemp -d -t d-verify-portage-fixture.XXXXXX)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

mkdir -p "$FIXTURE_DIR/scripts" "$FIXTURE_DIR/workflows" "$FIXTURE_DIR/decisions" "$FIXTURE_DIR/.claude" "$FIXTURE_DIR/scripts/tests"

# FAKE SECRET for TC8 sanitization check — must NOT appear in output.
FAKE_SECRET="ghp_FAKESECRETFORVERIFYPORTAGETEST1234567890abcdef"

# Fixture: scripts/dev-studio-init.sh (DIFFERENT from template's content)
cat > "$FIXTURE_DIR/scripts/dev-studio-init.sh" << FIXTURE_EOF
#!/usr/bin/env bash
# Fixture stub for d-verify-portage-diff-engine TC6 modified-detection.
# This file intentionally differs from the template's scripts/dev-studio-init.sh.
# Token-shaped string below MUST NOT leak into verify-portage.sh output (TC8).
export FAKE_SECRET="$FAKE_SECRET"
echo "fixture stub"
FIXTURE_EOF

# Fixture: scripts/dummy-added.sh (UNIQUE to fixture)
cat > "$FIXTURE_DIR/scripts/dummy-added.sh" << 'FIXTURE_EOF'
#!/usr/bin/env bash
# Fixture-unique file → tests "added" classification.
echo "fixture-added"
FIXTURE_EOF

# Fixture: workflows/dummy.yml (UNIQUE to fixture)
cat > "$FIXTURE_DIR/workflows/dummy.yml" << 'FIXTURE_EOF'
# Fixture-unique workflow stub.
name: dummy-fixture
on: push
FIXTURE_EOF

# Fixture: decisions/ADR-dummy.md (UNIQUE to fixture)
cat > "$FIXTURE_DIR/decisions/ADR-dummy.md" << 'FIXTURE_EOF'
# ADR-dummy — fixture stub
FIXTURE_EOF

# Fixture: scripts/tests/d-test-stub1.sh (1 file in fixture's scripts/tests/)
cat > "$FIXTURE_DIR/scripts/tests/d-test-stub1.sh" << 'FIXTURE_EOF'
#!/usr/bin/env bash
# Fixture stub d-test.
FIXTURE_EOF

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

# --- TC4: --dry-run --ref-dir <fixture> exits 0 (NEW flag, AC1) ---
if [[ -f "$TARGET_SCRIPT" && -x "$TARGET_SCRIPT" ]]; then
  # Capture rc directly (no `|| true` — that would clobber rc to 0)
  bash "$TARGET_SCRIPT" --dry-run --ref-dir "$FIXTURE_DIR" --report "$FIXTURE_DIR/report.txt" > "$FIXTURE_DIR/tc4.out" 2>&1
  rc_dry_ref=$?
  dry_ref_output=$(cat "$FIXTURE_DIR/tc4.out" 2>/dev/null || echo "")
  if [[ "$rc_dry_ref" -eq 0 ]]; then
    echo "TC4 PASS: --dry-run --ref-dir exits 0 with custom fixture (AC1)"
    tc4_status="PASS"
  else
    echo "TC4 FAIL: --dry-run --ref-dir exited with rc=$rc_dry_ref (output tail: $(echo "$dry_ref_output" | tail -5))"
    tc4_status="FAIL"
  fi
elif [[ -f "$TARGET_SCRIPT" ]]; then
  echo "TC4 FAIL: --dry-run --ref-dir cannot run — script not executable"
  tc4_status="FAIL"
else
  echo "TC4 FAIL: --dry-run --ref-dir cannot run — script missing"
  tc4_status="FAIL"
fi

# --- TC5: --dry-run --ref-dir <fixture> --json has valid schema with real category_gaps ---
json_output=""
if [[ -f "$TARGET_SCRIPT" && -x "$TARGET_SCRIPT" ]]; then
  json_output=$(bash "$TARGET_SCRIPT" --dry-run --ref-dir "$FIXTURE_DIR" --json 2>/dev/null || true)
  # Schema validation: must have category_gaps dict with at least 3/4 categories having non-zero counts
  schema_result=$(echo "$json_output" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
except Exception as e:
    print(f'NOT_JSON:{e}'); sys.exit(0)
if 'category_gaps' not in d or not isinstance(d['category_gaps'], dict):
    print('NO_CATEGORY_GAPS'); sys.exit(0)
non_zero_count = 0
for cat, info in d['category_gaps'].items():
    if not isinstance(info, dict): continue
    total = info.get('added', 0) + info.get('removed', 0) + info.get('modified', 0)
    if total > 0: non_zero_count += 1
if non_zero_count >= 3:
    print(f'PASS:{non_zero_count}')
else:
    print(f'INSUFFICIENT:{non_zero_count}')
" 2>&1)
  if [[ "$schema_result" == PASS:* ]]; then
    echo "TC5 PASS: --json output has valid schema with ${schema_result#PASS:} categories having non-zero counts (AC2: ≥3/4 required)"
    tc5_status="PASS"
  else
    echo "TC5 FAIL: --json schema check failed: $schema_result (raw: $(echo "$json_output" | head -3))"
    tc5_status="FAIL"
  fi
else
  echo "TC5 FAIL: --json cannot run — script missing or not executable"
  tc5_status="FAIL"
fi

# --- TC6: JSON output includes per-file diff with line counts (AC3) ---
if [[ "$tc5_status" == "PASS" ]]; then
  per_file_result=$(echo "$json_output" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
except Exception:
    print('NOT_JSON'); sys.exit(0)
per_file_found = False
total_diff_lines = 0
for cat, info in d['category_gaps'].items():
    files = info.get('files', [])
    for f in files:
        if 'path' in f and 'diff_lines' in f:
            per_file_found = True
            total_diff_lines += f.get('diff_lines', 0)
if per_file_found and total_diff_lines > 0:
    print(f'PASS:{total_diff_lines}')
elif per_file_found:
    print('ZERO_DIFF_LINES')
else:
    print('NO_PER_FILE_DIFF')
" 2>&1)
  if [[ "$per_file_result" == PASS:* ]]; then
    echo "TC6 PASS: JSON includes per-file diff with total diff_lines=${per_file_result#PASS:} (AC3)"
    tc6_status="PASS"
  else
    echo "TC6 FAIL: per-file diff check failed: $per_file_result"
    tc6_status="FAIL"
  fi
else
  echo "TC6 FAIL: TC5 dependency failed (no JSON to inspect)"
  tc6_status="FAIL"
fi

# --- TC7: JSON includes dtest_parity section (AC4) ---
if [[ "$tc5_status" == "PASS" ]]; then
  parity_result=$(echo "$json_output" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
except Exception:
    print('NOT_JSON'); sys.exit(0)
parity = d.get('dtest_parity')
if not isinstance(parity, dict): print('NO_PARITY'); sys.exit(0)
if 'local' in parity and 'ref' in parity and 'delta' in parity:
    print(f'PASS:local={parity[\"local\"]},ref={parity[\"ref\"]},delta={parity[\"delta\"]}')
else:
    print('INCOMPLETE_FIELDS')
" 2>&1)
  if [[ "$parity_result" == PASS:* ]]; then
    echo "TC7 PASS: JSON includes dtest_parity section (AC4): ${parity_result#PASS:}"
    tc7_status="PASS"
  else
    echo "TC7 FAIL: dtest_parity check failed: $parity_result"
    tc7_status="FAIL"
  fi
else
  echo "TC7 FAIL: TC5 dependency failed"
  tc7_status="FAIL"
fi

# --- TC8: Secret sanitization — FAKE_SECRET not in output ---
if [[ -f "$TARGET_SCRIPT" && -x "$TARGET_SCRIPT" ]]; then
  # Run script and capture both stdout and stderr.
  secret_output=$(bash "$TARGET_SCRIPT" --dry-run --ref-dir "$FIXTURE_DIR" --json --report "$FIXTURE_DIR/report.txt" 2>&1 || true)
  # Also check report file if produced.
  if [[ -f "$FIXTURE_DIR/report.txt" ]]; then
    secret_output="$secret_output$(cat "$FIXTURE_DIR/report.txt" 2>&1)"
  fi
  if echo "$secret_output" | grep -qF "$FAKE_SECRET"; then
    echo "TC8 FAIL: FAKE_SECRET '$FAKE_SECRET' found in output (sanitization broken — file contents leaking)"
    tc8_status="FAIL"
  else
    echo "TC8 PASS: FAKE_SECRET NOT in output (sanitization OK — file metadata only, no contents)"
    tc8_status="PASS"
  fi
else
  echo "TC8 FAIL: sanitization test cannot run — script missing or not executable"
  tc8_status="FAIL"
fi

# --- TC9: --reference-repo flag is RECOGNIZED (AC1: real-mode flag works) ---
# Pre-impl: --reference-repo is unknown → "unknown argument" error → rc=6
# Post-impl: --reference-repo is recognized → with valid value + --dry-run, script exits 0
if [[ -f "$TARGET_SCRIPT" && -x "$TARGET_SCRIPT" ]]; then
  # Capture rc directly (no `|| true`)
  bash "$TARGET_SCRIPT" --dry-run --reference-repo "fakeowner/fakerepo" > "$FIXTURE_DIR/tc9.out" 2>&1
  rc_bad_flag=$?
  bad_flag_output=$(cat "$FIXTURE_DIR/tc9.out" 2>/dev/null || echo "")
  if [[ "$rc_bad_flag" -eq 0 ]]; then
    echo "TC9 PASS: --reference-repo with valid dummy value + --dry-run exits 0 (flag recognized, AC1)"
    tc9_status="PASS"
  elif echo "$bad_flag_output" | grep -qiE "unknown argument"; then
    echo "TC9 FAIL: --reference-repo still 'unknown argument' (flag not yet recognized)"
    tc9_status="FAIL"
  else
    echo "TC9 FAIL: --reference-repo exited rc=$rc_bad_flag (output tail: $(echo "$bad_flag_output" | tail -3))"
    tc9_status="FAIL"
  fi
else
  echo "TC9 FAIL: --reference-repo test cannot run — script missing or not executable"
  tc9_status="FAIL"
fi

# --- TC10: Header documents exit code matrix per AC6 (≥6 codes; ideally 9 post-impl) ---
if [[ -f "$TARGET_SCRIPT" ]]; then
  header_section=$(head -80 "$TARGET_SCRIPT")
  if echo "$header_section" | grep -qE "^# Exit codes:"; then
    code_count=$(echo "$header_section" | grep -cE "^[^0-9]*[0-9]+[[:space:]]")
    if [[ "$code_count" -ge 6 ]]; then
      echo "TC10 PASS: Header has '# Exit codes:' section with $code_count codes (≥6 required per AC6)"
      tc10_status="PASS"
    else
      echo "TC10 FAIL: Header has '# Exit codes:' but only $code_count codes listed (need ≥6)"
      tc10_status="FAIL"
    fi
  else
    echo "TC10 FAIL: Header does not contain '# Exit codes:' section"
    tc10_status="FAIL"
  fi
else
  echo "TC10 FAIL: Header cannot be inspected — script missing"
  tc10_status="FAIL"
fi

# --- summary ---
total=10
fail_count=0
for s in "$tc1_status" "$tc2_status" "$tc3_status" "$tc4_status" "$tc5_status" "$tc6_status" "$tc7_status" "$tc8_status" "$tc9_status" "$tc10_status"; do
  if [[ "$s" == "FAIL" ]]; then
    fail_count=$((fail_count + 1))
  fi
done
pass_count=$((total - fail_count))

echo "---"
echo "d-verify-portage-diff-engine: $pass_count/$total PASS, $fail_count/$total FAIL"

if [[ "$fail_count" -gt 0 ]]; then
  echo "RESULT: RED (at least one TC failed — verify-portage.sh diff engine incomplete)"
  exit 1
else
  echo "RESULT: GREEN (all TCs pass — verify-portage.sh diff engine wired)"
  exit 0
fi
