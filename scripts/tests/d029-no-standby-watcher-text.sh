#!/usr/bin/env bash
# d029-no-standby-watcher-text.sh — regression for watcher-side no-standby doctrine.
#
# Why this test exists
# --------------------
# Issue #40 §Doctrine Reminder — no self-standby prohibits agents from using
# "standby", "holding", "iş saatleri", "ofis-saati", "sabah bakacağım",
# "yarın devam" as a pause justification. d028 enforces this in
# `.claude/agents/*.md` (4 soul files). d029 is the watcher-side equivalent:
# `scripts/agent-watch.sh` is the *enforcement mechanism* — if IT emits
# forbidden text in `wake_nudge` payload, agents reading the nudge are
# invited to self-standby, defeating the doctrine.
#
# Template port (Issue #262). Reference impl: atilcan65/AtilCalculator d029.
# Template equivalent of AtilCalc Issue #256 = Template Issue #41 (the
# "swap 'standby' text in wake_nudge" fix that landed in main commit
# 4e56022 with PR #41 → d028 enforcement).
#
# Test cases (5, per #41 acceptance):
#   T1: scripts/agent-watch.sh — no 'standby' (case-insensitive)
#   T2: scripts/agent-watch.sh — no 'holding' (the 'paused-on-dep' synonym)
#   T3: scripts/agent-watch.sh — no 'iş saatleri' / 'ofis-saati' (Turkish
#        for "work hours" / "office hours" — forbidden per CLAUDE.md §NEVER)
#   T4: scripts/agent-watch.sh — no 'sabah bakacağım' / 'yarın devam'
#        ("will look in the morning" / "continue tomorrow" — the most
#        common stall phrases)
#   T5: scripts/agent-watch.sh — wake_nudge context.note does NOT contain
#        forbidden words (live-behavior check via dry-run)
#
# Exit code: 0 = all pass, 1 = at least one fail.
#
# Run standalone: bash scripts/tests/d029-no-standby-watcher-text.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH_SH="$SCRIPT_DIR/../agent-watch.sh"

# Colors (TTY-aware)
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; B=""; D=""; fi

PASS=0; FAIL=0
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

if [ ! -r "$WATCH_SH" ]; then
  echo "ERROR: agent-watch.sh not found at $WATCH_SH" >&2; exit 127
fi

# Forbidden words per Issue #40 §Doctrine Reminder + #41 acceptance
FORBIDDEN_EN=("standby" "holding" "paused-on-dep")
FORBIDDEN_TR=("iş saatleri" "ofis-saati" "sabah bakacağım" "yarın devam")

# ============================================================================
# T1: no 'standby' (case-insensitive)
# ============================================================================
section "T1: scripts/agent-watch.sh — no 'standby' (case-insensitive)"
if grep -niE '\bstandby\b' "$WATCH_SH" >/dev/null 2>&1; then
  matches="$(grep -niE '\bstandby\b' "$WATCH_SH" | head -5)"
  fail "found 'standby' in agent-watch.sh" "$matches"
else
  pass "no 'standby' occurrences in agent-watch.sh"
fi

# ============================================================================
# T2: no 'holding' (pause synonym)
# ============================================================================
section "T2: scripts/agent-watch.sh — no 'holding' (pause synonym)"
if grep -niE '\bholding\b' "$WATCH_SH" >/dev/null 2>&1; then
  matches="$(grep -niE '\bholding\b' "$WATCH_SH" | head -5)"
  fail "found 'holding' in agent-watch.sh" "$matches"
else
  pass "no 'holding' occurrences in agent-watch.sh"
fi

# ============================================================================
# T3: no Turkish 'work hours' / 'office hours' phrases
# ============================================================================
section "T3: scripts/agent-watch.sh — no 'iş saatleri' / 'ofis-saati'"
t3_fail=0
for word in "${FORBIDDEN_TR[@]:0:2}"; do
  if grep -niF "$word" "$WATCH_SH" >/dev/null 2>&1; then
    matches="$(grep -niF "$word" "$WATCH_SH" | head -3)"
    fail "found '$word' in agent-watch.sh" "$matches"
    t3_fail=1
  fi
done
if [ "$t3_fail" -eq 0 ]; then
  pass "no 'iş saatleri' / 'ofis-saati' in agent-watch.sh"
fi

# ============================================================================
# T4: no 'sabah bakacağım' / 'yarın devam' (morning/tomorrow stall phrases)
# ============================================================================
section "T4: scripts/agent-watch.sh — no 'sabah bakacağım' / 'yarın devam'"
t4_fail=0
for word in "${FORBIDDEN_TR[@]:2:2}"; do
  if grep -niF "$word" "$WATCH_SH" >/dev/null 2>&1; then
    matches="$(grep -niF "$word" "$WATCH_SH" | head -3)"
    fail "found '$word' in agent-watch.sh" "$matches"
    t4_fail=1
  fi
done
if [ "$t4_fail" -eq 0 ]; then
  pass "no 'sabah bakacağım' / 'yarın devam' in agent-watch.sh"
fi

# ============================================================================
# T5: wake_nudge context.note is clean (live-behavior check via dry-run)
# ============================================================================
section "T5: wake_nudge literal does NOT contain forbidden words (template-portable)"
# We can't easily run agent-watch.sh here (it does GitHub API calls), but
# we can grep the source for the wake_nudge instruction literal + assert no
# 'standby' is in it. The literal that lands in context.note starts with
# "Lütfen pickup et" — the standard wake_nudge instruction.
#
# Template-portable: instead of asserting a SPECIFIC action-oriented phrase
# (which differs between AtilCalc "heartbeat yaz ve queue'ya dön" and
# template's "aktif kal"), we assert (a) the literal EXISTS and (b) it has
# NO forbidden word. The specific action phrase is implementation detail.
LITERAL_PATTERN="Lütfen pickup et"
literal="$(grep -nF "$LITERAL_PATTERN" "$WATCH_SH" | head -1)"
if [ -z "$literal" ]; then
  fail "no '$LITERAL_PATTERN' literal found" "expected wake_nudge instruction in agent-watch.sh"
else
  literal_violation=0
  for word in "${FORBIDDEN_EN[@]}" "${FORBIDDEN_TR[@]}"; do
    if echo "$literal" | grep -niF "$word" >/dev/null 2>&1; then
      fail "wake_nudge literal contains forbidden word '$word'" "$literal"
      literal_violation=1
    fi
  done
  if [ "$literal_violation" -eq 0 ]; then
    pass "wake_nudge literal present + clean (no forbidden words): ${literal#*:}"
  fi
fi

# ============================================================================
# Summary
# ============================================================================
printf "\n${B}==== SUMMARY ====${D}\n"
printf "  ${G}PASS${D}: %d\n" "$PASS"
printf "  ${R}FAIL${D}: %d\n" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo
  echo "Issue #41 REGRESSION FAILED — watcher emits forbidden no-standby doctrine text."
  echo "Fix: edit scripts/agent-watch.sh — replace 'sonra standby.' with"
  echo "     'sonra heartbeat yaz ve queue'ya dön.' (or similar action-oriented phrase)"
  echo "     AND rename 'standby' comments to 'silenced' or 'paused-on-dep'."
  exit 1
fi
echo
echo "Issue #41 REGRESSION PASS — watcher emits only action-oriented text."
exit 0
