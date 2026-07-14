# ADR-0060: Claude Code 2.1.207 — Remove `--agent` flag from custom agent invocation

- **Status**: Proposed
- **Date**: 2026-07-14
- **Deciders**: @architect (doctrine), @developer (impl in `scripts/dev-studio-start.sh`), @tester (dNNNN-cli-arg-hygiene d-test RED-first per ADR-0044), @atilcan65 (owner squash gate per ADR-0031)
- **Closes**: Issue #88 (template-gap-close, sprint:current, priority:P1)
- **Sister-patterns**:
  - ADR-0059 (cluster-squash-batch-lag-detection — Sprint 28 forward-port neighbor)
  - ADR-0024 (verdict-by time-anchor pattern)
  - ADR-0049 (d-test framework — TC contract)
  - ADR-0055 §1 (Cadence Rule 1 atomic — impl + d-test in same PR cluster)
  - ADR-0031 (owner squash gate — terminal hand-off)
  - ADR-0044 (RED-first TDD)

> **§20.1 reservation supersession note**: This ADR repurposes the Sprint 28 audit-baseline §20.1 ADR-0060 reservation (originally "§AC Mapping Verification Doctrine"). The reservation was un-authored on the template repo (AtilCalculator ADR-0060 IS authored as AC Mapping, 15KB, 2026-07-01). Per RETRO-018 W6, un-authored reservations may be repurposed when an explicit gap-closing item claims the number. The AC Mapping doctrine retains its canonical home as AtilCalculator ADR-0060.

## Context

### Claude Code CLI 2.1.207 breaking change (2026-07-14 03:31 mtime)

The Claude Code CLI release 2.1.207 introduced a breaking change to custom agent discovery:

- `claude --help` output **no longer lists custom agents** from `.claude/agents/<role>.md`
- Built-in agents only: `claude`, `claude-code-guide`, `Explore`, `general-purpose`, `Plan`, `statusline-setup`
- `claude --agent "${role}"` invocation now fails with `--agent '<role>' not found`
- `scripts/dev-studio-start.sh` heredoc (line 149) hits this and all 5 panes fall back to shell (no soul identity loaded)

### Impact (Sprint 29 cycle ~#1180 incident)

Without the fix:

- All 5 agent panes (orch/pm/arch/dev/tester) launch as generic Claude Code, no soul identity
- `agent-watch.sh` per-role queue polling works at the OS level (systemd user units), but each pane has no soul context (no role-bound behavior, no peer discipline)
- Manual tmux per-pane system prompt injection would be needed (fragile, not in doctrine)

### Test evidence (AtilCalculator restart 2026-07-14, prod-verified)

Local fix propagated: removed `--agent "${role}"` flag from local `scripts/dev-studio-start.sh` and restarted. Verified:

- ✅ 5 panes launched successfully (tmux window:main, panes 0.0–0.4)
- ✅ 5 watchers active (`systemctl --user list-units dev-studio-watcher@*`)
- ✅ Orchestrator queue resumed processing post-restart
- ✅ Agent identity smoke test: claude confirmed as AtilCalculator Orchestrator role
- ✅ Watcher log path: `/var/log/dev-studio/AtilCalculator/{role}.watch.log` (all 5 streams active)

### Root cause

The `--agent "${role}"` flag was a **pre-2.1.207 convenience** that auto-loaded the matching built-in agent. In 2.1.207, custom agents are no longer enumerated in the built-in agent registry — they are exclusively loaded via `--append-system-prompt-file <path>` (which references `.claude/agents/<role>.md`). The `--append-system-prompt-file` flag is the **canonical load-bearing identity mechanism** and is already wired in the heredoc. The `--agent` flag was redundant, and now broken.

## Decision

**Remove `--agent "${role}"` flag from the `scripts/dev-studio-start.sh` heredoc (line 149).** Identity continues to load via the already-wired `--append-system-prompt-file "$REPO_ROOT/.claude/agents/${role}.md"` flag.

### Diff spec (single line, line 149)

**Before** (broken on CLI ≥2.1.207):

```bash
claude --dangerously-skip-permissions --agent "${role}" --append-system-prompt-file "$REPO_ROOT/.claude/agents/${role}.md" "\$KICKOFF_PROMPT"
```

**After** (works on CLI ≥2.1.207):

```bash
claude --dangerously-skip-permissions --append-system-prompt-file "$REPO_ROOT/.claude/agents/${role}.md" "\$KICKOFF_PROMPT"
```

Single-line removal (1 token: ` --agent "${role}"`). No other changes needed — `--append-system-prompt-file` is the load-bearing identity mechanism.

### Alternatives considered

| Alternative | Pros | Cons | Decision |
|---|---|---|---|
| `--agents <json>` (JSON spec, new flag in 2.1.207) | Built-in flag | JSON escape overhead for 5 roles, inline size tax, maintainability burden | ❌ Rejected |
| Pin old CLI version (<2.1.207) | No code change | Security + feature regression risk, blocks future Claude Code features | ❌ Rejected |
| Wrapper script (translate `--agent` → `--append-system-prompt-file`) | Backward compatible | Extra layer, indirection, harder to debug, YAGNI | ❌ Rejected |
| **Drop `--agent`, keep `--append-system-prompt-file`** | Minimal diff, already wired, prod-verified | None | ✅ **Adopted** |

## Consequences

### Positive

- ✅ Works on Claude Code CLI ≥2.1.207 (current main branch)
- ✅ Single-token change (low diff surface, easy to review + backport)
- ✅ `--append-system-prompt-file` is already wired + smoke tested
- ✅ Forward-portable to AtilCalculator (same heredoc pattern, sister-task #90)

### Negative (accepted)

- ⚠️ Pane title match (`agent-watch.sh` line ~1468) fails every poll — fallback index map (window:main, panes 0-4 = orch/pm/arch/dev/tester) is the safety net, working as designed
- ⚠️ Sister-PR scope is template-only on this PR; AtilCalculator sister-PR (forward-port) tracked separately per RETRO-023 cross-repo doctrine
- ⚠️ Pre-2.1.207 deployments that relied on the redundant `--agent` flag will see no functional change (silent warning, not error in older CLIs)

### Neutral

- 🔄 Sister-pattern: ADR-0059 cluster-squash (recent Sprint 28 forward-port neighbor)
- 🔄 d-test framework (ADR-0049) + RED-first (ADR-0044) — sister task #89 follows dNNNN-cli-arg-hygiene pattern, lands atomic per ADR-0055 §1

## Future work (out of scope for this ADR)

- Pane targeting hardening (title match fragility under OSC-2 overrides) — Sprint 30+
- Forward-port to AtilCalculator `scripts/dev-studio-start.sh` (separate sister-PR, SHA lock per AtilCalculator v0.3.0 tag)
- Sister-PR to `dev-studio-launcher` if `dev-studio-start.sh` is symlinked (verify in launcher audit-baseline)
- Backport to any pre-2.1.207 deployments that may have other `--agent`-dependent code paths

## Reversibility

Reversible by reverting the single-token change. Pre-2.1.207 versions of Claude Code silently ignored the redundant `--agent` flag (warning, not error), so rollback does NOT break older CLI deployments. Rollback risk: **negligible**.

## Sister-task dependency graph

| Task | Owner | Status | Depends on |
|---|---|---|---|
| Issue #88 (this ADR draft) | @architect | In progress | — |
| Sister #89 (dNNNN-cli-arg-hygiene d-test RED-first) | @tester | Pending arch PR | This ADR merge-ready |
| Sister #90 (impl PR — remove `--agent` from heredoc) | @developer | Pending tester 🟢 | Sister #89 GREEN |
| Owner squash-merge | @atilcan65 | Pending all peer 🟢 | Sister #90 merge-ready |

## Cross-references

- **Issue #88** — template-gap-close origin + diagnostic body (this ADR's primary source)
- **Sprint 29 audit-baseline §20.1** — pre-allocation map that reserved ADR-0060 (now superseded by this ADR)
- **AtilCalculator ADR-0060** (ac-mapping-verification-doctrine) — NOT a sister-pattern (different topic), reference for AC Mapping doctrine canonical home
- **RETRO-018 W6** — branch-ownership matrix + reservation-repurposing doctrine
- **RETRO-023** — cross-repo workstream doctrine (forward-port target: AtilCalculator)
- **ADR-0033** — dual-channel peer-poke (used to wake tester + developer on this PR)
- **ADR-0045** — 9-Lens review framework (architect verdict gate on impl PR)
- **ADR-0024** — verdict-by time-anchor (used by peer-poke auto-verdict-by hook on PR)

— @architect (Sprint 29 cycle ~#1600, post-REPRIME)