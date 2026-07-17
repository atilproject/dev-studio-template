# ADR-0066 — tmux-wake Fix 4b (lenient capture-pane verify + hierarchical exit code) — **template forward-port**

- **Status:** Proposed (Sprint 31 P1 cluster-squash Path A v26 step 1/3 template-side, tmpl#123)
- **Date:** 2026-07-17
- **Deciders:** @architect (doctrine + ADR author per file ownership matrix `docs/decisions/`), @tester (d-test `d1138-template` ≥5 TCs RED-first per ADR-0049), @developer (impl in `scripts/agent-wake.sh.tmpl` per file ownership matrix `scripts/`), @atilcan65 (owner squash gate per ADR-0031)
- **Parent ADR:** none (additive evolution 3 → 4, no amendment)
- **Refs:** tmpl#123 (cluster-squash Path A v26 step 1/3 template-side coordination, sister of AtilCalculator Issue #1138), atilproject/AtilCalculator Issue #1138 (already auto-CLOSED 2026-07-17T20:03:12Z prematurely by PR #1141 closes anchor — AC5 retroactively satisfied by this PR's MERGE), atilproject/AtilCalculator PR #1139 (✅ MERGED 2026-07-17T19:49:04Z, ADR-0066 calc-side docs), atilproject/AtilCalculator PR #1141 (✅ MERGED 2026-07-17T20:07:55Z, calc-side impl)
- **Sister-patterns:**
  - [ADR-0033-auto-ping-dual-channel](./ADR-0033-auto-ping-dual-channel.md) — dual-channel doctrine (Fix 4b preserves contract)
  - [ADR-0024-stale-verdict-watchdog-schema](./ADR-0024-stale-verdict-watchdog-schema.md) — auto-verdict-by hook precedent for §Cross-cutting concern
  - [ADR-0049-behavioral-workflow-test-framework](./ADR-0049-behavioral-workflow-test-framework.md) — d-test framework (≥5 TCs, sister-pattern) — closest tmpl-side equivalent to calc ADR-0044 RED-first
  - [ADR-0059-cluster-squash-batch-lag-detection](./ADR-0059-cluster-squash-batch-lag-detection.md) — cluster-squash doctrine (ADR + d-test + impl 3-PR atomic squash window)
  - [ADR-0060-claude-code-2.1.207-agent-flag](./ADR-0060-claude-code-2.1.207-agent-flag.md) — sister Sprint 31 cluster-squash template-side (KAPI hotfix dispatch)
  - RETRO-027-cadence-rule-2-retroactive-close-doctrine — template forward-port triggers when calc-side issue closes; prerequisite: doc-side trigger to fire mid-cluster (cycle ~#2912 live evidence)

## §Context

`scripts/agent-wake.sh.tmpl` (the dual-channel tmux-wake component template — every downstream project inheriting from this template ships a copy of this script that gets `dev-studio-init.sh`-rendered on project init) currently mirrors **Fix 3** (Issue #1063 hotfix) for capture-pane post-send verify:

```bash
# Fix 3 (Issue #1063): capture-pane post-send verify (current `.tmpl`)
MSG_PREFIX="${MSG%%$'\n'*}"
if [ "${#MSG_PREFIX}" -gt 80 ]; then
  MSG_PREFIX="${MSG_PREFIX:0:80}"
fi
if timeout 1 tmux capture-pane -t "$pane_id" -p 2>/dev/null | grep -qF "$MSG_PREFIX"; then
  # verified
  exit 0
fi
# not verified — exit 1
verify_rc=0
timeout 1 tmux capture-pane -t "$pane_id" -p 2>/dev/null | grep -qF "$MSG_PREFIX" || verify_rc=$?
echo "ERROR: capture-pane verify failed for role=$ROLE pane=$pane_id rc=$verify_rc (no match for prefix: $MSG_PREFIX)" >&2
exit 1
```

The Fix 3 false-failure pathology has been observed **6/6 times in Sprint 31 cycles ~#2855, ~#2857, ~#2858, ~#2861** on AtilCalculator (sister repo), all of which were raised in the calc-side Issue #1138 (live evidence table below).

**Cross-repo transfer rationale:** the same Fix 4b authored in [atilcan65/AtilCalculator ADR-0066](https://github.com/atilproject/AtilCalculator/blob/main/docs/decisions/ADR-0066-tmux-wake-fix-4b-lenient-verify-hierarchical-exit-code.md) (✅ MERGED 2026-07-17T19:49:04Z via PR #1139) MUST be forward-ported to this template, so downstream projects inheriting the template receive the fix on `dev-studio-init.sh` re-render (Cadence Rule 2, RETRO-027).

**Problem statement** (owner-observed across Sprint 31 cycles; AtilCalculator live evidence table reproduced verbatim from calc ADR-0066):

| Cycle | Pane | Send-keys | Verify | Telegram | GitHub artefact | Net wake |
|---|---|---|---|---|---|---|
| ~#2855 | dev %3 | OK | FAIL | OK | cmt 5004803619 fired | ✅ peer woke via pr_comment_mention |
| ~#2857 | arch %2 | OK | FAIL | OK | n/a (compensation posted) | ✅ peer woke via compensating pr_comment |
| ~#2858 | tester %4 | OK | FAIL | OK | n/a (compensation posted) | ✅ peer woke via pr_comment_mention |
| ~#2858 | dev %3 | OK | FAIL | OK | n/a (compensation posted) | ✅ peer woke via pr_comment_mention |
| ~#2858 | PM %1 | OK | FAIL | OK | n/a (compensation posted) | ✅ peer woke via pr_comment_mention |
| ~#2861 | PM %1 | OK | FAIL | OK | n/a (compensation posted) | ✅ peer woke via pr_comment_mention |

**6/6 false-failures, 6/6 actual delivery success via GitHub artefact path.** Script reporting is wrong, delivery is correct. Same pattern will manifest on template-rendered downstream projects unless Fix 4b is forward-ported.

**Root cause analysis** (mirror of calc ADR-0066 §Context):

1. **Timeout too tight** (hardcoded `timeout 1`): pane render lag on busy hosts exceeds 1s → capture-pane returns empty or stale content
2. **Prefix too long** (full 80-char `MSG_PREFIX`): whitespace/render drift in pane content (e.g., terminal width wrap, ANSI escape sequences in multi-line messages) corrupts literal-match
3. **Exit code undifferentiated**: send-keys OK + verify OK = exit 0, send-keys OK + verify FAIL = exit 1, send-keys FAIL = exit 1 — caller (notify.sh) cannot distinguish "definite failure" from "uncertain delivery" because both exit 1

## §Decision

Apply **Fix 4b** to `scripts/agent-wake.sh.tmpl` (additive evolution Fix 3 → Fix 4; preserves dual-channel contract per [ADR-0033](./ADR-0033-auto-ping-dual-channel.md)). All four components D1-D4 below are **byte-identical** to the calc-side ADR-0066 decision — template forward-port is a verbatim design transfer, not a re-design.

### D1. Configurable verify timeout (sister-pattern d068b `WAKE_KEYS_GAP_SEC`)

```bash
# Before
timeout 1 tmux capture-pane ...

# After
timeout "${WAKE_VERIFY_TIMEOUT_SEC:-3}" tmux capture-pane ...
```

- Default 3s (covers host render lag)
- `WAKE_VERIFY_TIMEOUT_SEC` env override (sister-pattern: `WAKE_KEYS_GAP_SEC` from d068b sleep discipline)

### D2. Lenient prefix match (whitespace/render-drift tolerant)

```bash
# Before
MSG_PREFIX="${MSG%%$'\n'*}"
if [ "${#MSG_PREFIX}" -gt 80 ]; then
  MSG_PREFIX="${MSG_PREFIX:0:80}"
fi
if timeout 1 tmux capture-pane ... | grep -qF "$MSG_PREFIX"; then ...

# After
# Fixed 16-char sentinel — robust against whitespace/render drift, terminal width wrap, ANSI escapes
VERIFY_SENTINEL="🔔 INBOX (dual-c"
timeout "${WAKE_VERIFY_TIMEOUT_SEC:-3}" tmux capture-pane ... | grep -qF "$VERIFY_SENTINEL" && ...
```

- Hardcoded 16-char sentinel `"🔔 INBOX (dual-c"` — covers `notify.sh -w -r <role>` prefix that **every** peer-poke / agent-watch wake uses
- Drops dynamic `MSG_PREFIX` first-line extraction (was the source of multi-line pollution)
- Decoupled from message content → render-drift immune

### D3. Hierarchical exit code (3-tier rc semantics)

| Scenario | Exit code | Stderr | Audit log signature |
|---|---|---|---|
| send-keys OK + verify OK | **0** | — | `Wake verified: role=X pane=Y` |
| send-keys OK + verify FAIL | **0** | WARN | `WARN: Wake injected but verify uncertain for role=X pane=Y (pane may have scrolled past MSG_PREFIX; text sent via send-keys)` |
| send-keys FAIL | **1** | ERROR | `ERROR: send-keys returned rc=N for pane=Y role=X` |

Caller (`notify.sh.tmpl`) rc semantics preserved: **exit 0 = delivered OR delivery-uncertain-but-sent, exit 1 = definite failure**.

**Rationale**: GitHub artefact path (`pr_comment_mention`, live evidence: 6/6 cycles) is the primary wake channel per [ADR-0033](./ADR-0033-auto-ping-dual-channel.md). tmux pane wake is the **secondary** deliverability channel. If send-keys succeeded but verify can't confirm pane state, the text was injected — the dual-channel contract is intact even if capture-pane can't see it. False-positive audit logs (6/6 cycles) are worse than accurate uncertainty.

### D4. Log discrimination (WARN vs ERROR separation)

Owner greppable inspection: `grep "WARN: Wake injected but verify uncertain"` vs `grep "ERROR: send-keys returned"`. This enables:
- Audit of how often verify-uncertain events occur (was 100% in Sprint 31; post-Fix 4b should drop to ~0% with 3s timeout)
- Hard failure detection still works (send-keys FAIL → exit 1)

## §Cross-script scope-expansion signal (cycle ~#2912 live evidence)

The impl Fix 4b on AtilCalculator (PR #1141, MERGED 2026-07-17T20:07:55Z) addresses `scripts/agent-wake.sh` only. It does NOT yet address `scripts/peer-poke.sh` — which uses similar capture-pane verify logic but with the old 80-char strict prefix and rc=1 on verify-fail.

**Live evidence (cycle ~#2912-#2916)**: `scripts/peer-poke.sh` tmux-wake calls returned `ERROR: capture-pane verify failed ... rc=1 (no match for prefix: 🔔 INBOX (dual-channel wake, notify.sh -w -r orchestrator):)`.

**Implication for tmpl forward-port**: the template forward-port should likely mirror Fix 4b on BOTH `scripts/agent-wake.sh.tmpl` AND `scripts/peer-poke.sh.tmpl` (or split into a separate sister-issue). Flagging for template-developer agent to decide scope (architecture supports expansion; doing both atomically simplifies cluster-squash). **Both paths preserved as AC2 + AC2a on tmpl#123.**

## §Why NOT Fix 4a (paste-buffer for multi-line)

Owner pushback (cycle ~#2861 directive, mirrored from calc ADR-0066): "ben mesajların gidişinde hic sorun görmedim" — multi-line send-keys DOES submit each line as a separate bash command (pane pollution), but the actual wake path (GitHub artefact `pr_comment_mention` per ADR-0002 autonomy loop) is unaffected. So Fix 4a is preventive for a problem that has not been observed in production.

**Out of scope for this ADR.** Defer to future Issue if/when owner observes a real multi-line pathology on a template-rendered downstream project.

## §Alternatives considered

- **(A) Drop verify entirely (always exit 0 after send-keys OK)**: Rejected — removes ALL audit signal, including legitimate send-keys failures. D3's WARN tier is the principled middle ground.
- **(B) Tighten verify (extend MSG_PREFIX to full message body, multiple capture-pane attempts)**: Rejected — addresses wrong problem (verify IS working, just for stale content). Doesn't address the real issue: send-keys OK + verify FAIL ≠ definite failure.
- **(C) Switch from grep -F to regex with whitespace tolerance**: Rejected — adds complexity without addressing root cause (sentinel-based match D2 is simpler and more robust).
- **(D) Re-design Fix 4b independently for tmpl context** (e.g., with shorter sentinel, different default timeout): Rejected — sister-pattern fidelity with calc-side is the whole point of template forward-port. Diverging design would defeat the purpose.

## §Consequences

### Positive

- Audit log accuracy improves dramatically downstream: WARN/ERROR separation lets owner greppable inspect which wakes were uncertain vs failed (mirror of calc ADR-0066 §Consequences)
- Caller (`notify.sh.tmpl`) rc semantics preserved (backward-compatible for downstream projects)
- Dual-channel contract per [ADR-0033](./ADR-0033-auto-ping-dual-channel.md) preserved across the template render boundary (GitHub artefact path is primary; tmux pane verify is secondary)
- Configurable timeout via env override allows per-host tuning across diverse downstream projects
- Sentinel-based prefix (D2) is render-drift immune
- Template-rendered downstream projects (Sprint 30+ kalıtım) automatically receive the Fix 4b invariants after `dev-studio-init.sh` re-render

### Negative

- EXIT 0 on verify-FAIL means caller scripts that *only* check `$?` will miss the WARN signal — must be paired with stderr capture (`2>&1` + grep WARN) for accurate audit (mirror of calc ADR-0066 §Negative)
- Default 3s timeout is longer than current 1s — minor latency increase on failure-path detection (acceptable trade for accuracy)

### Neutral

- No change to MSG content (still passes the full multi-line message to send-keys; Fix 4a would address this but is out of scope)
- No change to `peer-poke.sh.tmpl` wrapper or `notify.sh.tmpl` Telegram mirror (Fix 4b on `peer-poke.sh.tmpl` is a separate cluster-squash if AC2a scope-expansion is approved; sister-issue `tmpl#124` candidate)
- Sister-pattern with d068b `WAKE_KEYS_GAP_SEC` env override — same naming convention, different concern

## §Implementation contract

- **Location:** `scripts/agent-wake.sh.tmpl` (lines 97-118, Fix 3 verify block — byte-identical to calc-side `scripts/agent-wake.sh`)
- **Test:** d-test `scripts/tests/d1138-template-agent-wake-fix-4b-lenient-verify.sh` (≥5 TCs per [ADR-0049](./ADR-0049-behavioral-workflow-test-framework.md))
  - TC1: WAKE_VERIFY_TIMEOUT_SEC override applied (env var honored)
  - TC2: VERIFY_SENTINEL=16 chars `"🔔 INBOX (dual-c"` (literal match, no MSG derivation)
  - TC3: send-keys OK + verify OK → exit 0 (preserved)
  - TC4: send-keys OK + verify FAIL → exit 0 + stderr WARN (hierarchical)
  - TC5: send-keys FAIL → exit 1 + stderr ERROR (preserved)
  - TC6: bash -n syntactic validity (shellcheck baseline)
- **Cadence Rule 1 atomic:** this ADR + `scripts/tests/INDEX.md` row registered same commit (analog of calc ADR-0055 §1; tmpl-side INDEX equivalent updates are the forward-port anchor)
- **Cluster-squash inventory update:** this PR is **step 1/3** of the tmpl-side cluster-squash (mirror of calc Path A v26). Steps 2/3 (d-test `d1138-template` by tester, impl `agent-wake.sh.tmpl` by developer) are awaited on separate PRs per tmpl#123 AC1 + AC2.

## §Cross-cutting concerns

- **Cross-repo close-handling (`scripts/cross-repo-close.sh`, [ADR-0040](./ADR-0040-cross-repo-pr-auto-close.md))**: this ADR does NOT introduce cross-repo close actions. AtilCalculator Issue #1138 was auto-CLOSED prematurely by PR #1141's `Closes #1138 AC3+AC4` anchor (2026-07-17T20:03:12Z, before this template sister PR could land). This PR retroactively **References** #1138 (not Closes) to mark AC5 as forward-port evidence.
- **Auto-Verdict-By hook ([ADR-0024](./ADR-0024-stale-verdict-watchdog-schema.md))**: Fix 4b does NOT modify `peer-poke.sh.tmpl`'s `_pair_verdict_by` function or any label-check.yml auto-add path. Unaffected.
- **Sister cluster-squash Path A v25 inventory**: tmpl#94 (Phase B agent-wake-hotfix, CLOSED 2026-07-14) is the immediate precedent for this template-port pattern. PR #1141 (calc-side impl) is in `✅ MERGED` state — Fix 4b cluster (Path A v26) is now expanding to the template side per Cadence Rule 2.
- **Template forward-port sister PR contract** (per Cadence Rule 2, RETRO-027): when AtilCalculator cluster-squash Path A v26 step 1/3 (PR #1139 ADR-0066 docs) MERGED at 2026-07-17T19:49:04Z, this template-side sister dispatch fired mid-cluster (cycle ~#2912 live evidence). PR #1137 (RETRO-027 closeout, `Closes #1130`, owner-merge-pending on calc side) is the doctrinal basis for the Cadence Rule 2 retroactive-close precondition clause.

## §Open questions

- **Q1**: Does template-developer prefer AC2-only scope (`scripts/agent-wake.sh.tmpl` Fix 4b only) or AC2+AC2a combined scope (`scripts/agent-wake.sh.tmpl` + `scripts/peer-poke.sh.tmpl` Fix 4b)? — defer to template-developer lane (tmpl#123 owner: agent:developer, cc:architect — architect lane owns forward-port fidelity verification)
- **Q2**: Should the WARN log line include `MSG_PREFIX` content for diagnostic purposes, or only role/pane? — defer to template-developer / owner review (mirror of calc ADR-0066 §Q3)

## §References

- tmpl#123 (this ADR author directive + cluster-squash Path A v26 step 1/3 template-side coordination)
- AtilCalculator Issue #1138 (already auto-CLOSED 2026-07-17T20:03:12Z prematurely by PR #1141 closes anchor — AC5 retroactively satisfied)
- AtilCalculator PR #1139 (✅ MERGED 19:49:04Z, ADR-0066 calc-side docs)
- AtilCalculator PR #1140 (✅ MERGED 20:03:11Z, d1138 calc-side d-test)
- AtilCalculator PR #1141 (✅ MERGED 20:07:55Z, calc-side impl Fix 4b)
- AtilCalculator ADR-0066 (calc-side doctrinal basis — this ADR is byte-identical design transfer per Cadence Rule 2)
- AtilCalculator Issue #1063 Fix 3 (current verify — additive evolution 3 → 4)
- AtilCalculator Issue #1130 / PR #1137 (RETRO-027 — Cadence Rule 2 retroactive-close precondition)
- tmpl#94 (Phase B agent-wake-hotfix, CLOSED 2026-07-14 — immediate precedent for template-port cluster-squash)
- tmpl#122 / Issue #121 (most recent Sprint 31 forward-port cluster — coord-issue precedent, MERGED 2026-07-17T14:00:23Z)
- ADR-0040-cross-repo-pr-auto-close (cross-repo close handling doctrine)
- ADR-0057-closes-anchor-guard (parser-friendly Closes anchor doctrine)
- ADR-0059-cluster-squash-batch-lag-detection (cluster-squash doctrine)
- ADR-0060-claude-code-2.1.207-agent-flag (sister Sprint 31 cluster-squash template-side)
- Cycle ~#2832 (NEVER cite numbers from memory doctrine — applied here for "next #122" → actual #123 divergence on orchestrator dispatch)
- Cycle ~#2912 (Cadence Rule 2 dispatch ACK + peer-poke.sh live evidence showing peer-poke.sh also needs Fix 4b → AC2a)
- Cycle ~#2917 (PR #1141 MERGED event, upstream state update — atomically added AC2a to tmpl#123 body for peer-poke.sh.tmpl cross-script scope)
- Cycle ~#2919 (REPRIME-detected premature-close of AtilCalculator Issue #1138 — anchor correction applied here: `Refs #1138` not `Closes #1138`)

Cluster-squash coordination: agent:orchestrator (per AtilCalculator Issue #1138 cluster-squash doctrine, [ADR-0059](./ADR-0059-cluster-squash-batch-lag-detection.md)).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
