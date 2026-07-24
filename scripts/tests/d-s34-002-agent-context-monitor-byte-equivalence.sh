#!/usr/bin/env bash
# d-s34-002-agent-context-monitor-byte-equivalence.sh — Sprint 34 W2 forward-port S34-002 row 001
#
# Verifies scripts/agent-context-monitor.sh in dev-studio-template is byte-equivalent
# to atilcan65/AtilCalculator canonical version. Per ADR-0075 §B.1, this script is
# `equivalent` class (Pure wake loop, no project context).
#
# Per ADR-0044 RED-first + ADR-0049 ≥6 TCs baseline + ADR-0055 §1 Cadence Rule 1 atomic.
#
# Usage: bash scripts/tests/d-s34-002-agent-context-monitor-byte-equivalence.sh
# Exit: 0 = all TCs GREEN, non-zero = TC failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_FILE="$SCRIPT_DIR/../agent-context-monitor.sh"
INDEX_FILE="$SCRIPT_DIR/INDEX.md"
CHANGELOG_FILE="$SCRIPT_DIR/../../CHANGELOG.md"

# AtilCalculator canonical MD5 + line count (byte-identical at S34-002 row 001,
# 2026-07-25T04:13Z verified via md5sum + wc -l per cycle ~#437 ground-truth probe)
EXPECTED_MD5="8062b3a267cb22e36069d9cd29733e58"
EXPECTED_LINES=325

failed=0

# TC1: target file exists in template
tc1_file_exists() {
  if [ -f "$TARGET_FILE" ]; then
    echo "✅ TC1: file exists at $TARGET_FILE"
    return 0
  else
    echo "❌ TC1: file MISSING at $TARGET_FILE"
    return 1
  fi
}

# TC2: file line count = 325 (matches AtilCalculator canonical)
tc2_line_count() {
  local lines
  lines=$(wc -l < "$TARGET_FILE")
  if [ "$lines" -eq "$EXPECTED_LINES" ]; then
    echo "✅ TC2: line count = $lines (matches canonical $EXPECTED_LINES)"
    return 0
  else
    echo "❌ TC2: line count = $lines (expected $EXPECTED_LINES)"
    return 1
  fi
}

# TC3: MD5 sum matches canonical AtilCalculator (byte-equivalence proof)
tc3_md5_match() {
  local actual_md5
  actual_md5=$(md5sum "$TARGET_FILE" | awk '{print $1}')
  if [ "$actual_md5" = "$EXPECTED_MD5" ]; then
    echo "✅ TC3: MD5 = $actual_md5 (byte-identical to AtilCalculator canonical)"
    return 0
  else
    echo "❌ TC3: MD5 = $actual_md5 (expected $EXPECTED_MD5)"
    return 1
  fi
}

# TC4: no project-specific paths (pure wake loop, no project context per ADR-0075 §B.1)
tc4_no_project_paths() {
  local grep_result
  grep_result=$(grep -E "(atilcan65|atilproject)/AtilCalculator|atilproject/dev-studio-(template|launcher)" "$TARGET_FILE" 2>&1 || true)
  if [ -z "$grep_result" ]; then
    echo "✅ TC4: no project-specific paths (pure wake loop confirmed per ADR-0075 §B.1)"
    return 0
  else
    echo "❌ TC4: project-specific path found: $grep_result"
    return 1
  fi
}

# TC5: key function signatures present (parse_context_pct, send_compact per script purpose)
tc5_key_functions() {
  if grep -q "context_pct\|parse_context" "$TARGET_FILE" && grep -q "/compact\|send_compact" "$TARGET_FILE"; then
    echo "✅ TC5: key function signatures present (context_pct + send_compact)"
    return 0
  else
    echo "❌ TC5: missing key function signatures (context_pct and/or send_compact)"
    return 1
  fi
}

# TC6: scripts/tests/INDEX.md row exists for this d-test (Cadence Rule 1 atomic marker)
tc6_index_row() {
  if grep -q "d-s34-002-agent-context-monitor-byte-equivalence" "$INDEX_FILE"; then
    echo "✅ TC6: INDEX.md row present (Cadence Rule 1 atomic marker per ADR-0055 §1)"
    return 0
  else
    echo "❌ TC6: INDEX.md row MISSING for d-s34-002-agent-context-monitor-byte-equivalence"
    return 1
  fi
}

# TC7: CHANGELOG.md entry exists for Sprint 34 W2 forward-port S34-002 row 001
tc7_changelog_entry() {
  if grep -q "Sprint 34 W2 forward-port S34-002" "$CHANGELOG_FILE" && grep -q "scripts/agent-context-monitor.sh" "$CHANGELOG_FILE"; then
    echo "✅ TC7: CHANGELOG.md entry present (Sprint 34 W2 forward-port S34-002)"
    return 0
  else
    echo "❌ TC7: CHANGELOG.md entry MISSING for Sprint 34 W2 forward-port S34-002"
    return 1
  fi
}

# Run all TCs (RED-first per ADR-0044 — initial run with INDEX/CHANGELOG missing will FAIL on TC6/TC7)
for tc in tc1_file_exists tc2_line_count tc3_md5_match tc4_no_project_paths tc5_key_functions tc6_index_row tc7_changelog_entry; do
  if ! $tc; then
    failed=$((failed + 1))
  fi
done

echo ""
if [ "$failed" -eq 0 ]; then
  echo "✅ All 7 TCs GREEN — Sprint 34 W2 forward-port S34-002 row 001 verified"
  echo "   Source-of-truth sister: atilcan65/AtilCalculator/scripts/agent-context-monitor.sh"
  echo "   MD5: $EXPECTED_MD5 (byte-identical)"
  echo "   Lines: $EXPECTED_LINES"
  exit 0
else
  echo "❌ $failed TC(s) failed — RED-first contract per ADR-0044"
  exit 1
fi