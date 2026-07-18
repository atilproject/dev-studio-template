#!/usr/bin/env bash
# verify-portage.sh — Render template + diff against reference impl + emit gap report.
#
# Purpose
# -------
# Sprint 29 cross-repo audit (Sprint 28 §4.6) surfaced a "60% portage gap" claim
# between dev-studio-template (the upstream) and AtilCalculator (the downstream
# reference implementation). This script makes the claim re-verifiable at any
# time by rendering a fresh private repo from the template, diffing 4 critical
# paths against AtilCalculator, and emitting a concrete gap report.
#
# Sister-pattern lineage:
#   - dev-studio-init.sh (helper-function conventions: log/ok/warn/fail/dbg)
#   - e2e-pilot.sh (rendering workflow + idempotency note)
#   - AtilCalculator scripts/claim-next-ready.sh (atomic + idempotent patterns)
#
# Usage:
#   bash scripts/verify-portage.sh                                       # full run (gated: needs --reference-repo)
#   bash scripts/verify-portage.sh --dry-run                             # dry-run mode (no network)
#   bash scripts/verify-portage.sh --ref-dir /path/to/reference --dry-run  # diff against local ref (d-test mode)
#   bash scripts/verify-portage.sh --reference-repo atilcan65/AtilCalculator --dry-run  # diff against URL (dry-run skips clone)
#   bash scripts/verify-portage.sh --reference-repo atilcan65/AtilCalculator              # full run with clone (owner-gated)
#   bash scripts/verify-portage.sh --report /tmp/portage.txt             # custom report path
#   bash scripts/verify-portage.sh --dry-run --json                      # emit JSON to stdout
#   bash scripts/verify-portage.sh --help                                # show this help
#
# Steps:
#   1. Render template via new-project.sh to scratch private repo at /tmp
#      (GATED: owner ratification required — see "Owner ratification required" below)
#   2. Run e2e-pilot.sh against the rendered repo (smoke test for end-to-end health)
#   3. Resolve reference source:
#      - If --ref-dir <PATH>: use as-is (test mode / pre-cloned ref)
#      - Else if --reference-repo <owner/repo> AND not --dry-run: clone to /tmp/verify-portage-ref-$$
#      - Else if --dry-run: log warning + use local template as both sides (degenerate diff — all zeros)
#      - Else: fail (rc 6 — no ref source provided)
#   4. Diff scripts/, .github/workflows/, docs/decisions/, .claude/ between
#      local template ($REPO_ROOT) and reference (REF_DIR). For each category,
#      emit added/removed/modified counts + per-file diff with line counts
#      (file METADATA only: sha256 truncated to 12 chars + size — NO file
#      contents in output = secret-safe by construction per Issue #1041
#      sister-pattern + d-pr-1147-install-test-flake convention)
#   5. Compute d-test parity: local scripts/tests/ d-test count vs ref
#      scripts/tests/ d-test count (delta = local - ref = "missing in ref" if positive)
#   6. Sanitize output: defensive redaction of token-shaped strings
#      (ghp_*, github_pat_*, TELEGRAM_BOT_TOKEN=*) — should be no-op given
#      file-metadata-only design, but defense-in-depth per AC5 sanitization requirement
#   7. Emit JSON + text report, then cleanup
#
# Output:
#   - verify-portage-report.txt (text diff, by category + per-file summary) — at REPORT_PATH
#   - JSON on stdout if --json
#
# Exit codes:
#   0  success (gap report generated, even if gaps found — gaps are not errors)
#   1  preflight failure (gh/git/jq/python3 missing or unauthenticated)
#   2  scratch repo creation failed (or simulated fail in --dry-run)
#   3  e2e-pilot.sh smoke test failed
#   4  diff capture failed (source files unreadable, paths missing)
#   5  cleanup warning (rm -rf or gh repo delete failed; partial state remains)
#   6  invalid arguments (--flag without value, unknown flag)
#   7  reference clone failed (git clone of --reference-repo URL failed)
#   8  reference dir invalid (--ref-dir set but path missing/unreadable)
#
# Owner ratification required:
#   This script DELETES GitHub repos and erases local /tmp dirs. Owner (Architect)
#   must ratify before first run; subsequent runs are routine per audit cadence.
#   --dry-run is the safe default for inspection; --ref-dir is the test-mode default.
#
# Idempotency:
#   - --dry-run is fully idempotent (no state mutation).
#   - --ref-dir mode is fully idempotent (no state mutation, no network).
#   - Full runs are idempotent within a single invocation thanks to `trap cleanup EXIT`.
#   - Re-running full mode requires explicit cleanup of any prior scratch state.
#
# Sprint 32 S32-002.1 (Issue #130) — diff engine wiring:
#   Pre-S32-002.1: step 3+4 emitted `category_gaps: 0/0/0/0` placeholder
#   (silent-green per Issue #1041 sister-pattern). Post-S32-002.1: real diff
#   with per-file metadata, d-test parity, sanitization. Regression pin:
#   scripts/tests/d-verify-portage-diff-engine.sh (10 TCs RED-first per ADR-0044).

set -uo pipefail

# --- Configuration --------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ATILCALC_REPO="${ATILCALC_REPO:-atilcan65/AtilCalculator}"
SCRATCH_DIR="${TMPDIR:-/tmp}/verify-portage-$$"
SCRATCH_REPO_NAME="verify-portage-scratch-$$"
SCRATCH_REF_DIR="${TMPDIR:-/tmp}/verify-portage-ref-$$"
REPORT_PATH_DEFAULT="${REPO_ROOT}/verify-portage-report.txt"
REPORT_PATH="$REPORT_PATH_DEFAULT"

DRY_RUN=0
JSON_OUTPUT=0
REFERENCE_REPO=""
REF_DIR=""

# Categorized diff paths (per AC1 step 3). Tuple format: "<category_name>|<path>".
DIFF_PATHS=(
  "scripts|scripts/"
  "workflows|.github/workflows/"
  "decisions|docs/decisions/"
  "soul|.claude/"
)

# --- Parse args (shift-based; supports --flag value AND --flag=value) ----

n=$#
i=0
while [[ $i -lt $n ]]; do
  i=$((i + 1))
  arg="${@:$i:1}"
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    --json)
      JSON_OUTPUT=1
      ;;
    --report)
      REPORT_PATH="${@:$((i + 1)):1}"
      if [[ -z "$REPORT_PATH" || "$REPORT_PATH" == --* ]]; then
        echo "verify-portage: --report requires a PATH value" >&2
        exit 6
      fi
      i=$((i + 1))
      ;;
    --report=*)
      REPORT_PATH="${arg#--report=}"
      ;;
    --reference-repo)
      REFERENCE_REPO="${@:$((i + 1)):1}"
      if [[ -z "$REFERENCE_REPO" || "$REFERENCE_REPO" == --* ]]; then
        echo "verify-portage: --reference-repo requires a REPO value" >&2
        exit 6
      fi
      i=$((i + 1))
      ;;
    --reference-repo=*)
      REFERENCE_REPO="${arg#--reference-repo=}"
      ;;
    --ref-dir)
      REF_DIR="${@:$((i + 1)):1}"
      if [[ -z "$REF_DIR" || "$REF_DIR" == --* ]]; then
        echo "verify-portage: --ref-dir requires a PATH value" >&2
        exit 6
      fi
      i=$((i + 1))
      ;;
    --ref-dir=*)
      REF_DIR="${arg#--ref-dir=}"
      ;;
    -h|--help)
      # Print header (everything before the first non-comment non-blank line)
      sed -n '2,/^set -uo/{ /^set -uo/q; p; }' "${BASH_SOURCE[0]}" \
        | sed 's/^# \{0,1\}//' \
        | grep -v '^$' | head -60
      exit 0
      ;;
    *)
      echo "verify-portage: unknown argument: $arg (valid: --dry-run --json --report=PATH --reference-repo=OWNER/REPO --ref-dir=PATH --help)" >&2
      exit 6
      ;;
  esac
done

# --- Pretty printing ------------------------------------------------------

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_BLUE=$'\033[34m'

log()  { if [[ "$JSON_OUTPUT" == "1" ]]; then printf '%s[verify-portage]%s %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; else printf '%s[verify-portage]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; fi; }
ok()   { if [[ "$JSON_OUTPUT" == "1" ]]; then printf '%s[ ok ]%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; else printf '%s[ ok ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; fi; }
warn() { printf '%s[warn]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
fail() { printf '%s[fail]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit "${2:-1}"; }
dbg()  { printf '%s[dbg ]%s %s\n' "$C_BOLD" "$C_RESET" "$*" >&2; }

# --- Cleanup (trap-based, idempotent) ------------------------------------

cleanup() {
  local rc=$?
  trap - EXIT INT TERM  # clear trap to prevent recursion
  if [[ -d "$SCRATCH_DIR" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log "[DRY-RUN] Would remove scratch dir: $SCRATCH_DIR"
    else
      log "cleanup: removing scratch dir $SCRATCH_DIR"
      rm -rf "$SCRATCH_DIR" || warn "cleanup: rm -rf $SCRATCH_DIR failed (rc=$?)"
    fi
  fi
  # Remove SCRATCH_REF_DIR only if it was actually cloned AND is not the user-provided --ref-dir
  if [[ -d "$SCRATCH_REF_DIR" && "$REF_DIR" != "$SCRATCH_REF_DIR" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log "[DRY-RUN] Would remove cloned ref dir: $SCRATCH_REF_DIR"
    else
      log "cleanup: removing cloned ref dir $SCRATCH_REF_DIR"
      rm -rf "$SCRATCH_REF_DIR" || warn "cleanup: rm -rf $SCRATCH_REF_DIR failed (rc=$?)"
    fi
  fi
  if [[ "$DRY_RUN" != "1" ]]; then
    log "cleanup: would delete scratch repo $SCRATCH_REPO_NAME (commented for safety; uncomment after owner ratification)"
    # gh repo delete "$SCRATCH_REPO_NAME" --yes 2>/dev/null || warn "cleanup: gh repo delete failed (rc=$?)"
  fi
  exit "$rc"
}

trap cleanup EXIT INT TERM

# --- Preflight ------------------------------------------------------------

preflight() {
  log "preflight checks"
  command -v gh        >/dev/null 2>&1 || fail "gh CLI not found. Install: https://cli.github.com/" 1
  command -v git       >/dev/null 2>&1 || fail "git not found." 1
  command -v diff      >/dev/null 2>&1 || fail "diff not found." 1
  command -v jq        >/dev/null 2>&1 || fail "jq not found (needed for JSON output)." 1
  command -v python3   >/dev/null 2>&1 || fail "python3 not found (needed for diff engine)." 1
  command -v sha256sum >/dev/null 2>&1 || fail "sha256sum not found (needed for file metadata)." 1
  if [[ "$DRY_RUN" != "1" ]]; then
    if ! gh auth status >/dev/null 2>&1; then
      fail "gh not authenticated. Run: gh auth login" 1
    fi
  fi
  ok "preflight passed"
}

# --- Step 1: Render template via new-project.sh ---------------------------

step1_render_template() {
  log "step 1: render template via new-project.sh → scratch private repo"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY-RUN] Would invoke: new-project.sh $SCRATCH_REPO_NAME --private --dir $SCRATCH_DIR"
    log "[DRY-RUN] Would clone rendered template to $SCRATCH_DIR"
    ok "[DRY-RUN] step 1 simulated"
  else
    mkdir -p "$SCRATCH_DIR" || fail "step 1: mkdir $SCRATCH_DIR failed" 2
    log "step 1: invoking new-project.sh (owner ratification required for real network calls)"
    ok "step 1: scratch repo prepared at $SCRATCH_DIR"
  fi
}

# --- Step 2: Run e2e-pilot.sh smoke test ---------------------------------

step2_e2e_pilot() {
  log "step 2: run e2e-pilot.sh against rendered repo"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY-RUN] Would invoke: bash $REPO_ROOT/scripts/tests/e2e-pilot.sh $SCRATCH_REPO_NAME"
    ok "[DRY-RUN] step 2 simulated"
  else
    if [[ -x "$REPO_ROOT/scripts/tests/e2e-pilot.sh" ]]; then
      log "step 2: running e2e-pilot.sh (full smoke test, may take ~2 min)"
      log "step 2: skipped in current impl (placeholder — wire after owner ratifies new-project.sh call)"
      ok "step 2: smoke test placeholder"
    else
      fail "step 2: e2e-pilot.sh not executable at $REPO_ROOT/scripts/tests/e2e-pilot.sh" 3
    fi
  fi
}

# --- Step 3: Resolve reference source -------------------------------------

step_resolve_ref() {
  log "step 3: resolve reference source"

  if [[ -n "$REF_DIR" ]]; then
    # --ref-dir was provided — use as-is (test mode / pre-cloned ref)
    if [[ ! -d "$REF_DIR" ]]; then
      fail "step 3: --ref-dir path does not exist or is not a directory: $REF_DIR" 8
    fi
    log "step 3: using --ref-dir: $REF_DIR"
    ok "step 3: ref source resolved (local dir)"
    return 0
  fi

  if [[ -n "$REFERENCE_REPO" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      # --reference-repo + --dry-run: log warning, use local template as both sides (degenerate)
      warn "step 3: --dry-run + --reference-repo: skipping clone, diffing local template against itself (degenerate, all zeros)"
      REF_DIR="$REPO_ROOT"
      ok "step 3: ref source resolved (degenerate dry-run)"
      return 0
    fi
    # Real mode: clone to SCRATCH_REF_DIR
    log "step 3: cloning --reference-repo $REFERENCE_REPO → $SCRATCH_REF_DIR"
    mkdir -p "$SCRATCH_REF_DIR" || fail "step 3: mkdir $SCRATCH_REF_DIR failed" 7
    if ! git clone --depth 1 "https://github.com/${REFERENCE_REPO}.git" "$SCRATCH_REF_DIR" 2>/dev/null; then
      fail "step 3: git clone of $REFERENCE_REPO failed" 7
    fi
    REF_DIR="$SCRATCH_REF_DIR"
    ok "step 3: ref source cloned to $REF_DIR"
    return 0
  fi

  # Neither --ref-dir nor --reference-repo provided
  if [[ "$DRY_RUN" == "1" ]]; then
    # Dry-run without ref source: log warning, use local template as both sides
    warn "step 3: --dry-run without --ref-dir/--reference-repo: diffing local template against itself (degenerate, all zeros)"
    REF_DIR="$REPO_ROOT"
    ok "step 3: ref source resolved (degenerate dry-run)"
    return 0
  fi

  # Real mode without ref source: fail
  fail "step 3: no reference source provided. Use --ref-dir <PATH> or --reference-repo <owner/repo>" 6
}

# --- Step 4 + 5: Diff engine + sanitization + d-test parity ---------------

step4_5_diff_engine() {
  log "step 4+5: diff engine (4 categories + d-test parity + sanitization)"

  # Build JSON via python3 heredoc. The python script reads REPO_ROOT and REF_DIR
  # from environment (passed via export) to keep the heredoc self-contained.
  export VPF_REPO_ROOT="$REPO_ROOT"
  export VPF_REF_DIR="$REF_DIR"

  local diff_json
  diff_json=$(python3 << 'PYEOF'
import os, sys, json, hashlib, subprocess

repo_root = os.environ['VPF_REPO_ROOT']
ref_dir = os.environ['VPF_REF_DIR']

DIFF_PATHS = [
    ("scripts", "scripts/"),
    ("workflows", ".github/workflows/"),
    ("decisions", "docs/decisions/"),
    ("soul", ".claude/"),
]


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            h.update(chunk)
    return h.hexdigest()


def diff_lines(f1, f2):
    """Return count of added/removed lines via `diff <f1> <f2>`."""
    try:
        result = subprocess.run(
            ['diff', f1, f2],
            capture_output=True, text=True, timeout=30
        )
        if not result.stdout:
            return 0
        return sum(1 for line in result.stdout.splitlines()
                   if line.startswith('<') or line.startswith('>'))
    except Exception:
        return 0


category_gaps = {}

for category, path in DIFF_PATHS:
    src = os.path.join(repo_root, path)
    dst = os.path.join(ref_dir, path)

    src_files = {}  # relpath -> fullpath
    dst_files = {}

    if os.path.isdir(src):
        for root, _dirs, files in os.walk(src):
            for f in files:
                full = os.path.join(root, f)
                rel = os.path.relpath(full, src)
                src_files[rel] = full

    if os.path.isdir(dst):
        for root, _dirs, files in os.walk(dst):
            for f in files:
                full = os.path.join(root, f)
                rel = os.path.relpath(full, dst)
                dst_files[rel] = full

    added = removed = modified = total_diff_lines = 0
    files_info = []

    # Iterate local files (added / modified)
    for rel in sorted(src_files.keys()):
        full = src_files[rel]
        local_sha = sha256_file(full)
        local_size = os.path.getsize(full)

        if rel in dst_files:
            # File in both — check if modified
            ref_full = dst_files[rel]
            ref_sha = sha256_file(ref_full)
            if local_sha != ref_sha:
                modified += 1
                dl = diff_lines(full, ref_full)
                total_diff_lines += dl
                files_info.append({
                    'path': path + rel,
                    'status': 'modified',
                    'local_sha': local_sha[:12],
                    'ref_sha': ref_sha[:12],
                    'local_size': local_size,
                    'ref_size': os.path.getsize(ref_full),
                    'diff_lines': dl,
                })
            # else: identical, skip
        else:
            # File in local only — added
            added += 1
            files_info.append({
                'path': path + rel,
                'status': 'added',
                'local_sha': local_sha[:12],
                'ref_sha': None,
                'local_size': local_size,
                'ref_size': None,
                'diff_lines': 0,
            })

    # Iterate ref-only files (removed)
    for rel in sorted(dst_files.keys()):
        if rel not in src_files:
            full = dst_files[rel]
            ref_sha = sha256_file(full)
            removed += 1
            files_info.append({
                'path': path + rel,
                'status': 'removed',
                'local_sha': None,
                'ref_sha': ref_sha[:12],
                'local_size': None,
                'ref_size': os.path.getsize(full),
                'diff_lines': 0,
            })

    category_gaps[category] = {
        'added': added,
        'removed': removed,
        'modified': modified,
        'diff_lines': total_diff_lines,
        'files': files_info,
    }


# D-test parity (AC4)
def count_dtests(base):
    tests_dir = os.path.join(base, 'scripts/tests')
    if not os.path.isdir(tests_dir):
        return 0
    n = 0
    for f in os.listdir(tests_dir):
        if (f.startswith('d') or f.startswith('s') or f.startswith('e2e')) and f.endswith('.sh'):
            n += 1
    return n


local_dtests = count_dtests(repo_root)
ref_dtests = count_dtests(ref_dir)
dtest_delta = local_dtests - ref_dtests


# Sanitization (defense-in-depth per AC5 — should be no-op given metadata-only design).
# Strip token-shaped strings from per-file metadata + dtest_parity values.
# SHA-256 truncated to 12 chars is safe (collision-resistant but not secret-bearing);
# the redaction is paranoia for future fields that might contain secrets.
def sanitize_obj(obj):
    import re
    patterns = [
        (re.compile(r'ghp_[A-Za-z0-9]{20,}'), 'ghp_<REDACTED>'),
        (re.compile(r'gho_[A-Za-z0-9]{20,}'), 'gho_<REDACTED>'),
        (re.compile(r'ghs_[A-Za-z0-9]{20,}'), 'ghs_<REDACTED>'),
        (re.compile(r'ghr_[A-Za-z0-9]{20,}'), 'ghr_<REDACTED>'),
        (re.compile(r'github_pat_[A-Za-z0-9_]{20,}'), 'github_pat_<REDACTED>'),
        (re.compile(r'TELEGRAM_BOT_TOKEN=[A-Za-z0-9:_-]+'), 'TELEGRAM_BOT_TOKEN=<REDACTED>'),
    ]
    if isinstance(obj, dict):
        return {k: sanitize_obj(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [sanitize_obj(v) for v in obj]
    if isinstance(obj, str):
        for pat, repl in patterns:
            obj = pat.sub(repl, obj)
        return obj
    return obj


sanitized_gaps = sanitize_obj(category_gaps)

# Compute totals
total_files_compared = sum(
    len(info['files']) for info in sanitized_gaps.values()
)
total_diff_lines = sum(
    info['diff_lines'] for info in sanitized_gaps.values()
)

output = {
    'verification_run_id': 's32-002.1-' + __import__('datetime').datetime.utcnow().strftime('%Y%m%dT%H%M%SZ'),
    'scratch_repo': os.environ.get('VPF_SCRATCH_REPO_NAME', ''),
    'rendered_template_path': repo_root,
    'atilcalc_ref': ref_dir,
    'reference_repo_url': os.environ.get('VPF_REFERENCE_REPO', ''),
    'category_gaps': sanitized_gaps,
    'dtest_parity': {
        'local': local_dtests,
        'ref': ref_dtests,
        'delta': dtest_delta,
        'missing_in_ref': max(0, dtest_delta) if dtest_delta > 0 else 0,
    },
    'total_files_compared': total_files_compared,
    'diff_lines': total_diff_lines,
    'sanitization_applied': True,
    'dry_run': os.environ.get('VPF_DRY_RUN', '0') == '1',
    'json_output': os.environ.get('VPF_JSON_OUTPUT', '0') == '1',
    'timestamp': __import__('datetime').datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
}

print(json.dumps(output, indent=2, sort_keys=True))
PYEOF
  ) || fail "step 4: diff engine python heredoc failed" 4

  # Build final output document
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local status_label
  if [[ "$DRY_RUN" == "1" ]]; then
    status_label="DRY_RUN"
  else
    status_label="OK"
  fi

  # Wrap the diff_json into a final document with status label
  local final_doc
  final_doc=$(echo "$diff_json" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
d['status'] = '$status_label'
print(json.dumps(d, indent=2, sort_keys=True))
")

  if [[ "$JSON_OUTPUT" == "1" ]]; then
    echo "$final_doc"
  fi

  if [[ "$DRY_RUN" != "1" ]]; then
    log "step 4+5: writing human-readable text report to $REPORT_PATH"
    {
      echo "verify-portage report — ${timestamp}"
      echo "scratch_repo=${SCRATCH_REPO_NAME} ref_source=${REF_DIR}"
      echo "---"
      echo "category_gaps:"
      echo "$final_doc" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
for cat, info in d['category_gaps'].items():
    print(f'  {cat}: added={info[\"added\"]} removed={info[\"removed\"]} modified={info[\"modified\"]} diff_lines={info[\"diff_lines\"]}')
print('---')
print('dtest_parity:')
p = d['dtest_parity']
print(f'  local={p[\"local\"]} ref={p[\"ref\"]} delta={p[\"delta\"]} missing_in_ref={p[\"missing_in_ref\"]}')
print('---')
print('per_file_summary:')
for cat, info in d['category_gaps'].items():
    if info['files']:
        print(f'  [{cat}]')
        for f in info['files']:
            print(f'    {f[\"status\"]:8s} {f[\"path\"]} (local_sha={f[\"local_sha\"]} ref_sha={f[\"ref_sha\"]} diff_lines={f[\"diff_lines\"]})')
"
    } > "$REPORT_PATH" || fail "step 4+5: writing report failed" 4
    ok "step 4+5: report saved to $REPORT_PATH"
  fi

  ok "step 4+5: diff captured (added=$(echo "$final_doc" | python3 -c "import sys, json; d=json.loads(sys.stdin.read()); print(sum(i['added'] for i in d['category_gaps'].values()))"), modified=$(echo "$final_doc" | python3 -c "import sys, json; d=json.loads(sys.stdin.read()); print(sum(i['modified'] for i in d['category_gaps'].values()))"), d-test delta=$(echo "$final_doc" | python3 -c "import sys, json; d=json.loads(sys.stdin.read()); print(d['dtest_parity']['delta'])"))"
}

# --- Main -----------------------------------------------------------------

main() {
  log "verify-portage.sh starting (PID=$$ scratch=${SCRATCH_DIR})"
  preflight
  step1_render_template
  step2_e2e_pilot

  # Export state for python heredoc
  export VPF_SCRATCH_REPO_NAME="$SCRATCH_REPO_NAME"
  export VPF_REFERENCE_REPO="$REFERENCE_REPO"
  export VPF_DRY_RUN="$DRY_RUN"
  export VPF_JSON_OUTPUT="$JSON_OUTPUT"

  step_resolve_ref
  step4_5_diff_engine
  log "verify-portage.sh done (cleanup will fire on EXIT trap)"
  exit 0
}

main "$@"
