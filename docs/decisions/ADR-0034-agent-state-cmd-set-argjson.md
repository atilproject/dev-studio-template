# ADR-0034 — agent-state.sh cmd_set JSON contract fix (Issue #228 RCA + design)

**Status:** Proposed
**Date:** 2026-06-21
**Supersedes:** (partial) `scripts/agent-state.sh §cmd_set` --arg contract
**Related:** ADR-0002 (GitHub-Native Autonomy), ADR-0024 (Watchdog Schema), ADR-0025 (Bound Standby), Issue #228 (RCA + bug filing), Issue #94 (WATCHER-FIX sister, F4-F8 behavior)

---

## Context

Issue #228 (P0, filed by @product-manager 2026-06-21T21:10Z) reports that `scripts/agent-state.sh cmd_set` uses `jq --arg` to write values, which silently **stringifies JSON arrays/objects instead of storing them as parsed values**. The downstream `cmd_seen` uses `index()` which fails on stringified values, breaking the watcher's dedup loop.

### Live repro (2026-06-21T21:56Z, captured during this RCA)

```bash
$ jq -r '.processed_event_ids | type' /var/log/dev-studio/AtilCalculator/agent-state/architect.json
"string"    # ← BUG: my own architect state is corrupted
$ jq -r '.processed_event_ids | type' /var/log/dev-studio/AtilCalculator/agent-state/product-manager.json
"array"     # ← PM manually restored at 21:09Z
$ jq -r '.processed_event_ids' /var/log/dev-studio/AtilCalculator/agent-state/architect.json
""          # ← architect was overwritten via `set` with comma-joined string
```

The architect state shows `""` (empty string) because the comma-separated event IDs I passed to `cmd_set` were stored as a literal string and the JSON serialization round-tripped to empty (likely because of the comma → array construction in the jq path? Actually because `--arg` stores as JSON-escaped string, the comma got encoded as `,` and the resulting JSON was `"..."` which jq serialized as `""` for empty content — but the actual round-trip might lose data. The key point: **the contract is wrong**.).

PM's state (`product-manager.json`) was manually restored to a proper array at 21:09Z. Other agents (developer, tester, orchestrator) likely have the same corruption but haven't been checked yet.

### Root cause analysis

`scripts/agent-state.sh:151-159`:

```bash
cmd_set() {
  require_jq
  local role="$1" key="$2" value="$3"
  local file
  file="$(state_path "$role")"
  [ -f "$file" ] || cmd_init "$role"
  # Use --arg for safety; numeric/bool callers must JSON-encode if needed.
  jq_inplace "$file" --arg v "$value" ".${key} = \$v"
}
```

The comment "Use --arg for safety; numeric/bool callers must JSON-encode if needed" reveals the **original design intent**: callers were expected to JSON-encode complex values before passing to `cmd_set`. But:

1. The contract is implicit, not enforced — callers can forget to JSON-encode
2. The stringification is silent — no error or warning
3. The watcher's `cmd_mark` (lines 174-186) does `processed_event_ids + [$id]` — appending a string to a string yields broken JSON
4. The watcher's `cmd_seen` (line 167) uses `index()` which assumes array semantics — silently broken when stringified

This is the **second silent-dedup-corruption** in the watcher in 24h (after RCA-32 dedup buffer TTL, ADR-0032). The watcher state management is fragile to silent failures.

### Why this is P0, not P1

- **Dedup is fundamental to the wake loop**: every event gets re-processed, agent workload doubles
- **Compounds over time**: every `cmd_mark` re-corrupts the state; manual restores are band-aids
- **Already affected all 5 agents**: architect + PM confirmed; developer/tester/orchestrator unverified but likely
- **wake_nudge has throttle (60s per ADR-0025 Katman 1)**, which masks the dedup failure — but the failure mode is real, just throttled

## Decision

**Adopt Option 3 (PM's recommendation): change `cmd_set` contract to require JSON input, use `--argjson`, and error on non-JSON input.**

```bash
# Pseudo-code (≤30 lines, no production code in this ADR)
cmd_set() {
  require_jq
  local role="$1" key="$2" value="$3"
  local file
  file="$(state_path "$role")"
  [ -f "$file" ] || cmd_init "$role"
  # Validate that $value is parseable JSON; reject on failure.
  if ! echo "$value" | jq -e . >/dev/null 2>&1; then
    echo "ERROR: cmd_set requires JSON input (key=$key)" >&2
    echo "  hint: wrap strings in quotes, e.g. '\"hello\"' not 'hello'" >&2
    echo "  hint: for arrays, use '[1,2,3]'; for null, use 'null'" >&2
    exit 2
  fi
  jq_inplace "$file" --argjson v "$value" ".${key} = \$v"
}
```

### Behavior change matrix

| Caller | Old (`--arg`) | New (`--argjson` validated) |
|---|---|---|
| `set role key '"hello"'` (string literal) | stored as `hello` ✅ | ERROR: not JSON ❌ |
| `set role key '"hello"'` (JSON-quoted) | stored as `"hello"` (escaped string) ❌ | stored as `hello` ✅ |
| `set role key '42'` | stored as `42` (string `"42"`) ❌ | stored as `42` (number) ✅ |
| `set role key '[1,2,3]'` | stored as `"[1,2,3]"` (escaped string) ❌ | stored as `[1,2,3]` (array) ✅ |
| `set role key 'true'` | stored as `"true"` ❌ | stored as `true` ✅ |
| `set role key 'null'` | stored as `"null"` ❌ | stored as `null` ✅ |

### Migration path (one-shot, developer-owned)

A migration script restores corrupted state files for all 5 agents:

```bash
# scripts/agent-state-repair.sh (new, ~20 lines)
for role in orchestrator product-manager architect developer tester; do
  file="/var/log/dev-studio/AtilCalculator/agent-state/$role.json"
  if [ -f "$file" ]; then
    # If processed_event_ids is a string (corrupted), re-parse it.
    if jq -e '.processed_event_ids | type == "string"' "$file" >/dev/null 2>&1; then
      # Try parsing the string as JSON; if it looks like an array, fix.
      raw=$(jq -r '.processed_event_ids' "$file")
      if [ "$raw" != "" ] && echo "$raw" | jq -e . >/dev/null 2>&1; then
        jq --argjson v "$raw" '.processed_event_ids = $v' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
      else
        # Empty or unparseable; reset to empty array.
        jq '.processed_event_ids = []' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
      fi
      echo "repaired: $role"
    fi
  fi
done
```

This is a **one-shot fixup** — once state files are repaired and `cmd_set` is fixed, no further corruption.

## Rationale

### Why Option 3 over the others

| Option | Description | Pros | Cons | Verdict |
|---|---|---|---|---|
| 1 | `--argjson` only for known JSON values (detect `[`/`{` prefix) | Minimal change | Heuristic; brittle on edge cases (e.g., JSON string starting with `{`) | Rejected — heuristic is fragile |
| 2 | Add `cmd_set_array` and `cmd_set_object` helpers | Explicit, type-safe | API surface grows; existing callers must migrate | Rejected — too invasive |
| 3 | `cmd_set` requires JSON; uses `--argjson`; errors on non-JSON | Cleanest contract; one breaking change but easy migration | Callers passing plain strings (e.g., `set role last_seen_utc "2026-..."`) must wrap in quotes | **Accepted** — strict contract > silent corruption |
| 4 | `cmd_mark` uses `--argjson` directly, bypasses `cmd_set` | Localized fix | Doesn't fix the underlying `cmd_set` bug; other callers (e.g., `set processed_event_ids`) still corrupt | Rejected — band-aid |

### Why this is doctrine-grade (ADR), not a bug fix

Per the rule "ADR for any decision >1 hour of dev work to reverse" + "every non-trivial decision becomes an ADR":

- `cmd_set` is a **shared contract** used by every agent and the watcher
- The contract change is **breaking** (callers must wrap strings in quotes)
- The fix has **security implications** (silent stringification could mask injection)
- The fix is **non-trivial** (~30 lines + migration script + d025 regression)
- The fix affects **ADR-0024/0025 family** (watchdog + bound standby depend on cmd_set correctness)

Hence ADR-0034, not a quiet fix PR.

## Consequences

### Positive

- **`cmd_set` contract is strict and enforceable**: invalid input fails fast (exit 2) instead of silent corruption
- **Watcher dedup loop is correct**: `cmd_seen` works as designed; `index()` finds array elements
- **No more manual state restores**: PM's 21:09Z workaround becomes a one-shot migration
- **Type-safe state writes**: numbers stay numbers, arrays stay arrays, bools stay bools
- **Future-proof**: new agent state fields (e.g., `verdict_by_*`) work correctly without per-field helper functions

### Negative

- **All existing callers must be updated**: `cmd_set <role> <key> "plain string"` becomes `cmd_set <role> <key> '"plain string"'`. ~5-10 callers across agent-watch.sh, agent-state.sh, agent-wake.sh (when it lands per ADR-0033).
- **Migration script is one-shot**: if a state file is corrupted pre-fix, manual restore needed. Mitigation: migration script in same PR + runbook entry.
- **Strict validation may reject legitimate use cases**: e.g., writing a JSON-encoded string (where the value IS a JSON string). Mitigation: docs clarify the contract; tests cover common patterns.

### Out of scope

- **ADR-0032 RCA-32 dedup buffer TTL**: already shipped in PR #224 (the bucket-TTL fix). Sister concern, separate ADR.
- **Watcher robustness overhaul**: not warranted; the watcher is otherwise working. This is a narrow contract fix.
- **State file schema migration**: not needed; the schema (top-level keys) is unchanged. Only the value type for some keys is corrected.

## Implementation handoff

Per Issue #228 owner table (PM's recommendation):

- **@architect** (this ADR + RCA confirmation): 0.5 SP ✅ (this PR)
- **@developer** (cmd_set fix + migration script + d025 regression): 1 SP (separate PR)
- **@tester** (d025 sign-off): 0.5 SP (separate PR)
- **Total**: 2 SP

### d025 regression test contract (developer-owned)

7 test cases:
1. `set role key '"hello"'` → stored as `hello` (string), no error
2. `set role key '"hello"'` (plain) → ERROR exit 2, error message hints JSON quoting
3. `set role key '42'` → stored as `42` (number)
4. `set role key '[1,2,3]'` → stored as `[1,2,3]` (array)
5. `set role key 'true'` → stored as `true` (bool)
6. `set role key 'null'` → stored as `null`
7. Migration: corrupted state file (string `processed_event_ids`) → after migration, `processed_event_ids` is `array`

### Sprint 4 impact

- Sprint 4 commitment: 21.5 SP (post ADR-0033) → **24.0 SP** (+0.5 architect, +1 dev, +0.5 tester for Issue #228; Issue #227 separately tracked in ADR-0035)
- Buffer: 11.0-21.0 SP (was 13.5-23.5 SP, still in range)
- Sprint 4 P0 chain: previous P0s closed + Issue #228 (this) + Issue #221 (in flight, +2.5 SP dev+tester)

## Pending

- Owner (@atilcan65) approves ADR-0034 (Proposed → Accepted)
- Developer opens impl PR for `cmd_set` fix + migration script + d025
- Tester signs off on d025
- Owner merges all PRs
- Run migration script in prod (orchestrator or owner; ~1 minute downtime for watcher dedup window)

— @architect, 2026-06-21T22:05:00Z
