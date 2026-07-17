#!/usr/bin/env bash
# d0984-cli-arg-hygiene.sh — Sprint 29 W2, Issue #89 RED-first d-test
#
# Verifies that `scripts/dev-studio-start.sh` (the template's tmux bootstrap
# launcher) has been cleaned up to remove the obsolete `--agent "${role}"`
# argument from its heredoc, per Claude Code CLI 2.1.207 breaking change
# (--agent flag no longer accepts custom agent names from
# `.claude/agents/<role>.md`; identity is loaded via --append-system-prompt-file).
#
# Doctrinal contract (≥5 TCs baseline per ADR-0049 d-test framework):
#   TC0: bash -n syntactic self-check (preflight, PASS pre/post)
#   TC1: --agent "..." removed from dev-studio-start.sh source (issue #89 spec)
#   TC2: `claude --help` still lists --agent flag (regression detector — the CLI
#        didn't remove the flag, just custom-name match per Issue #88 / ADR-0102)
#   TC3: bootstrap-generated scripts/.tmux-bootstrap/<role>.sh (5 roles: orch/pm/
#        arch/dev/tester) contain NO `--agent ` token (issue #89 spec)
#   TC4: `bash -n scripts/.tmux-bootstrap/*.sh` syntax check passes for all 5
#        generated files (issue #89 spec — hygiene regression guard)
#   TC5: `--append-system-prompt-file` argument is still wired in the generated
#        `claude` invocation (issue #89 spec — positive regression check that
#        identity loading path is intact post-removal)
#
# Sister-pattern (≥3 per ADR-0049, 5 cited):
#   - d081-auto-verdict-by-hook.sh (template sister — INDEX.md row format +
#     tmpl-side d-test authoring conventions + 4-cat label discipline)
#   - d983-s28-003-forward-port-parity.sh (template sister — cross-tmpl
#     forward-port d-test pattern)
#   - d031-claim-next-ready.sh (calc sister — Layer 2 fake-gh factory for
#     isolated test env; sister-pattern for sourced-fixture isolation in TC3)
#   - d1042-template-agent-watch-line-294-repos-guard.sh (template sister —
#     same Sprint 29 W2 cadence, same template-side Issue #88 cluster scope)
#   - d1027-s29-016-template-pyproject-render.sh (template sister — same
#     TC0 preflight + Cadence Rule 1 INDEX.md attestation pattern in TC7/INDEX row)
#
# Why this d-test exists
# ----------------------
# Claude Code CLI 2.1.207 (2026-07-14 03:31 update, mtime verified) breaking
# change: --agent <role> no longer matches custom agent names defined in
# `.claude/agents/<role>.md`. When scripts/dev-studio-start.sh heredoc invokes
# `claude ... --agent "${role}" ...`, Claude errors with `--agent '<role>' not
# found` and all 5 tmux panes fall back to a plain shell — losing Claude Code
# identity loading entirely. ADR-0102 (Issue #88, PR #97 MERGED) codifies the
# fix: remove `--agent "${role}"` from the bootstrap heredoc; identity continues
# to load via `--append-system-prompt-file .claude/agents/${role}.md` (already
# wired, no change needed). This d-test guards the fix on the template side so
# future `new-project.sh` invocations ship bug-free.
#
# RED-first per ADR-0044 (RED-first TDD doctrinal home, calc-side) + ADR-0100
# (d-test convention, template-side doctrinal home) + ADR-0049 (d-test
# framework): pre-impl on current template main, TC1+TC3 fail (--agent "..."
# still present in source + generated bootstrap files); TC2+TC4+TC5 pass.
# Post-impl (when developer lands Issue #90 fix to dev-studio-start.sh heredoc):
# all 5 TCs GREEN.
#
# Cadence Rule 1 atomic per ADR-0055 §1: this d-test file + INDEX.md row land
# in same commit cluster per ADR-0059 cluster-squash. Phase A (d-test) MUST
# land BEFORE Phase B (impl Issue #90); both must land same merge-day as the
# calc-side d-test cluster for cross-repo parity per RETRO-023.
#
# Exit codes: 0 = all pass; 1 = at least one TC fail.
# Run: bash scripts/tests/d0984-cli-arg-hygiene.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEV_STUDIO_START="${REPO_ROOT}/scripts/dev-studio-start.sh"

# Colors (TTY-aware)
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; B=""; D=""
fi

PASS=0; FAIL=0
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

# ----------------------------------------------------------------------------
# TC0: bash -n syntactic self-check
# ----------------------------------------------------------------------------
section "TC0: bash -n syntactic self-check (preflight)"
if bash -n "$0" 2>/dev/null; then
  pass "test file syntactically valid (bash -n)"
else
  fail "bash -n self-check failed" "fix syntax errors in $0"
fi

# ----------------------------------------------------------------------------
# TC1: --agent "..." removed from dev-studio-start.sh source
# ----------------------------------------------------------------------------
section "TC1: --agent \"\${role}\" removed from dev-studio-start.sh source"
if [ -f "$DEV_STUDIO_START" ]; then
  # Use -- to terminate option parsing so the grep pattern starts cleanly.
  # Pattern: literal `--agent ` (with trailing space) anchored to avoid false
  # positives from any other `--agent` reference in comments/docs (per spec).
  agent_count=$(grep -c -- '--agent ' "$DEV_STUDIO_START" 2>/dev/null)
  agent_count="${agent_count:-0}"
  if [ "$agent_count" -eq 0 ]; then
    pass "dev-studio-start.sh contains 0 occurrences of --agent (post-fix)"
  else
    # Surface the offending line(s) for the developer to fix
    offending=$(grep -nE -- '--agent ' "$DEV_STUDIO_START" 2>/dev/null | head -3)
    fail "dev-studio-start.sh still contains --agent ($agent_count occurrences)" "expected 0 per Issue #89 + ADR-0102; offending lines: $offending — remove the --agent \"\${role}\" arg from the bootstrap heredoc (line ~149)"
  fi
else
  fail "dev-studio-start.sh absent" "Issue #89 spec — scripts/dev-studio-start.sh must exist at template root for the bootstrap launcher"
fi

# ----------------------------------------------------------------------------
# TC2: claude --help still lists --agent flag (regression detector)
# ----------------------------------------------------------------------------
section "TC2: claude --help still lists --agent flag (regression detector)"
if command -v claude >/dev/null 2>&1; then
  # Match `^  --agent ` (2-space indent + literal `--agent `) to anchor the
  # CLI's --agent line in the help output. Per ADR-0102 / Issue #88, CLI 2.1.207
  # removed custom-agent-name matching from --agent, but the flag itself is
  # still in claude --help (used for built-in agents). This regression detector
  # catches a scenario where someone "fixes" --agent by removing it entirely
  # from the CLI's argv surface, which would break the smoke-test path.
  help_agent_count=$(claude --help 2>&1 | grep -c '^  --agent ')
  help_agent_count="${help_agent_count:-0}"
  if [ "$help_agent_count" -ge 1 ]; then
    pass "claude --help still lists --agent flag ($help_agent_count match) — CLI argv surface intact"
  else
    fail "claude --help no longer lists --agent flag" "expected at least 1 line matching '^  --agent ' per ADR-0102 (CLI 2.1.207 kept --agent as built-in agent selector); if claude actually removed the flag, this d-test needs updating — see ADR-0102 + Issue #88"
  fi
else
  # Cannot run claude --help (e.g., CI env without CLI installed) — skip with note.
  # This is an environmental gap, not a RED signal. The impl does not depend on
  # claude being installed; only this regression-detector TC does.
  printf "  ${B}⊘ SKIP${D} — claude CLI not on PATH (TC2 is environment-dependent; impl fix does not require claude installed)\n"
fi

# ----------------------------------------------------------------------------
# TC3: bootstrap-generated scripts/.tmux-bootstrap/<role>.sh have NO --agent
# ----------------------------------------------------------------------------
section "TC3: bootstrap-generated <role>.sh files contain no --agent token"
TMUX_BOOT_DIR="$(mktemp -d -t d0984-bootstrap-XXXXXX)"
cleanup_bootstrap() { rm -rf "$TMUX_BOOT_DIR" 2>/dev/null || true; }
trap cleanup_bootstrap EXIT

if [ -f "$DEV_STUDIO_START" ]; then
  # Extract the write_agent_bootstrap function definition from dev-studio-start.sh
  # via awk. The function body is between 'write_agent_bootstrap() {' and the
  # matching '}' at column 0. We use awk to grab those lines verbatim, then
  # eval the function definition in this shell context.
  fn_def=$(awk '
    /^write_agent_bootstrap\(\) \{/ { in_func=1 }
    in_func { print }
    in_func && /^}$/ { in_func=0; exit }
  ' "$DEV_STUDIO_START" 2>/dev/null)

  if [ -n "$fn_def" ]; then
    # Eval the function definition
    eval "$fn_def" 2>/dev/null || true

    # Set the env vars the function expects at call-time. Under `set -u`
    # (declared at script top), any unbound variable referenced inside the
    # heredoc body aborts `cat > "$file" <<EOF` mid-write, leaving the
    # generated bootstrap file EMPTY. An empty file would falsely satisfy
    # TC3's "no --agent token" check (vacuously true) — a classic false-green
    # anti-pattern. Bind all heredoc-referenced vars to safe test values so
    # the full heredoc body is written to disk and TC3 grep is meaningful.
    #   - HEARTBEAT_DIR: required on line 77, 79, 80, 92, 96, 111, 122, 130, 131
    #   - PROJECT_NAME: required on line 80
    #   - HEARTBEAT_DIR: also referenced inside the bootstrap script's runtime
    #     section via $HEARTBEAT_DIR/${role}.json (line 75 of the generated file)
    BOOT_DIR="$TMUX_BOOT_DIR"
    REPO_ROOT="$REPO_ROOT"
    ENV_FILE="$REPO_ROOT/.env"
    HEARTBEAT_DIR="/tmp/d0984-hb-$$"
    PROJECT_NAME="d0984-test"
    mkdir -p "$HEARTBEAT_DIR"

    # Generate bootstrap files for all 5 agent roles
    gen_ok=1
    for role in orchestrator product-manager architect developer tester; do
      if ! write_agent_bootstrap "$role" 2>/dev/null; then
        gen_ok=0
        fail "write_agent_bootstrap $role failed" "function extracted from $DEV_STUDIO_START did not execute cleanly (check that HEARTBEAT_DIR + PROJECT_NAME are bound — see comment above TC3)"
      fi
    done

    # Sanity guard against false-green: if any generated file is suspiciously
    # small (<200 bytes), the heredoc aborted mid-write (likely unbound var).
    # This is a defensive TC3.5 check — the issue is real because TC1's grep
    # against dev-studio-start.sh source CAN pass with the heredoc body in
    # source still containing `--agent ` (per ADR-0102 fix scope: dev-studio-start.sh
    # source is fixed; the heredoc body line is what changes). We want TC3 to
    # detect the heredoc body itself, not just source-side grep.
    for f in "$TMUX_BOOT_DIR"/*.sh; do
      [ -f "$f" ] || continue
      fsize=$(wc -c < "$f" 2>/dev/null || echo 0)
      if [ "$fsize" -lt 200 ]; then
        fail "generated bootstrap file $(basename "$f") suspiciously small ($fsize bytes)" "expected ≥200 bytes (full heredoc body written); if smaller, heredoc aborted mid-write — bind HEARTBEAT_DIR + PROJECT_NAME before write_agent_bootstrap call (see TC3 comment)"
      fi
    done

    if [ "$gen_ok" -eq 1 ]; then
      # Verify all 5 generated files lack --agent token
      files_total=0
      files_with_agent=0
      for f in "$TMUX_BOOT_DIR"/*.sh; do
        [ -f "$f" ] || continue
        files_total=$((files_total + 1))
        if grep -qE -- '--agent ' "$f" 2>/dev/null; then
          files_with_agent=$((files_with_agent + 1))
        fi
      done

      if [ "$files_total" -eq 5 ] && [ "$files_with_agent" -eq 0 ]; then
        pass "all 5 generated bootstrap files (orch/pm/arch/dev/tester) lack --agent token"
      elif [ "$files_total" -ne 5 ]; then
        fail "expected 5 bootstrap files generated, got $files_total" "write_agent_bootstrap should produce 5 files (one per role)"
      else
        # Surface offending role files
        offending=$(grep -lE -- '--agent ' "$TMUX_BOOT_DIR"/*.sh 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        fail "$files_with_agent/5 generated bootstrap files still contain --agent token" "offending: $offending — remove --agent \"\${role}\" from the heredoc body in scripts/dev-studio-start.sh write_agent_bootstrap()"
      fi
    fi
  else
    fail "could not extract write_agent_bootstrap function from dev-studio-start.sh" "function definition not found via awk pattern — file structure may have changed; update TC3"
  fi
else
  fail "dev-studio-start.sh absent (skipped TC3)" "Issue #89 spec requires dev-studio-start.sh"
fi

# ----------------------------------------------------------------------------
# TC4: bash -n syntax check passes for all 5 generated bootstrap scripts
# ----------------------------------------------------------------------------
section "TC4: bash -n syntax check on all 5 generated bootstrap scripts"
syntax_fail=0
syntax_total=0
syntax_offending=""
for f in "$TMUX_BOOT_DIR"/*.sh; do
  [ -f "$f" ] || continue
  syntax_total=$((syntax_total + 1))
  if ! bash -n "$f" 2>/dev/null; then
    syntax_fail=$((syntax_fail + 1))
    syntax_offending="$syntax_offending $(basename "$f")"
  fi
done

if [ "$syntax_total" -eq 0 ]; then
  fail "no bootstrap files to syntax-check (TC4 cannot run without TC3 generation)" "TC4 depends on TC3 generation succeeding; check TC3 result first"
elif [ "$syntax_fail" -eq 0 ]; then
  pass "bash -n passes for all $syntax_total generated bootstrap scripts"
else
  fail "bash -n failed on $syntax_fail/$syntax_total generated bootstrap scripts" "offending:$syntax_offending — heredoc structure broken or unescaped template variable leaked"
fi

# ----------------------------------------------------------------------------
# TC5: --append-system-prompt-file still wired in bootstrap heredoc
# ----------------------------------------------------------------------------
section "TC5: --append-system-prompt-file still wired in dev-studio-start.sh heredoc"
if [ -f "$DEV_STUDIO_START" ]; then
  # Positive regression check: ensure the identity-loading flag is still wired.
  # After removing --agent, identity MUST continue to load via
  # --append-system-prompt-file .claude/agents/${role}.md (per ADR-0102).
  append_count=$(grep -c -- '--append-system-prompt-file' "$DEV_STUDIO_START" 2>/dev/null)
  append_count="${append_count:-0}"
  if [ "$append_count" -ge 1 ]; then
    pass "--append-system-prompt-file still wired ($append_count occurrence(s)) — identity loading path intact"
  else
    fail "--append-system-prompt-file missing from dev-studio-start.sh" "after removing --agent (TC1), --append-system-prompt-file MUST remain wired or agents lose identity — see ADR-0102 + Issue #88"
  fi
else
  fail "dev-studio-start.sh absent (skipped)" "Issue #89 spec requires dev-studio-start.sh"
fi

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
printf "\n${B}==== Summary ====${D}\n"
printf "  PASS: %d\n" "$PASS"
printf "  FAIL: %d\n" "$FAIL"
printf "  Target tested: Issue #89 (template-gap-close) + ADR-0102 — remove --agent \"\${role}\" from scripts/dev-studio-start.sh heredoc (CLI 2.1.207 breaking change)\n"

if [ "$FAIL" -gt 0 ]; then
  printf "\n${R}RED state${D} — pre-impl template main has --agent \"\${role}\" still in source + bootstrap-generated files. ADR-0102 (Issue #88, PR #97 MERGED) codifies the fix; impl Issue #90 BLOCKED on this RED-first d-test per ADR-0100 (template-side doctrinal home) + ADR-0044 (calc-side doctrinal home for RED-first TDD).\n"
  exit 1
else
  printf "\n${G}GREEN state${D} — all 5 TCs pass; developer impl landed the --agent \"\${role}\" removal in scripts/dev-studio-start.sh heredoc per ADR-0102. AC1-AC4 of Issue #89 satisfied (5 generated bootstrap files lack --agent, identity path intact, CLI --agent flag still in claude --help as regression detector).\n"
  exit 0
fi
