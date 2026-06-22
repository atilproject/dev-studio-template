#!/usr/bin/env bash
# dreg-post-restart-label-guard.sh — regression for #261
# (Dev Studio template port: scripts/post-restart-label-guard.sh)
#
# Why this test exists
# --------------------
# Issue #261: post-restart-label-guard.sh + restart-stable.txt were created
# in AtilCalculator as a Sprint 4 P0 fix (auto-revert bug, RCA-15/16/17).
# They need to exist in the dev-studio-template too, so new projects get
# label-drift protection on watcher restart.
#
# This regression test GUARDS:
#   1. The script exists, is executable, and accepts the documented args
#   2. The allowlist file exists and contains only restart-stable labels
#      (cc:* and needs-* must NOT be present — they're workflow state)
#   3. The systemd integration is wired (ExecStartPost= in installer / unit)
#   4. Idempotency structural invariant: empty allowlist → exit 0 (no gh calls)
#   5. The watcher drop-in install script references the guard
#
# Test cases (10):
#   T1:  post-restart-label-guard.sh exists at scripts/post-restart-label-guard.sh
#   T2:  Script is executable (-x bit set)
#   T3:  Script handles --dry-run flag (mode flag parsing)
#   T4:  Script rejects unknown args (exits non-zero)
#   T5:  Script has empty-allowlist no-op path (exits 0 before gh call)
#   T6:  restart-stable.txt exists at scripts/restart-stable.txt
#   T7:  Allowlist contains only restart-stable labels
#        (must NOT contain cc:* or needs-*: — those are workflow state)
#   T8:  Allowlist default contains type:* and sprint:* (preserves AtilCalc contract)
#   T9:  systemd integration wired: dev-studio-install-systemd.sh or watcher
#        unit references post-restart-label-guard.sh via ExecStartPost=
#   T10: Script logs to scripts/logs/post-restart-label-guard.log
#
# Exit code: 0 = all pass, 1 = at least one fail.
#
# Run standalone: bash scripts/tests/dreg-post-restart-label-guard.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD_SH="$REPO_ROOT/scripts/post-restart-label-guard.sh"
ALLOWLIST="$REPO_ROOT/scripts/restart-stable.txt"
INSTALL_SH="$REPO_ROOT/scripts/install/dev-studio-install-systemd.sh"
WATCHER_SVC="$REPO_ROOT/scripts/install/systemd/dev-studio-watcher@.service"

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

# ============================================================================
# T1: Script exists
# ============================================================================
section "T1: post-restart-label-guard.sh exists at scripts/post-restart-label-guard.sh"
if [ -f "$GUARD_SH" ]; then
  pass "script present at $GUARD_SH"
else
  fail "script missing" "expected: scripts/post-restart-label-guard.sh (mirrored from AtilCalculator PR #211)"
fi

# ============================================================================
# T2: Script is executable
# ============================================================================
section "T2: Script is executable (-x bit set)"
if [ -x "$GUARD_SH" ]; then
  pass "script is executable"
else
  fail "script is NOT executable" "fix: chmod +x scripts/post-restart-label-guard.sh"
fi

# ============================================================================
# T3: Script handles --dry-run flag
# ============================================================================
section "T3: Script accepts --dry-run flag (mode parsing)"
if [ -f "$GUARD_SH" ] && grep -Eq -- '--dry-run' "$GUARD_SH"; then
  pass "script has --dry-run mode handling"
else
  fail "no --dry-run handling" "expected: case \"\${1:-}\" branch for --dry-run (zero-risk first deploy)"
fi

# ============================================================================
# T4: Script rejects unknown args
# ============================================================================
section "T4: Script rejects unknown args (exits non-zero)"
if [ -f "$GUARD_SH" ] && grep -Eq 'unknown arg|exit 1' "$GUARD_SH"; then
  pass "script has unknown-arg rejection + exit 1 path"
else
  fail "no unknown-arg rejection" "expected: *) echo \"ERROR: unknown arg\" >&2; exit 1 ;; in case branch"
fi

# ============================================================================
# T5: Empty-allowlist no-op path (exits 0 before gh call)
# ============================================================================
section "T5: Empty-allowlist no-op (exits 0 before gh pr list)"
# This is the maximum-safety invariant: if the allowlist is empty, the
# script MUST short-circuit and exit 0 WITHOUT calling gh. Guards against
# rate-limit / auth-failure surfacing as restart-time noise.
if [ -f "$GUARD_SH" ] && \
   grep -Eq 'ALLOWLIST_PATTERNS' "$GUARD_SH" && \
   grep -B2 -A2 'empty allowlist' "$GUARD_SH" | grep -q 'exit 0'; then
  pass "empty-allowlist short-circuit exits 0 before gh call"
else
  fail "no empty-allowlist no-op" "expected: if [ -z \"\$ALLOWLIST_PATTERNS\" ]; then exit 0; fi BEFORE gh pr list call"
fi

# ============================================================================
# T6: restart-stable.txt exists
# ============================================================================
section "T6: restart-stable.txt exists at scripts/restart-stable.txt"
if [ -f "$ALLOWLIST" ]; then
  pass "allowlist present at $ALLOWLIST"
else
  fail "allowlist missing" "expected: scripts/restart-stable.txt (mirrored from AtilCalculator)"
fi

# ============================================================================
# T7: Allowlist contains only restart-stable labels (no cc:*, no needs-*:)
# ============================================================================
section "T7: Allowlist contains ONLY restart-stable labels"
# Per ADR-0031 + design §Data model: only type:* and sprint:* are
# restart-stable. cc:* and needs-*: are workflow state — they MUST NOT
# be re-applied by the guard (would mask owner's manual intent).
if [ -f "$ALLOWLIST" ]; then
  bad_patterns="$(grep -vE '^[[:space:]]*(#|$)' "$ALLOWLIST" | grep -E '^(cc|needs|status|agent|priority):' || true)"
  if [ -z "$bad_patterns" ]; then
    pass "no cc:* / needs-*: / status:* / agent:* / priority:* in allowlist (correct)"
  else
    fail "found non-restart-stable patterns" "REGRESSION: $bad_patterns — only type:* + sprint:* are restart-stable per ADR-0031"
  fi
else
  fail "allowlist missing — T7 cannot run" "expected: scripts/restart-stable.txt"
fi

# ============================================================================
# T8: Allowlist default has type:* and sprint:* (preserves AtilCalc contract)
# ============================================================================
section "T8: Allowlist default = type:* + sprint:* (preserves AtilCalc contract)"
if [ -f "$ALLOWLIST" ]; then
  has_type=false
  has_sprint=false
  grep -qE '^type:\*$' "$ALLOWLIST" && has_type=true
  grep -qE '^sprint:\*$' "$ALLOWLIST" && has_sprint=true
  if $has_type && $has_sprint; then
    pass "allowlist has both type:* and sprint:* (AtilCalc contract preserved)"
  else
    fail "missing required allowlist patterns" "expected: type:* and sprint:* (Sprint 4 P0 default)"
  fi
else
  fail "allowlist missing — T8 cannot run" "expected: scripts/restart-stable.txt"
fi

# ============================================================================
# T9: systemd integration wired (ExecStartPost= reference)
# ============================================================================
section "T9: systemd integration — ExecStartPost= references post-restart-label-guard.sh"
# The guard needs to be invoked after watcher restart. The integration is
# via systemd ExecStartPost= in either:
#   (a) scripts/install/systemd/dev-studio-watcher@.service (base template)
#   (b) scripts/install/dev-studio-install-systemd.sh (drop-in generator)
#   (c) the watcher drop-in override.conf pattern (rendered at install)
#
# We check (a) and (b) structurally — the rendered drop-in is project-
# specific and tested at install time.
integration_ok=false
if [ -f "$WATCHER_SVC" ] && grep -Eq 'ExecStartPost.*post-restart-label-guard' "$WATCHER_SVC"; then
  pass "watcher unit template references post-restart-label-guard.sh via ExecStartPost="
  integration_ok=true
elif [ -f "$INSTALL_SH" ] && grep -Eq 'ExecStartPost.*post-restart-label-guard' "$INSTALL_SH"; then
  pass "install script renders ExecStartPost= for post-restart-label-guard.sh"
  integration_ok=true
else
  fail "no systemd integration found" "expected: ExecStartPost=/usr/bin/bash \$REPO_ROOT/scripts/post-restart-label-guard.sh in either watcher unit or install script"
fi

# ============================================================================
# T10: Script logs to scripts/logs/post-restart-label-guard.log
# ============================================================================
section "T10: Script logs to scripts/logs/post-restart-label-guard.log"
if [ -f "$GUARD_SH" ] && grep -Eq 'LOG_FILE=.*post-restart-label-guard\.log' "$GUARD_SH"; then
  pass "LOG_FILE path is scripts/logs/post-restart-label-guard.log"
else
  fail "LOG_FILE path mismatch" "expected: LOG_FILE=\"\$LOG_DIR/post-restart-label-guard.log\" where LOG_DIR=scripts/logs"
fi

# ============================================================================
# Summary
# ============================================================================
printf "\n${B}==== SUMMARY ====${D}\n"
printf "  ${G}PASS${D}: %d\n" "$PASS"
printf "  ${R}FAIL${D}: %d\n" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo
  echo "Issue #261 REGRESSION FAILED — post-restart-label-guard.sh template port incomplete."
  echo "Fix: copy post-restart-label-guard.sh + restart-stable.txt from AtilCalculator,"
  echo "     genericize headers, add ExecStartPost= to watcher drop-in install."
  exit 1
fi
echo
echo "Issue #261 REGRESSION PASS — post-restart-label-guard.sh fully ported + integrated."
exit 0