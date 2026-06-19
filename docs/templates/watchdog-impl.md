## Watchdog impl template — based on PR #108 (ADR-0024 stale-verdict)

**Source**: PR #108 — `feat(watchdog): ADR-0024 stale-verdict schema impl (refs #46, TD-006)` (MERGED 2026-06-19T05:02:32Z, commit 0d7c13c)

**Reusable for**: Any future watchdog/agent-watch.sh change that adds (a) new event kinds, (b) new query functions, (c) shim windows for back-compat, or (d) regression tests with d0XX-*.sh naming.

---

### 1. Code structure (scripts/agent-watch.sh)

When adding a new query function `query_<name>` to the watchdog, follow this skeleton:

```bash
# v<N+1> (<ADR-NNNN>): query_<name> — <one-line description>.
#
# <2-3 line description of what this query detects and what event kind it emits.>
# <Cites the ADR; explains the event ID format and throttle scheme.>
# <Notes the kill switch / env var if any.>
query_<name>() {
  local now_epoch bucket
  now_epoch="$(date -u +%s)"
  bucket=$(( now_epoch / 300 ))   # 5-min bucket for re-fire throttle

  gh pr list \
    --repo "$REPO" \
    --label "cc:${ROLE}" \
    --state open \
    --limit 50 \
    --json number,title,url,updatedAt,headRefOid,labels \
    --jq --argjson now_epoch "$now_epoch" "[
      .[] |
      ...filter expression...
      {
        id: (\"<kind>-<n>-<sha7>-b${bucket}\"),
        kind: \"<kind>\",
        number: .number,
        title: .title,
        url: .url,
        updated_at: .updatedAt,
        context: {
          ...role-specific context fields...
        }
      }
    ]"
}
```

**Naming conventions** (enforced by ADR-0024 + this template):
- Event kind: lowercase, snake_case (`stale_verdict`, `missing_expectation`, `queue_empty_but_priority_pending`)
- Event ID prefix: same as event kind with hyphens (`stale-verdict-`, `missing-expectation-`, `queue-empty-priority-`)
- Throttle bucket: 5-min (`now_epoch / 300`) for time-based events; no bucket for state-based events (head_sha is the dedup key)

---

### 2. Shim pattern (when changing watchdog behavior)

When replacing an existing event kind (e.g., `stale_cc` → `stale_verdict`), emit BOTH during a back-compat window:

```bash
# At the top of agent-watch.sh (after existing env var reads):
SHIM_END="${<NEW>_SHIM_END:-<ISO_DATE>}"
LEGACY_KILL_SWITCH="${<NEW>_LEGACY_<OLD_KIND>:-false}"

# In poll_once, replace the old query call with:
local now_epoch_shim shim_end_epoch
now_epoch_shim="$(date -u +%s)"
shim_end_epoch="$(date -u -d "$SHIM_END" +%s 2>/dev/null || echo 9999999999)"
if [ "$now_epoch_shim" -lt "$shim_end_epoch" ] || [ "$LEGACY_KILL_SWITCH" = "true" ]; then
  <old_query_result>="$(query_<old> 2>/dev/null || echo '[]')"
else
  <old_query_result>='[]'
fi
<new_query_result>="$(query_<new> 2>/dev/null || echo '[]')"

# Add both to the jq -s merge input list.
```

**Default shim window**: 1 sprint (14 days). Default shim end: `${TODAY_SPRINT_END_DATE}T00:00:00Z`.

**Kill switch semantics**: When false (default after shim end), the old behavior is suppressed. When true, the old behavior is re-enabled regardless of shim window. This allows emergency rollback without a code revert.

---

### 3. Regression test pattern (scripts/tests/d0NN-*.sh)

When adding a new watchdog event kind, add a d0NN regression test that covers static + behavioral semantics:

```bash
#!/usr/bin/env bash
# d0NN-<short-slug>.sh — regression test for ADR-NNNN + Issue #NN.
#
# <What the test defends against: which bug class, which silent failure modes.>
# <Cites the ADR + Issue.>
#
# Test cases (T1..TN):
#   T1: <static: function exists, defaults, env var reads>
#   T2: <static: event ID format>
#   T3: <behavioral: emit when condition met>
#   T4: <behavioral: do NOT emit when condition NOT met>
#   T5: <behavioral: edge case — empty array, malformed input>
#   T6: <shim: past/present/future dispatch behavior>
#   T7: <kill switch: legacy override behavior>
#   T8: <integration: poll_once merges the new event kind>

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH_SH="$SCRIPT_DIR/../agent-watch.sh"

# Colors (TTY-aware)
if [[ -t 1 ]]; then G=$'\033[0;32m'; R=$'\033[0;31m'; B=$'\033[1m'; D=$'\033[0m'
else G=""; R=""; B=""; D=""; fi

PASS=0; FAIL=0
pass() { printf "  ${G}✓ PASS${D} — %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}✗ FAIL${D} — %s\n" "$1"; [ -n "${2:-}" ] && printf "    ${R}%s\n" "$2"; FAIL=$((FAIL+1)); }
section() { printf "\n${B}==== %s ====${D}\n" "$1"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required" >&2; exit 127
fi
if [ ! -r "$WATCH_SH" ]; then
  echo "ERROR: agent-watch.sh not found at $WATCH_SH" >&2; exit 127
fi

# ============================================================================
# Test cases T1..TN (see header for descriptions)
# ============================================================================

section "T1: query_<name> function exists"
if grep -Eq '^query_<name>\(\) \{' "$WATCH_SH"; then
  pass "query_<name>() defined at top level"
else
  fail "query_<name>() not found" "expected function definition in scripts/agent-watch.sh"
fi

# ... (repeat for T2..TN) ...

# ============================================================================
# Summary
# ============================================================================
printf "\n${B}==== SUMMARY ====${D}\n"
printf "  ${G}PASS${D}: %d\n" "$PASS"
printf "  ${R}FAIL${D}: %d\n" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
```

**Test count target**: 10-15 cases per watchdog change. PR #108 had 15 cases.

**Coverage matrix** (mandatory):

| Dimension | Cases required |
|---|---|
| Static: function existence | T1 |
| Static: env var defaults | T2 |
| Static: event ID format | T3 |
| Behavioral: positive case | T4 |
| Behavioral: negative case (no event) | T5 |
| Behavioral: edge case | T6 |
| Shim: inside-window | T7 |
| Shim: past-window | T8 |
| Shim: kill-switch override | T9 |
| Integration: poll_once merge | T10 |

**Numbering**: Increment from the latest d0NN. Current list: d006 (event IDs), d007 (api observability), d011 (status action driver), d012 (stale-verdict schema). Next: d013.

---

### 4. PR template (for any watchdog impl)

```bash
gh pr create --draft --head <branch-name> \
  --title "feat(watchdog): <ADR-NNNN> <short-slug> impl (refs #NN, <TD-NNNN>)" \
  --body "$(cat <<'EOF'
## What
<One paragraph: what this PR changes in the watchdog.>

## Why
Closes #NN (<issue title>). <Cite the ADR — what was decided and why.>

## How
- **query_<name>()** (scripts/agent-watch.sh): <one-line>
- **Shim dispatch** in poll_once: <one-line — when both old + new fire, when kill switch applies>
- **N-case regression test** (scripts/tests/d0NN-<slug>.sh): <one-line — what's covered>

## Acceptance criteria
- [x] <AC1>
- [x] <AC2>
- [ ] <AC3 — needs deployment validation>

## Test plan
- Unit: scripts/tests/d0NN-<slug>.sh (N cases — all green)
- Integration: TBD after deploy — <observation plan>
- Manual: <commands to verify behavior>

## Risk
Low — additive change. <Or Medium/High if not.>

## Rollback plan
<ENV_VAR>=true re-enables old behavior. <Or revert PR + redeploy.>

## Checklist
- [x] Tests added / updated
- [x] Lint passes locally (bash -n)
- [x] Type-check passes locally (N/A — bash)
- [x] Self-review done
- [x] Design doc followed (ADR-NNNN §<section> implemented as specified)
- [ ] Architect reviewed
- [ ] Tester signed off
- [ ] Human owner approved
EOF
)" \
  --label "type:feature" \
  --label "status:in-review" \
  --label "agent:developer" \
  --label "cc:tester" \
  --label "needs-tester-signoff" \
  --label "needs-architect-review"
```

---

### 5. Companion files (per watchdog impl)

Beyond the 3 core (impl + dispatch + test), also update:

| File | What to update |
|---|---|
| `scripts/agent-watch.sh` header docstring | Add Event Model version line + new event kinds to the kinds list |
| `scripts/agent-watch.sh` Env section | Add new env vars with defaults + kill switch notes |
| `scripts/agent-watch.sh` kinds list (line ~55) | Add new kinds to the JSON output kind enum |
| `docs/decisions/INDEX.md` | Reference the ADR (if new ADR) or update existing ADR's "Last amended" date |
| `docs/tech-debt.md` | Mark any related TD entries as resolved (if applicable) |

---

### 6. Real-world examples (PR #108 applied this template)

| Step | PR #108 actual | Source |
|---|---|---|
| Function skeleton | `query_stale_verdict()` + `query_missing_expectation()` | scripts/agent-watch.sh |
| Shim pattern | `VERDICT_SHIM_END` + `VERDICT_LEGACY_STALE_CC` | scripts/agent-watch.sh (env vars + poll_once) |
| Regression test | `d012-stale-verdict-schema.sh` (15 cases) | scripts/tests/ |
| PR template | title `feat(watchdog): ADR-0024 stale-verdict schema impl (refs #46, TD-006)` + 6 labels | gh pr create |
| Companion updates | Header docstring (v6 + 2 new kinds) + Env section (VERDICT_*) + kinds list | scripts/agent-watch.sh |

---

### 7. Anti-patterns (avoid)

- ❌ Renaming an existing event kind in-place (breaks processed_event_ids dedup across agents)
- ❌ Adding a new event kind without a regression test (silent failure risk)
- ❌ Skipping the shim window (forces synchronized agent rollout)
- ❌ Using `--arg` for numeric values in jq (use `--argjson` to avoid lexicographic comparison bugs)
- ❌ Hardcoding bucket intervals differently across queries (inconsistent throttle behavior)
- ❌ Forgetting the kinds list in the JSON output enum (test fixtures won't match)
- ❌ Editing `.claude/` files directly (human-only — propose via PR or issue)
- ❌ Opening PR without `needs-architect-review` label when the change is ADR-derived

---

### 8. Cross-references (post-merge actions)

- Issue #109 (doctrine amendment) — the bounded-standby companion. PR #108 reduced spam (less wake noise); Issue #109's queue-empty detector breaks agents out of standby when there's P0 work.
- `docs/tech-debt.md` TD-006 — umbrella TD; entry should be updated to reflect the resolution mapping.
- `docs/retros/` — file a retro entry (A?) for the spam-class fix if not already filed.

---

**Status**: This template is ready for re-use. Next likely use cases:
1. `query_queue_empty_with_priority` (Issue #109 §2) — bounded-standby complement
2. Per-PR `verdict-by:` warning (when a PR has `cc:<role>` but no `verdict-by:<ts>` for >1 day) — separate issue
3. Watchdog rewrite for `pr_labeled` schema (if ADR-NNNN future amendment warrants it)

The template owner is @developer. Modifications to this template go through PR review (per the file ownership matrix — `scripts/` is shared infra).
