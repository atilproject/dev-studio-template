#!/usr/bin/env bash
# d1029-s29-setup-telegram-docs.sh — S29 setup-Telegram operator-recipe
# doc-content regression guard (template side, Issue #101 Phase B).
#
# Doctrinal contract (≥5 TCs baseline per ADR-0049 + `docs/sprints/current/plan.md`
#   "≥5 TCs behavioral, ≥3 TCs hygiene/docs"):
#   TC0: bash -n syntactic self-check (preflight on this d-test)
#   TC1: AC1 — docs/setup-Telegram.md exists + contains all 6 required sections
#        (§1 Overview, §2 Prerequisites, §3 Quickstart, §4 Verification,
#         §5 Troubleshooting, §6 Cross-references)
#   TC2: AC1 §3 — Quickstart section contains `scripts/install/dev-studio-install-env.sh`
#        invocation pattern (regression guard against tmpl Issue #100 install-env.sh
#        being renamed or removed — sister-pattern to d1028)
#   TC3: AC1 §6 — Cross-references section contains ≥4 references
#        (ADR-0033 dual-channel, ADR-0014 project-token-auth, Issue #100 install-env,
#         Issue #5 launcher arg pass-through OR equivalent cluster coord)
#   TC4: AC1 §5 — Troubleshooting section contains ≥3 failure-mode rows
#        (token rejected / chat not found / env not loaded / tmux session missing /
#         chat_id negative for group — at least 3 present)
#
# Doctrinal home: Issue #101 (Phase C arch docs, this PR) + tmpl Issue #100
#   (install-env.sh impl, BLOCKS recipe per cluster ordering) + launcher
#   Issue #5 (new-project.sh args, downstream consumer) + atilcan65/AtilCalculator#1058
#   (cluster coord, cross-repo sister per RETRO-023).
#
# Why this d-test exists
# ----------------------
# Issue #101 AC1 requires a NEW operator-facing doc `docs/setup-Telegram.md`
# covering dual-channel Telegram provisioning for fresh tmpl-rendered projects.
# The doc supersedes the legacy `docs/TELEGRAM-SETUP.md` (Turkish, manual
# .env hand-edit pattern) with a recipe that wires together:
#   - ADR-0033 dual-channel doctrine (the doc explains why)
#   - scripts/install/dev-studio-install-env.sh (the helper to invoke,
#     references tmpl Issue #100 cluster sister)
#   - launcher new-project.sh arg pass-through (downstream bootstrap,
#     references launcher Issue #5)
#
# Without a regression guard, the doc can drift:
#   - Quickstart section can drop the install-env.sh invocation pattern
#     (Issue #100 file gets renamed/removed → recipe references broken)
#   - Cross-references section can fall below 4 links (sister-pattern
#     weakens, scope ambiguity grows)
#   - Troubleshooting section can shrink below 3 rows (operator support
#     surface degrades, common failures unaddressed)
#
# This d-test enforces AC1's structural requirements statically — no
# execution, no live Telegram, no fake tmux session needed. Pattern
# sister to d1027 (`pyproject.toml.tmpl` static parse check) + d1018
# (`.tmpl` presence + content checks via grep) + d1020 (TOML parse
# + regex check). All 3 sister-patterns exist on tmpl main; d1029
# adds the 4th.
#
# RED-first per ADR-0044: TC0 PASSES (d-test syntactically valid). TC1,
#   TC2, TC3, TC4 all FAIL pre-impl (docs/setup-Telegram.md doesn't
#   exist on main). Post-impl: all 5 TCs GREEN.
#
# Cadence Rule 1 atomic (ADR-0055 §1): this d-test file + INDEX.md entry
#   + docs/setup-Telegram.md (the impl) land in same commit. Sister-
#   pattern per d096.
#
# Sister-patterns (≥3 per ADR-0049):
#   - d1026 (template env-decoupling port-parity) — template-side d-test
#     authoring conventions + INDEX.md format + check() helper pattern
#   - d1027 (template pyproject-tmpl render) — static `.tmpl` presence
#     + content checks via grep + Python parse, RED-first baseline
#   - d1028 (install-env-telegram d-test — Issue #100 sister) — direct
#     sister for this cluster, same S29 gap-closing scope, same RED-first
#     contract (referenced by Quickstart §3)
#   - d1018 (template ADR port-parity) — `.tmpl` content checks via grep
#   - d1020 (template workflow port-parity) — TOML parse-via-python +
#     regex check idiom
#   - d058 (no-live-peer-pane) — fake-session isolation (NOT needed here:
#     d1029 is static markdown checks, no execution surface)
#   - d081 (auto-verdict-by-hook on tmpl) — INDEX.md row format conventions
#
# Cross-refs:
#   - ADR-0033 (dual-channel doctrine — the doctrine this recipe explains)
#   - ADR-0014 (project-token-auth — env management reference)
#   - ADR-0044 (RED-first TDD doctrinal home)
#   - ADR-0049 (d-test framework ≥5 TCs baseline)
#   - ADR-0055 §1 (Cadence Rule 1 atomic)
#   - ADR-0059 (cluster-squash — sister-PRs land same merge-day per
#     Issue #101 cluster ordering: tmpl #100 → tmpl #101 + launcher #5)
#   - ADR-0031 (owner merge gate — only human squash-merges impl PR)
#   - Issue #101 (this story, Phase C arch docs)
#   - Issue #100 (sister cluster — install-env.sh impl, BLOCKS recipe
#     per cluster ordering)
#   - launcher Issue #5 (downstream consumer, arg pass-through)
#   - atilcan65/AtilCalculator#1058 (cluster coord, cross-repo sister
#     per RETRO-023 cross-repo workstream codification)
#   - TD candidate (Sprint 30+): consolidate docs/TELEGRAM-SETUP.md
#     (legacy Turkish) with new docs/setup-Telegram.md (English recipe)
#     to avoid operator confusion on dual-doc surface.

set -uo pipefail

DOC_FILE="docs/setup-Telegram.md"

# Resolve script dir (in case d-test is invoked from elsewhere)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOC_PATH="$REPO_ROOT/$DOC_FILE"

pass=0
fail=0

check() {
    if [ "${2:-FAIL}" = "PASS" ]; then
        echo "  ✅ $1"
        pass=$((pass+1))
    elif [ "${2:-FAIL}" = "INFO" ]; then
        echo "  ℹ️  $1: $3"
    else
        echo "  ❌ $1: $2"
        fail=$((fail+1))
    fi
}

require_dependencies() {
    local missing=0
    if ! command -v bash >/dev/null 2>&1; then
        echo "FATAL: bash not found in PATH" >&2
        missing=1
    fi
    if ! command -v grep >/dev/null 2>&1; then
        echo "FATAL: grep not found in PATH" >&2
        missing=1
    fi
    [ "$missing" -eq 0 ] || exit 2
}

require_dependencies

# -------------------------------------------------------------------------
# TC0 (preflight): bash -n syntactic validity of this d-test file
# -------------------------------------------------------------------------
if bash -n "$0" 2>/dev/null; then
    check "TC0 (bash -n self-check)" "PASS"
else
    check "TC0 (bash -n self-check)" "bash syntax error"
    exit 1
fi

# -------------------------------------------------------------------------
# TC1: AC1 — docs/setup-Telegram.md exists + contains all 6 required sections
# -------------------------------------------------------------------------
echo ""
echo "TC1: docs/setup-Telegram.md exists + ≥6 sections (Overview, Prerequisites, Quickstart, Verification, Troubleshooting, Cross-references)"

if [ ! -f "$DOC_PATH" ]; then
    check "TC1 (file exists + 6 sections)" "FAIL: $DOC_FILE does not exist on main (pre-impl RED expected)"
else
    # Extract all top-level (##) section headings from the doc
    SECTIONS=$(grep -E '^##[[:space:]]+' "$DOC_PATH" 2>/dev/null | \
               sed -E 's/^##[[:space:]]+//' | sed -E 's/[[:space:]]*$//' || true)

    REQUIRED_SECTIONS=("Overview" "Prerequisites" "Quickstart" "Verification" "Troubleshooting" "Cross-references")
    MISSING=()
    for req in "${REQUIRED_SECTIONS[@]}"; do
        # Case-insensitive substring match against section heading text
        if ! echo "$SECTIONS" | grep -qiF "$req"; then
            MISSING+=("$req")
        fi
    done

    if [ ${#MISSING[@]} -eq 0 ]; then
        check "TC1 (file exists + 6 sections)" "PASS"
    else
        check "TC1 (file exists + 6 sections)" \
            "FAIL: missing sections: ${MISSING[*]} (found: $(echo "$SECTIONS" | tr '\n' '|'))"
    fi
fi

# -------------------------------------------------------------------------
# TC2: AC1 §3 — Quickstart section contains install-env.sh invocation pattern
# -------------------------------------------------------------------------
echo ""
echo "TC2: Quickstart section contains scripts/install/dev-studio-install-env.sh invocation (regression guard against Issue #100 file rename)"

if [ ! -f "$DOC_PATH" ]; then
    check "TC2 (Quickstart install-env.sh ref)" \
        "FAIL: $DOC_FILE does not exist (pre-impl RED expected)"
else
    # Extract the Quickstart section (between ## Quickstart and the next ## heading)
    QUICKSTART_BLOCK=$(awk '
        /^##[[:space:]]+.*[Qq]uickstart/ { in_section=1; next }
        /^##[[:space:]]+/ { if (in_section) exit }
        in_section { print }
    ' "$DOC_PATH" 2>/dev/null || true)

    if [ -z "$QUICKSTART_BLOCK" ]; then
        check "TC2 (Quickstart install-env.sh ref)" \
            "FAIL: Quickstart section not found in $DOC_FILE"
    elif echo "$QUICKSTART_BLOCK" | grep -qF "scripts/install/dev-studio-install-env.sh"; then
        check "TC2 (Quickstart install-env.sh ref)" "PASS"
    else
        check "TC2 (Quickstart install-env.sh ref)" \
            "FAIL: Quickstart section does not reference scripts/install/dev-studio-install-env.sh (regression: Issue #100 file rename would break recipe)"
    fi
fi

# -------------------------------------------------------------------------
# TC3: AC1 §6 — Cross-references section contains ≥4 references
# -------------------------------------------------------------------------
echo ""
echo "TC3: Cross-references section contains ≥4 references (ADR-0033, ADR-0014, Issue #100, Issue #5 or equivalent)"

if [ ! -f "$DOC_PATH" ]; then
    check "TC3 (Cross-references ≥4)" \
        "FAIL: $DOC_FILE does not exist (pre-impl RED expected)"
else
    # Extract the Cross-references section
    XREFS_BLOCK=$(awk '
        /^##[[:space:]]+.*[Cc]ross-?[?[Rr]eferences/ { in_section=1; next }
        /^##[[:space:]]+/ { if (in_section) exit }
        in_section { print }
    ' "$DOC_PATH" 2>/dev/null || true)

    if [ -z "$XREFS_BLOCK" ]; then
        check "TC3 (Cross-references ≥4)" \
            "FAIL: Cross-references section not found in $DOC_FILE"
    else
        # Count references by looking for ADR-NNNN or Issue #N patterns
        ADR_COUNT=$(echo "$XREFS_BLOCK" | grep -cE 'ADR-[0-9]+' || true)
        ISSUE_COUNT=$(echo "$XREFS_BLOCK" | grep -cE '[Ii]ssue[[:space:]]*#?[0-9]+' || true)
        TOTAL_REFS=$((ADR_COUNT + ISSUE_COUNT))

        # Per Issue #101 AC1 §6: 4+ references required
        # Mandatory refs: ADR-0033, ADR-0014, Issue #100, Issue #5 (or equivalent)
        HAS_ADR0033=$(echo "$XREFS_BLOCK" | grep -cE 'ADR-0033' || true)
        HAS_ADR0014=$(echo "$XREFS_BLOCK" | grep -cE 'ADR-0014' || true)
        HAS_ISSUE100=$(echo "$XREFS_BLOCK" | grep -cE 'Issue[[:space:]]*#?100' || true)
        # Issue #5 might be referenced as launcher#5 or just "Issue #5"
        HAS_LAUNCHER5=$(echo "$XREFS_BLOCK" | grep -cE 'launcher.*#?5|Issue[[:space:]]*#?5' || true)

        if [ "$TOTAL_REFS" -ge 4 ] && [ "$HAS_ADR0033" -ge 1 ] && [ "$HAS_ADR0014" -ge 1 ] && [ "$HAS_ISSUE100" -ge 1 ] && [ "$HAS_LAUNCHER5" -ge 1 ]; then
            check "TC3 (Cross-references ≥4 + mandatory refs)" "PASS"
        else
            check "TC3 (Cross-references ≥4 + mandatory refs)" \
                "FAIL: total_refs=$TOTAL_REFS (need ≥4); ADR-0033=$HAS_ADR0033 ADR-0014=$HAS_ADR0014 Issue#100=$HAS_ISSUE100 Issue#5=$HAS_LAUNCHER5 (all mandatory refs must be ≥1)"
        fi
    fi
fi

# -------------------------------------------------------------------------
# TC4: AC1 §5 — Troubleshooting section contains ≥3 failure-mode rows
# -------------------------------------------------------------------------
echo ""
echo "TC4: Troubleshooting section contains ≥3 failure-mode rows (token rejected / chat not found / env not loaded / tmux missing / etc.)"

if [ ! -f "$DOC_PATH" ]; then
    check "TC4 (Troubleshooting ≥3 rows)" \
        "FAIL: $DOC_FILE does not exist (pre-impl RED expected)"
else
    # Extract the Troubleshooting section
    TROUBLE_BLOCK=$(awk '
        /^##[[:space:]]+.*[Tt]roubleshooting/ { in_section=1; next }
        /^##[[:space:]]+/ { if (in_section) exit }
        in_section { print }
    ' "$DOC_PATH" 2>/dev/null || true)

    if [ -z "$TROUBLE_BLOCK" ]; then
        check "TC4 (Troubleshooting ≥3 rows)" \
            "FAIL: Troubleshooting section not found in $DOC_FILE"
    else
        # Count "rows" by looking for table rows (| ... |) OR list items (- ... or * ...)
        # Exclude the section heading itself and blank lines
        TABLE_ROWS=$(echo "$TROUBLE_BLOCK" | grep -cE '^\|[[:space:]]*[^|]+' || true)
        LIST_ITEMS=$(echo "$TROUBLE_BLOCK" | grep -cE '^[[:space:]]*[-*][[:space:]]+' || true)
        # Use the larger of the two counts (table OR list format acceptable)
        ROW_COUNT=$((TABLE_ROWS + LIST_ITEMS))

        if [ "$ROW_COUNT" -ge 3 ]; then
            check "TC4 (Troubleshooting ≥3 rows)" "PASS"
        else
            check "TC4 (Troubleshooting ≥3 rows)" \
                "FAIL: only $ROW_COUNT rows found in Troubleshooting (need ≥3; table_rows=$TABLE_ROWS list_items=$LIST_ITEMS)"
        fi
    fi
fi

# -------------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "d1029 summary: pass=$pass fail=$fail"
echo "============================================================"

if [ "$fail" -eq 0 ]; then
    echo "✅ d1029 (S29 setup-Telegram docs) — all TCs GREEN"
    exit 0
else
    echo "❌ d1029 (S29 setup-Telegram docs) — $fail TC(s) FAIL (RED-first expected pre-impl)"
    exit 1
fi