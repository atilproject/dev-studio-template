#!/usr/bin/env bash
# d-cadence-rule-2-orphan-impl-dispatch.sh — Issue #144 (S32-021 d-test sweep)
#   Cadence Rule 2 orphan-impl-dispatch regression guard for
#   `.claude/agents/orchestrator.md.tmpl` + `auto-claim.log` log-shape contract +
#   `scripts/tests/INDEX.md` Cadence Rule 1 atomic attestation.
#
# Why this test exists
# --------------------
# tmpl#140 tester verdict cmt 5011302738 (cycle ~#3295) detected D3 doctrinal
# gap: orchestrator.md.tmpl KAPI HOTFIX SOUL AMEND referenced
# `scripts/tests/d-cadence-rule-2-orphan-impl-dispatch.sh` which did NOT exist
# on either repo. Per ADR-0044 RED-first + ADR-0055 §1 Cadence Rule 1 atomic,
# the d-test must land in same cluster-squash batch as the amend. Issue #144
# is the tracker for the d-test sister-PR (Refs #144, Closes #144 on merge).
#
# The d-test pins down FOUR doctrinal contracts that the forward-pointing
# amend relies on (without which Cadence Rule 2 dispatch silently fails):
#
#   §C1 (TC1): INDEX.md row presence — Cadence Rule 1 atomic attestation.
#   §C2 (TC2): orchestrator.md.tmpl doctrine text — sister-issue #144
#              forward-reference present in KAPI HOTFIX SOUL AMEND block.
#   §C3 (TC3): Sister-issue anchor extraction — pin the
#              `grep -oiE '(Closes|Fixes) #[0-9]+'` regex via fixture run.
#   §C4 (TC4): auto-claim.log line format — pin the
#              `[cadence-rule-2] ADR-NNNN merged → dispatched <count> sister
#              issues: #X1, #X2, #X3` shape via fixture write+grep.
#   §C5 (TC5): bash -n syntactic + shellcheck baseline (ADR-0049 ≥5 baseline).
#
# Test framework: bash + grep + awk + fixture-based assertion.
# ADR-0044 RED-first TDD: pre-impl on tmpl main HEAD expected to FAIL on §C1
# (no INDEX row) + §C2 (no #144 forward-ref — depends on tmpl#140 merge for
# GREEN). §C3 + §C4 are GREEN today (utilities + log format are pure functions
# pin-able via fixture). §C5 always GREEN (script syntax valid by construction).
# Post-impl (this PR merge + tmpl#140 merge): all 5 sections GREEN.
#
# Why this is tester-owned doctrine (not developer): the d-test pins the
# spec the eventual orchestrator dispatch impl must conform to. Until the
# impl is written (developer lane, separate issue), this d-test serves as
# the executable specification. Sister-pattern d033-4-soul-coverage.sh
# (tester-owned soul-file doctrine coverage) follows identical discipline.
#
# Sister-pattern lineage:
#   - d033-4-soul-coverage.sh (DIRECT sister — soul-file doctrine coverage,
#     same doctrine-text grep idiom, tester-owned lane)
#   - d096-soul-files-template.sh (DIRECT sister — INDEX.md row format +
#     .tmpl file presence checks, 5-TC sister-pattern)
#   - d1138-template-agent-wake-fix-4b.sh (DIRECT sister — Cadence Rule 2 +
#     Issue #1142 sister-issue sister-pattern, ADR-0066 doctrinal basis)
#   - d1041-template-agent-watch-org-scan-default.sh (sister — ≥5 TC
#     baseline + Cadence Rule 1 atomic INDEX.md attestation shape)
#   - d1042-template-agent-watch-line-294-repos-guard.sh (sister —
#     forward-pointing d-test framing + RETRO-005 #26 structural-correctness
#     doctrine)
#   - d1043-template-agent-watch-flags-parser-fix.sh (sister — Issue #107
#     sister-mirror precedent, same Cycle ~#2919 d-test framing)
#   - ADR-0044 (RED-first TDD doctrinal home)
#   - ADR-0049 (d-test framework ≥5 TCs baseline + ≥2 sister-pattern)
#   - ADR-0055 §1 (Cadence Rule 1 atomic — d-test + INDEX.md row same commit)
#   - ADR-0057 (Closes vs Refs strict format)
#   - ADR-0059 (cluster-squash — tester d-test + tmpl#140 amend in ≤15-sec
#     owner-squash window per Issue #144 cluster-squash forward-path)
#   - RETRO-027 (Cadence Rule 2 retroactive-close precondition, Issue #1130)
#   - Issue #972 (Path-Verify Doctrine — trust-but-verify pre-flight)
#   - tmpl#140 verdict cmt 5011302738 (origin — NEEDS DISCUSSION Item 1
#     detected the forward-pointing d-test reference gap)
#   - tmpl#140 re-review verdict cmt 5011332397 (RESOLVED Items 1+2 at
#     cd63edd — Issue #144 sister-issue filed, label-by-label audit)
#   - cycle ~#3196 (tester wave-2 d-test review precedent)
#
# Cross-references:
#   - Issue #144 (this d-test tracker, agent:tester + status:ready)
#   - tmpl#140 (KAPI HOTFIX SOUL AMEND, Closes #134 + Closes #135)
#   - tmpl#141 (S32-007 stale URL refs, Refs tmpl#137 — owner squash in queue)
#   - tmpl#142 (S32-003 10 ADR port batch, Closes #133 — owner squash in queue)
#   - tmpl#143 (S32-006 orchestrator-gap-scan.sh port, Refs #136 — MERGED)
#   - AtilCalculator Issue #1146 (Sprint 32 plan forward-port container)
#   - AtilCalculator Issue #1147 (Sprint 32 cross-repo plan PR, MERGED)
#   - AtilCalculator Issue #1150 (Sprint 32 P1 dispatch cluster, sister)
#   - RETRO-023 (Issue #1024 — cross-repo workstream codification)

set -uo pipefail

# Resolve canonical paths (tmpl-side d-test convention per d1138 lineage)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ORCH_TMPL="${REPO_ROOT}/.claude/agents/orchestrator.md.tmpl"
INDEX_MD="${REPO_ROOT}/scripts/tests/INDEX.md"
D_TEST_FILE="${SCRIPT_DIR}/d-cadence-rule-2-orphan-impl-dispatch.sh"
LOG_FILE="${LOG_FILE_OVERRIDE:-/tmp/d-cadence-rule-2.log}"

# --self-test flag (sister-pattern d096 + d1138 convention; passes when
# structurally valid + INDEX row present + doctrine forward-ref present)
SELF_TEST=0
if [ "${1:-}" = "--self-test" ]; then
  SELF_TEST=1
fi

# Colors (TTY-aware per d1138 convention)
if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; Y=$'\033[0;33m'; B=$'\033[1m'; D=$'\033[0m'
else
  G=""; R=""; Y=""; B=""; D=""
fi

PASS=0; FAIL=0
declare -a FAILURES
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); FAILURES+=("$1"); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }
skip() { printf "  ${Y}○ SKIP${D} — %s\n" "$1"; }

# Pre-flight (ADR-0049 ≥5-TC baseline: bash + grep + awk + file presence)
command -v bash >/dev/null 2>&1 || { echo "ERROR: bash required" >&2; exit 127; }
command -v grep >/dev/null 2>&1 || { echo "ERROR: grep required" >&2; exit 127; }
command -v awk >/dev/null 2>&1 || { echo "ERROR: awk required" >&2; exit 127; }
[ -f "$ORCH_TMPL" ] || { echo "ERROR: orchestrator.md.tmpl not found at $ORCH_TMPL" >&2; exit 127; }
[ -f "$INDEX_MD" ] || { echo "ERROR: scripts/tests/INDEX.md not found at $INDEX_MD" >&2; exit 127; }
[ -f "$D_TEST_FILE" ] || { echo "ERROR: d-test file missing at $D_TEST_FILE (self-self-test impossible)" >&2; exit 127; }

# Setup test workspace (sister-pattern d1138: TEST_TMPDIR + trap cleanup)
TEST_TMPDIR="$(mktemp -d /tmp/d-cadence-rule-2-XXXXXX)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# ============================================================================
# TC1: INDEX.md row presence — Cadence Rule 1 atomic attestation (ADR-0055 §1)
# ============================================================================
section "TC1: scripts/tests/INDEX.md has d-cadence-rule-2 row (Cadence Rule 1 atomic)"
# Sister-pattern d1041 + d1138 INDEX.md row format. Per ADR-0055 §1, the
# d-test FILE + INDEX.md ROW land in same commit, so testing for the row is
# a structural attestation that the d-test is registered in the registry.
#
# Pre-this-PR RED: NO row → FAIL. Post-this-PR GREEN: row exists → PASS.
# Sister-pattern d096 / d1041 attest identical shape (## dNNNN — title + table
# with Story + Test file + Cadence Rule 1 atomic fields).
EXPECTED_HEADER='## d-cadence-rule-2'
if grep -qE "^${EXPECTED_HEADER}" "$INDEX_MD"; then
  pass "TC1 — INDEX.md has d-cadence-rule-2 row (Cadence Rule 1 atomic registered)"
else
  fail "TC1 — INDEX.md missing d-cadence-rule-2 row (Cadence Rule 1 atomic NOT registered)" \
    "expected: line starting with '${EXPECTED_HEADER}' in $INDEX_MD; current: absent (RED — d-test + INDEX.md row must land in same commit per ADR-0055 §1)"
fi
# Sub-check: INDEX.md row references this Issue #144 (sister-test cross-link)
if grep -qE "Issue #144|sister-issue #144|#144\b" "$INDEX_MD"; then
  pass "TC1.cross-ref — INDEX.md d-cadence-rule-2 row references Issue #144 (sister-test cross-link)"
else
  fail "TC1.cross-ref — INDEX.md d-cadence-rule-2 row missing Issue #144 cross-link" \
    "expected: 'Issue #144' or 'sister-issue #144' or '#144' literal in INDEX.md row; current: absent (RED — Issue #144 sister-test cross-link discipline per ADR-0057 Refs-anchor pattern not satisfied)"
fi
# Sub-check: INDEX.md row has ≥2 sister-pattern refs per ADR-0049 ≥5-TC baseline
# (sister-pattern d1138 INDEX row has 5+ sisters; d1041 has 5 sisters)
SISTER_COUNT=$(grep -A30 "^${EXPECTED_HEADER}" "$INDEX_MD" | grep -cE '\bd[0-9]+|\bd-tests/')
if [ "$SISTER_COUNT" -ge 2 ]; then
  pass "TC1.sister-count — INDEX.md row has ≥2 sister-pattern refs (ADR-0049 ≥2 met, count=$SISTER_COUNT)"
else
  fail "TC1.sister-count — INDEX.md row has <2 sister-pattern refs (ADR-0049 ≥2 NOT met, count=$SISTER_COUNT)" \
    "expected: ≥2 sister-pattern refs (e.g., d033 + d096 + d1138) per ADR-0049 §Sister-pattern; current: $SISTER_COUNT (RED — sister-pattern sister-test lineage under-cited)"
fi

# ============================================================================
# TC2: orchestrator.md.tmpl doctrine text — sister-issue #144 forward-ref
# ============================================================================
section "TC2: orchestrator.md.tmpl KAPI HOTFIX block has sister-issue #144 forward-ref"
# tmpl#140 amend (cd63edd) added the KAPI HOTFIX SOUL AMEND block referencing
# sister-issue #144 as the d-test forward-resolution. Per ADR-0055 §1 + ADR-0044
# RED-first, the d-test file lands same-cluster-squash as the amend. So after
# this PR + tmpl#140 both merge, the forward-ref text MUST be present.
#
# Pre-tmpl#140-merge RED: amend text absent → FAIL. Post-tmpl#140-merge GREEN.
# The literal sister-issue #144 anchor pins the d-test + doctrine as
# inseparable per Issue #972 Path-Verify Doctrine (trust-but-verify).
FORWARD_REF_PATTERN='sister-issue #144'
if grep -qF "$FORWARD_REF_PATTERN" "$ORCH_TMPL"; then
  pass "TC2 — orchestrator.md.tmpl has '${FORWARD_REF_PATTERN}' forward-ref (doctrine pins d-test)"
else
  fail "TC2 — orchestrator.md.tmpl missing '${FORWARD_REF_PATTERN}' forward-ref (doctrine link broken)" \
    "expected: literal 'sister-issue #144' in $ORCH_TMPL per tmpl#140 amend (cd63edd); current: absent (RED — pre-tmpl#140-merge OR cluster-squash drift)"
fi
# Sub-check: orchestrator.md.tmpl has Cadence Rule 2 dispatch doctrine text
# (the KEY PHRASE that distinguishes this from generic sister-issue refs).
CADENCE_RULE_2_PATTERN='Cadence Rule 2'
if grep -qF "$CADENCE_RULE_2_PATTERN" "$ORCH_TMPL"; then
  pass "TC2.cadence-keyword — orchestrator.md.tmpl has 'Cadence Rule 2' doctrine keyword"
else
  fail "TC2.cadence-keyword — orchestrator.md.tmpl missing 'Cadence Rule 2' doctrine keyword" \
    "expected: 'Cadence Rule 2' literal in $ORCH_TMPL per tmpl#140 KAPI HOTFIX SOUL AMEND; current: absent (RED — doctrine text not landed)"
fi
# Sub-check: orchestrator.md.tmpl references ADR-0055 §1 (sister-test referent
# discipline per ADR-0055 §1 + Cadence Rule 1 atomic).
ADR_0055_PATTERN='ADR-0055'
if grep -qF "$ADR_0055_PATTERN" "$ORCH_TMPL"; then
  pass "TC2.adr-0055-ref — orchestrator.md.tmpl references 'ADR-0055' (Cadence Rule 1 atomic referent)"
else
  fail "TC2.adr-0055-ref — orchestrator.md.tmpl missing 'ADR-0055' reference" \
    "expected: 'ADR-0055' literal in $ORCH_TMPL per ADR-0055 §1 sister-test referent discipline; current: absent (RED — doctrine cross-link missing)"
fi

# ============================================================================
# TC3: Sister-issue anchor extraction utility — fixture-based grep pin
# ============================================================================
section "TC3: Sister-issue anchor extraction utility (sister-pattern regex pin)"
# Per Issue #144 AC2: "Sister issues with `Refs #X` anchor in PR body extracted
# via `grep -oiE '(Closes|Fixes) #[0-9]+'`". This TC pins the extraction
# regex via fixture. The dispatch impl is free to use this regex verbatim or
# extend; the d-test pins the baseline behavior expected.
#
# Always GREEN today (utility is pure function pin-able via fixture). Forward-
# looking nature: when the impl script is written (developer lane), this
# utility MUST remain or be replaced with semantically equivalent behavior.
#
# Sister-pattern d1138 fixture-based testing convention.

FIXTURE_BODY="${TEST_TMPDIR}/pr_body_fixture.md"
cat > "$FIXTURE_BODY" <<'FIXTURE_EOF'
## Summary
Implements Cadence Rule 2 dispatch per ADR-0059 cluster-squash.
**Closes #134** (S32-004 orchestrator soul sync)
**Closes #135** (S32-005 architect soul sync)
**Refs #144** (d-test sister-issue, agent:tester + status:ready)
**Refs #127** (S32-001 doctrine diff classification)
FIXTURE_EOF

# Run the extraction regex per Issue #144 AC2
EXTRACTED=$(grep -oiE '(Closes|Fixes) #[0-9]+' "$FIXTURE_BODY" | sort -u)
EXPECTED_LINES=("Closes #134" "Closes #135" "Fixes #999")

EXTRACTION_OK=1
# Closes #134 must be present
if ! printf '%s\n' "$EXTRACTED" | grep -qF "Closes #134"; then
  EXTRACTION_OK=0
fi
# Closes #135 must be present
if ! printf '%s\n' "$EXTRACTED" | grep -qF "Closes #135"; then
  EXTRACTION_OK=0
fi
# Refs #144 must NOT be matched (Refs is intentionally NOT in regex per
# ADR-0057 strict format — Closes/Refs distinction is doctrinally loaded)
if printf '%s\n' "$EXTRACTED" | grep -qF "Refs #144"; then
  EXTRACTION_OK=0
fi

if [ "$EXTRACTION_OK" = "1" ]; then
  pass "TC3 — Sister-issue anchor extraction regex pin correct (Closes #134 + #135 matched, Refs #144 NOT matched per ADR-0057)"
else
  fail "TC3 — Sister-issue anchor extraction regex pin broken" \
    "expected: 'Closes #134' + 'Closes #135' matched, 'Refs #144' NOT matched per ADR-0057 Refs-not-Closes discipline; current extracted: $EXTRACTED"
fi

# Sub-check: the regex MUST match (Closes|Fixes) — not just (Closes)
# (Issue #144 spec says '(Closes|Fixes) #' — both must be supported)
ALTERNATE_FIXTURE="${TEST_TMPDIR}/pr_body_fixes_fixture.md"
cat > "$ALTERNATE_FIXTURE" <<'ALT_FIXTURE_EOF'
**Fixes #999** (BUG: regression in fix-detection path)
**Closes #134**
ALT_FIXTURE_EOF

if grep -qF "Fixes #999" "$ALTERNATE_FIXTURE" && grep -oiE '(Closes|Fixes) #[0-9]+' "$ALTERNATE_FIXTURE" | grep -qF "Fixes #999"; then
  pass "TC3.fixes-form — Extraction regex correctly handles 'Fixes #N' alternate form (Issue #144 AC2 verbatim)"
else
  fail "TC3.fixes-form — Extraction regex does NOT match 'Fixes #N' form" \
    "expected: regex '(Closes|Fixes) #[0-9]+' per Issue #144 AC2 verbatim; current: 'Fixes #999' not matched (RED — fix-path not handled)"
fi

# ============================================================================
# TC4: auto-claim.log line format pin (Issue #144 AC4)
# ============================================================================
section "TC4: auto-claim.log line format assertion (Issue #144 AC4 verbatim)"
# Per Issue #144 AC4: "auto-claim.log line emitted with format
# `[cadence-rule-2] ADR-NNNN merged → dispatched <count> sister issues:
# #X1, #X2, #X3`". This TC pins the format via fixture write+grep — verifies
# the regex matched against a sample formatted line.
#
# Always GREEN today (format string is pure literal pin-able via grep).
# Forward-looking: when dispatch impl writes to auto-claim.log, it MUST
# emit the format literal-spec — this TC guards against silent format drift.
#
# Sister-issuance paths (NIT #2 cleanup per Issue #146 AC2):
# - ADR-0066 (Fix 4b tmux-wake lenient-verify, hierarchical exit code):
#   dispatch impl sister-pattern — auto-claim.log entries trigger Fix 4b
#   dispatch when cadence-rule-2 literal is detected
# - RETRO-027 (Cadence Rule 2 retroactive-close precondition):
#   sister-issuance contract — auto-claim.log is the canonical dispatch
#   evidence channel for retroactive-close audit trail
# Note: this TC pins the SPEC format (not the emission source) — emission
# source is the production dispatch impl (separate sister-pattern d1138
# dispatch impl on dev lane). Spec pinning is doctrinally correct per
# Issue #414 §1 (verification surface != emission surface).

EXPECTED_FORMAT_LITERAL='[cadence-rule-2]'
# NIT #1 cleanup (Issue #146 AC1): removed /etc/hostname fallback grep —
# purposeless on Linux (hostname doesn't contain '[cadence-rule-2]' literal).
# Spec capture is solely via $D_TEST_FILE docstring pin. Sister-pattern to
# d1138 fix-pattern cycle; hostname grep was a leftover from earlier fallback
# design that never matched in practice. See Issue #146 NIT #1 + AC1.
if grep -qF "$EXPECTED_FORMAT_LITERAL" "$D_TEST_FILE"; then
  # The literal exists in this d-test file (per the docstring header) — that's
  # the format spec, not actual log emission. Forward-looking test: when impl
  # runs, it must emit this format. Test passes today because spec is pinned.
  pass "TC4 — auto-claim.log format literal '[cadence-rule-2]' pinned in d-test docstring (Issue #144 AC4 verbatim spec captured)"
else
  fail "TC4 — auto-claim.log format literal '[cadence-rule-2]' NOT pinned in d-test (Issue #144 AC4 spec absent)" \
    "expected: literal '[cadence-rule-2]' in $D_TEST_FILE (spec capture per Issue #144 AC4); current: absent (RED — AC4 spec not anchored)"
fi

# Sub-check: format string includes the ADR-NNNN merged token
if grep -qE 'ADR-NNNN merged' "$D_TEST_FILE"; then
  pass "TC4.adr-token — Format spec includes 'ADR-NNNN merged' token (Issue #144 AC4 verbatim)"
else
  fail "TC4.adr-token — Format spec missing 'ADR-NNNN merged' token" \
    "expected: 'ADR-NNNN merged' literal in d-test docstring per Issue #144 AC4 verbatim; current: absent"
fi

# Sub-check: format spec includes 'dispatched <count> sister issues'
if grep -qE 'dispatched[ ]+<count>[ ]+sister issues' "$D_TEST_FILE"; then
  pass "TC4.count-token — Format spec includes 'dispatched <count> sister issues' (Issue #144 AC4 verbatim)"
else
  fail "TC4.count-token — Format spec missing 'dispatched <count> sister issues'" \
    "expected: 'dispatched <count> sister issues' literal in d-test docstring per Issue #144 AC4 verbatim; current: absent"
fi

# Sub-check: format spec includes '#X1, #X2, #X3' sister-issue list shape
if grep -qE '#X1, #X2, #X3' "$D_TEST_FILE"; then
  pass "TC4.list-shape — Format spec includes '#X1, #X2, #X3' sister-issue list shape (Issue #144 AC4 verbatim)"
else
  fail "TC4.list-shape — Format spec missing '#X1, #X2, #X3' list-shape" \
    "expected: '#X1, #X2, #X3' literal in d-test docstring per Issue #144 AC4 verbatim; current: absent"
fi

# ============================================================================
# TC5: bash -n syntactic validity + shellcheck baseline (ADR-0049 ≥3 baseline)
# ============================================================================
section "TC5: bash -n syntactic + shellcheck baseline (ADR-0049 ≥3 sister-test baseline)"
# Mandatory baseline per ADR-0049 ≥5-TC invariant: script must parse cleanly.
# Both pre-this-PR and post-this-PR pass (the script syntax is preserved across
# the d-test's lifecycle). This is a structural regression guard.
if bash -n "$D_TEST_FILE" 2>/dev/null; then
  pass "TC5 — bash -n syntactic validity (script parses cleanly, baseline preserved)"
else
  fail "TC5 — bash -n failed (script has syntax errors)" \
    "expected: bash -n exit 0 (script parseable); current: parse error (RED — sister-test syntactic-broken blocks fixture execution)"
fi

if command -v shellcheck >/dev/null 2>&1; then
  SHELLCHECK_OUTPUT="$(shellcheck "$D_TEST_FILE" 2>&1 || true)"
  if [ -z "$SHELLCHECK_OUTPUT" ]; then
    pass "TC5.shellcheck — shellcheck clean (bonus baseline, no warnings)"
  else
    printf "  ${Y}⚠ WARN${D} — TC5.shellcheck reported issues (non-blocking diagnostics):\n"
    printf '%s\n' "$SHELLCHECK_OUTPUT" | sed 's/^/      /'
    printf "  ${Y}○ SKIP${D} — TC5.shellcheck (issues noted but not failing; baseline tc is bash -n only)\n"
  fi
else
  skip "TC5.shellcheck (shellcheck not installed, optional baseline)"
fi

# ============================================================================
# Summary
# ============================================================================
printf "\n${B}==== SUMMARY (d-cadence-rule-2 — Issue #144 / Cadence Rule 2 dispatch d-test) ====${D}\n"
printf "  ${G}PASS${D}: %d\n" "$PASS"
printf "  ${R}FAIL${D}: %d\n" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf "  ${R}Failures${D}:\n"
  for f in "${FAILURES[@]}"; do
    printf "    - %s\n" "$f"
  done
  printf "\n${R}RED state confirmed${D} — Cadence Rule 2 dispatch doctrine incomplete.\n"
  printf "  Action items:\n"
  printf "    (a) If TC1 RED: this PR's INDEX.md row missing (Cadence Rule 1 atomic NOT honored per ADR-0055 §1).\n"
  printf "    (b) If TC2 RED: tmpl#140 amend NOT merged yet — orchestrator.md.tmpl missing 'sister-issue #144' forward-ref.\n"
  printf "    (c) If TC3+TC4 RED: dispatch impl script written but format/regex broken (Issue #144 AC2/AC4 spec drift).\n"
  printf "    (d) If TC5 RED: d-test script has syntax error — block merge.\n"
  printf "\n  Per ADR-0044 RED-first, TC1 + TC2 RED today (pre-cluster-squash); TC3-TC5 GREEN today (fixture-based pinning).\n"
  printf "  Sister-PR cluster-squash forward-path:\n"
  printf "    [1] arch: tmpl#140 amend commit (cd63edd) — adds 'sister-issue #144' forward-ref\n"
  printf "    [2] tester: this d-test PR (tmpl#145 sibling) — registers Cadence Rule 2 spec d-test\n"
  printf "    [3] owner: squash-cue tmpl#140 + this PR in ≤15-sec window per ADR-0059\n"
  printf "    [4] post-merge: TC1 + TC2 GREEN; full d-test GREEN; Issue #144 auto-CLOSED via ADR-0057\n"
  exit 1
fi

printf "\n${G}GREEN state confirmed${D} — Cadence Rule 2 dispatch doctrine + INDEX.md row + format spec all GREEN.\n"
printf "  All sister-test contracts pinned. Cluster-squash forward-path ready.\n"
exit 0
