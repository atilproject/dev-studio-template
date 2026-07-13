#!/usr/bin/env bash
# s29-011-issue-templates.sh — STORY-S29-011 regression guard for .github/ISSUE_TEMPLATE/ files
# (Issue #1036, Sprint 29 Wave 2B forward-port — REFRAMED XS per owner #7 directive).
#
# Why this test exists
# --------------------
# ISSUE_TEMPLATEs in dev-studio-template/.github/ISSUE_TEMPLATE/ pre-fill labels at issue creation.
# ADR-0012 4-cat invariant requires type/status/agent/cc labels to be addressable on every issue.
# S29-011 verifies all 5 content templates (agent-stall/bug/feature-request/incident/vision-intake)
# have valid YAML frontmatter + ADR-0012 4-cat label section + drift-corrected Ownership rule
# markdown block (Issue #113 doctrine) per AtilCalculator parity baseline.
#
# Acceptance criteria (Issue #1036 / STORY-S29-011):
#   TC1: AC1 — All 5 content templates present (agent-stall.yml, bug.yml, feature-request.yml,
#             incident.yml, vision-intake.yml); config.yml.tmpl exists but is exempt (config file)
#   TC2: AC3 — Each template has valid YAML frontmatter (name, description, title, labels, body)
#             parseable by python3 yaml.safe_load
#   TC3: AC2 — Each template's `labels:` array contains ≥3 of 4 ADR-0012 categories
#             (type:*, status:*, agent:*, cc:*) — sister-pattern: at least 3 categories
#             pre-fillable, the 4th is added during handoff per ADR-0015
#   TC4: AC1 — Drift correction: bug.yml + feature-request.yml contain the Ownership rule
#             markdown block referencing Issue #113 (parity with AtilCalculator)
#   TC5: AC1 — config.yml.tmpl is exempt from content checks (config file, no labels),
#             only existence is required
#
# Pre-impl RED state: 5/5 FAIL (templates lack 4-cat section + drift correction)
# Post-impl GREEN state: 5/5 PASS
#
# Sister-pattern: d066 (AtilCalculator, when landed) — same TC structure
#
# Run: bash scripts/tests/s29-011-issue-templates.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEMPLATE_DIR="${REPO_ROOT}/.github/ISSUE_TEMPLATE"

# 5 content templates (config.yml.tmpl is exempt, checked in TC5)
CONTENT_TEMPLATES=(
  "agent-stall.yml"
  "bug.yml"
  "feature-request.yml"
  "incident.yml"
  "vision-intake.yml"
)

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

printf "${B}s29-011 issue-template 4-cat compliance d-test (5 TCs per ADR-0049)${D}\n"
printf "${B}=====================================================================${D}\n"
printf "  Template dir: %s\n" "$TEMPLATE_DIR"
printf "  Sister-pattern: ADR-0012 4-cat + ADR-0049 ≥3 TC baseline\n\n"

# TC1: All 5 content templates present
section "TC1: AC1 — 5 content templates exist"
TC1_OK=1
for tpl in "${CONTENT_TEMPLATES[@]}"; do
  if [ ! -f "${TEMPLATE_DIR}/${tpl}" ]; then
    fail "TC1 — ${tpl} missing" "expected ${TEMPLATE_DIR}/${tpl}"
    TC1_OK=0
  fi
done
if [ "$TC1_OK" -eq 1 ]; then
  pass "TC1 — all 5 content templates present (agent-stall.yml, bug.yml, feature-request.yml, incident.yml, vision-intake.yml)"
fi

# TC2: Valid YAML frontmatter (parseable by python3 yaml)
section "TC2: AC3 — YAML frontmatter valid (name/description/title/labels/body)"
command -v python3 >/dev/null 2>&1 || { fail "TC2 — python3 required for YAML parse"; exit 1; }
python3 -c "import yaml" 2>/dev/null || {
  fail "TC2 — PyYAML required" "pip install pyyaml (or use python3 -c 'import yaml' fallback test)"
  printf "\n${B}==== SUMMARY ====${D}\n  ${G}PASS${D}: %d  ${R}FAIL${D}: %d\n" "$PASS" "$FAIL"
  exit 1
}

TC2_OK=1
for tpl in "${CONTENT_TEMPLATES[@]}"; do
  path="${TEMPLATE_DIR}/${tpl}"
  if ! python3 -c "
import yaml, sys
with open('${path}') as f:
    d = yaml.safe_load(f)
required = ['name', 'description', 'title', 'labels', 'body']
for k in required:
    if k not in d:
        print(f'MISSING:{k}')
        sys.exit(1)
if not isinstance(d['labels'], list):
    print('LABELS_NOT_LIST')
    sys.exit(1)
if not isinstance(d['body'], list):
    print('BODY_NOT_LIST')
    sys.exit(1)
" 2>&1; then
    fail "TC2 — ${tpl} YAML frontmatter invalid" "expected keys: name/description/title/labels/body"
    TC2_OK=0
  fi
done
if [ "$TC2_OK" -eq 1 ]; then
  pass "TC2 — all 5 templates have valid YAML frontmatter (5 keys each)"
fi

# TC3: ADR-0012 4-cat ≥3 categories pre-filled in `labels:`
section "TC3: AC2 — ADR-0012 4-cat compliance (≥3 categories pre-filled)"
TC3_OK=1
for tpl in "${CONTENT_TEMPLATES[@]}"; do
  path="${TEMPLATE_DIR}/${tpl}"
  cat_count=$(python3 -c "
import yaml
with open('${path}') as f:
    d = yaml.safe_load(f)
labels = d.get('labels', [])
cats = set()
for lbl in labels:
    if lbl.startswith('type:'): cats.add('type')
    elif lbl.startswith('status:'): cats.add('status')
    elif lbl.startswith('agent:'): cats.add('agent')
    elif lbl.startswith('cc:'): cats.add('cc')
print(len(cats))
" 2>/dev/null)
  cat_count=${cat_count:-0}
  if [ "$cat_count" -lt 3 ]; then
    fail "TC3 — ${tpl} has only ${cat_count}/4 ADR-0012 categories (need ≥3)" \
         "current labels: $(grep '^labels:' ${path})"
    TC3_OK=0
  else
    info "TC3 ${tpl}: ${cat_count}/4 categories (type/status/agent/cc)"
  fi
done
if [ "$TC3_OK" -eq 1 ]; then
  pass "TC3 — all 5 templates have ≥3/4 ADR-0012 categories pre-filled"
fi

# TC4: Drift correction — bug.yml + feature-request.yml contain Ownership rule markdown (Issue #113)
section "TC4: AC1 — Drift correction (Ownership rule Issue #113 in bug.yml + feature-request.yml)"
TC4_OK=1
for tpl in bug.yml feature-request.yml; do
  path="${TEMPLATE_DIR}/${tpl}"
  if ! grep -qE 'Ownership rule|Issue #113' "$path" 2>/dev/null; then
    fail "TC4 — ${tpl} missing Ownership rule markdown (drift from AtilCalculator parity)"
    TC4_OK=0
  fi
done
if [ "$TC4_OK" -eq 1 ]; then
  pass "TC4 — bug.yml + feature-request.yml contain Ownership rule (Issue #113) — drift corrected"
fi

# TC5: config.yml.tmpl exists (exempt from content checks)
section "TC5: AC1 — config.yml.tmpl exists (config file, exempt from 4-cat checks)"
if [ -f "${TEMPLATE_DIR}/config.yml.tmpl" ]; then
  pass "TC5 — config.yml.tmpl present (config file, 4-cat exempt per ADR-0012 scope)"
else
  fail "TC5 — config.yml.tmpl missing" "expected ${TEMPLATE_DIR}/config.yml.tmpl"
fi

# Summary
section "Summary"
printf "  ${G}PASS: %d${D}  ${R}FAIL: %d${D}  ${Y}INFO: %d${D}\n\n" "$PASS" "$FAIL" "$INFO"

if [ "$FAIL" -gt 0 ]; then
  printf "${R}✗ RED state — at least one TC failed${D}\n"
  exit 1
fi

printf "${G}✓ GREEN state — issue-template 4-cat compliance (STORY-S29-011) lands with all 5 ACs verified${D}\n"
exit 0